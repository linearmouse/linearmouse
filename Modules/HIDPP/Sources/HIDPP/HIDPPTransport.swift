// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

public struct HIDPPTransport {
    private enum ResponseResult {
        case response(HIDPPResponse)
        case busy
        case failure
    }

    private static let maximumBusyAttempts = 3

    private let device: HIDPPDeviceIO
    private let reportID: UInt8
    private let reportLength: Int
    private let deviceIndex: UInt8
    private let acceptedReplyIndices: Set<UInt8>
    private let shouldContinue: () -> Bool
    public let isReceiverRoutedDevice: Bool

    public init?(
        device: HIDPPDeviceIO,
        deviceIndex: UInt8?,
        shouldContinue: @escaping () -> Bool = { true }
    ) {
        let maxOutputReportSize = device.maxOutputReportSize ?? 0
        if maxOutputReportSize >= HIDPPConstants.longReportLength {
            reportID = HIDPPConstants.longReportID
            reportLength = HIDPPConstants.longReportLength
        } else if maxOutputReportSize >= HIDPPConstants.shortReportLength {
            reportID = HIDPPConstants.shortReportID
            reportLength = HIDPPConstants.shortReportLength
        } else {
            return nil
        }

        self.device = device
        self.deviceIndex = deviceIndex ?? HIDPPConstants.receiverIndex
        self.shouldContinue = shouldContinue
        isReceiverRoutedDevice = deviceIndex != nil
        acceptedReplyIndices = deviceIndex.map { Set([$0]) } ?? HIDPPConstants.directReplyIndices
    }

    public func featureIndex(for featureID: HIDPPFeatureID) -> UInt8? {
        guard let response = request(featureIndex: 0x00, function: 0x00, parameters: featureID.bytes),
              let featureIndex = response.payload.first,
              featureIndex != 0
        else {
            return nil
        }

        return featureIndex
    }

    public func request(
        featureIndex: UInt8,
        function: UInt8,
        parameters: [UInt8]
    ) -> HIDPPResponse? {
        request(
            featureIndex: featureIndex,
            function: function,
            parameters: parameters,
            performsSingleTransaction: false
        )
    }

    public func requestOnce(
        featureIndex: UInt8,
        function: UInt8,
        parameters: [UInt8]
    ) -> HIDPPResponse? {
        request(
            featureIndex: featureIndex,
            function: function,
            parameters: parameters,
            performsSingleTransaction: true
        )
    }

    private func request(
        featureIndex: UInt8,
        function: UInt8,
        parameters: [UInt8],
        performsSingleTransaction: Bool
    ) -> HIDPPResponse? {
        for attempt in 1 ... Self.maximumBusyAttempts {
            switch response(
                featureIndex: featureIndex,
                function: function,
                parameters: parameters,
                performsSingleTransaction: performsSingleTransaction
            ) {
            case let .response(response):
                return response
            case .busy where attempt < Self.maximumBusyAttempts:
                continue
            case .busy, .failure:
                return nil
            }
        }

        return nil
    }

    private func response(
        featureIndex: UInt8,
        function: UInt8,
        parameters: [UInt8],
        performsSingleTransaction: Bool
    ) -> ResponseResult {
        // A HID++ report has a four-byte header. Do not silently drop parameters
        // that do not fit in the negotiated report size: callers must know that
        // the request was not representable before any I/O has taken place.
        guard parameters.count <= reportLength - 4,
              shouldContinue() else {
            return .failure
        }

        let address = address(for: function)
        let report = makeReport(
            featureIndex: featureIndex,
            address: address,
            parameters: parameters
        )
        let matching: (Data) -> Bool = { response in
            let reply = [UInt8](response)
            guard reply.count >= HIDPPConstants.shortReportLength,
                  [HIDPPConstants.shortReportID, HIDPPConstants.longReportID].contains(reply[0]),
                  acceptedReplyIndices.contains(reply[1])
            else {
                return false
            }

            if reply[2] == 0xFF {
                return reply.count >= 6 && reply[3] == featureIndex && reply[4] == address
            }

            return reply[2] == featureIndex && reply[3] == address
        }
        let response: Data?
        if let cancellableDevice = device as? HIDPPCancellableDeviceIO {
            if performsSingleTransaction {
                response = cancellableDevice.performSynchronousOutputReportRequestOnce(
                    report,
                    timeout: HIDPPConstants.timeout,
                    matching: matching,
                    until: shouldContinue
                )
            } else {
                response = cancellableDevice.performSynchronousOutputReportRequest(
                    report,
                    timeout: HIDPPConstants.timeout,
                    matching: matching,
                    until: shouldContinue
                )
            }
        } else if performsSingleTransaction {
            response = device.performSynchronousOutputReportRequestOnce(
                report,
                timeout: HIDPPConstants.timeout,
                matching: matching
            )
        } else {
            response = device.performSynchronousOutputReportRequest(
                report,
                timeout: HIDPPConstants.timeout,
                matching: matching
            )
        }

        guard shouldContinue(), let response else {
            return .failure
        }

        let reply = [UInt8](response)
        guard reply.count >= 4 else {
            return .failure
        }

        if reply[2] == 0xFF {
            let hidpp20BusyError: UInt8 = 0x08
            return reply.count >= 6 && reply[5] == hidpp20BusyError ? .busy : .failure
        }

        return .response(.init(payload: Array(reply.dropFirst(4))))
    }

    private func address(for function: UInt8) -> UInt8 {
        (function << 4) | HIDPPConstants.softwareID
    }

    private func makeReport(
        featureIndex: UInt8,
        address: UInt8,
        parameters: [UInt8]
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: reportLength)
        bytes[0] = reportID
        bytes[1] = deviceIndex
        bytes[2] = featureIndex
        bytes[3] = address
        for (index, parameter) in parameters.enumerated() where index + 4 < bytes.count {
            bytes[index + 4] = parameter
        }
        return Data(bytes)
    }
}
