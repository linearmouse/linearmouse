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
    private let requestTimeout: TimeInterval
    private let requestDeadline: Date?
    public let receiverSlot: UInt8?
    public let isReceiverRoutedDevice: Bool

    public init?(
        device: HIDPPDeviceIO,
        deviceIndex: UInt8?,
        requestTimeout: TimeInterval = HIDPPConstants.timeout,
        deadline: Date? = nil,
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
        self.requestTimeout = max(0, requestTimeout)
        requestDeadline = deadline
        receiverSlot = deviceIndex
        isReceiverRoutedDevice = receiverSlot != nil
        acceptedReplyIndices = deviceIndex.map { Set([$0]) } ?? HIDPPConstants.directReplyIndices
    }

    public func featureIndex(for featureID: HIDPPFeatureID) -> UInt8? {
        featureIndex(for: featureID, deadline: nil) { true }
    }

    public func featureIndex(
        for featureID: HIDPPFeatureID,
        deadline: Date? = nil,
        until operationShouldContinue: @escaping () -> Bool
    ) -> UInt8? {
        guard let response = request(
            featureIndex: 0x00,
            function: 0x00,
            parameters: featureID.bytes,
            deadline: deadline,
            until: operationShouldContinue
        ),
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
            deadline: nil
        ) { true }
    }

    public func request(
        featureIndex: UInt8,
        function: UInt8,
        parameters: [UInt8],
        deadline: Date? = nil,
        until operationShouldContinue: @escaping () -> Bool
    ) -> HIDPPResponse? {
        request(
            featureIndex: featureIndex,
            function: function,
            parameters: parameters,
            performsSingleTransaction: false,
            deadline: deadline,
            operationShouldContinue: operationShouldContinue
        )
    }

    public func requestOnce(
        featureIndex: UInt8,
        function: UInt8,
        parameters: [UInt8]
    ) -> HIDPPResponse? {
        requestOnce(
            featureIndex: featureIndex,
            function: function,
            parameters: parameters,
            deadline: nil
        ) { true }
    }

    public func requestOnce(
        featureIndex: UInt8,
        function: UInt8,
        parameters: [UInt8],
        deadline: Date? = nil,
        until operationShouldContinue: @escaping () -> Bool
    ) -> HIDPPResponse? {
        request(
            featureIndex: featureIndex,
            function: function,
            parameters: parameters,
            performsSingleTransaction: true,
            deadline: deadline,
            operationShouldContinue: operationShouldContinue
        )
    }

    private func request(
        featureIndex: UInt8,
        function: UInt8,
        parameters: [UInt8],
        performsSingleTransaction: Bool,
        deadline: Date?,
        operationShouldContinue: @escaping () -> Bool
    ) -> HIDPPResponse? {
        for attempt in 1 ... Self.maximumBusyAttempts {
            switch response(
                featureIndex: featureIndex,
                function: function,
                parameters: parameters,
                performsSingleTransaction: performsSingleTransaction,
                deadline: deadline,
                operationShouldContinue: operationShouldContinue
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
        performsSingleTransaction: Bool,
        deadline: Date?,
        operationShouldContinue: @escaping () -> Bool
    ) -> ResponseResult {
        let effectiveDeadline: Date?
        switch (requestDeadline, deadline) {
        case let (lhs?, rhs?):
            effectiveDeadline = min(lhs, rhs)
        case let (value?, nil), let (nil, value?):
            effectiveDeadline = value
        case (nil, nil):
            effectiveDeadline = nil
        }
        let requestShouldContinue = {
            shouldContinue()
                && operationShouldContinue()
                && effectiveDeadline.map { Date() < $0 } != false
        }
        // A HID++ report has a four-byte header. Do not silently drop parameters
        // that do not fit in the negotiated report size: callers must know that
        // the request was not representable before any I/O has taken place.
        guard parameters.count <= reportLength - 4,
              requestShouldContinue() else {
            return .failure
        }

        let timeout = min(
            requestTimeout,
            effectiveDeadline.map { max(0, $0.timeIntervalSinceNow) } ?? requestTimeout
        )
        guard timeout > 0 else {
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
                    timeout: timeout,
                    matching: matching,
                    until: requestShouldContinue
                )
            } else {
                response = cancellableDevice.performSynchronousOutputReportRequest(
                    report,
                    timeout: timeout,
                    matching: matching,
                    until: requestShouldContinue
                )
            }
        } else if performsSingleTransaction {
            response = device.performSynchronousOutputReportRequestOnce(
                report,
                timeout: timeout,
                matching: matching
            )
        } else {
            response = device.performSynchronousOutputReportRequest(
                report,
                timeout: timeout,
                matching: matching
            )
        }

        guard requestShouldContinue(), let response else {
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
