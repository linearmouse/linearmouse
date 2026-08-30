// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

public struct AdjustableDPI: HIDPPFeature {
    public static let featureID = HIDPPFeatureID.adjustableDPI

    private enum Constants {
        static let getSensorDPIListFunction: UInt8 = 0x01
        static let getSensorDPIFunction: UInt8 = 0x02
        static let setSensorDPIFunction: UInt8 = 0x03
        static let defaultDPIRange = 100 ... 32_000
        static let defaultDPIStep = 50
    }

    public let supportedDPI: [Int]

    private let transport: HIDPPTransport
    private let featureIndex: UInt8

    public init(transport: HIDPPTransport, featureIndex: UInt8) {
        self.init(
            transport: transport,
            featureIndex: featureIndex,
            supportedDPI: Self.readSupportedDPI(
                transport: transport,
                featureIndex: featureIndex
            )
        )
    }

    public init(
        transport: HIDPPTransport,
        featureIndex: UInt8,
        supportedDPI: [Int]
    ) {
        self.transport = transport
        self.featureIndex = featureIndex
        self.supportedDPI = Self.normalizedSupportedDPI(supportedDPI)
    }

    public var dpiRange: ClosedRange<Int> {
        guard let first = supportedDPI.first, let last = supportedDPI.last else {
            return Constants.defaultDPIRange
        }

        return first ... last
    }

    public var dpiStep: Int {
        guard supportedDPI.count >= 2 else {
            return Constants.defaultDPIStep
        }

        let differences = zip(supportedDPI, supportedDPI.dropFirst()).map { $1 - $0 }.filter { $0 > 0 }
        return differences.min() ?? Constants.defaultDPIStep
    }

    public func currentDPI() -> Int? {
        guard let response = transport.request(
            featureIndex: featureIndex,
            function: Constants.getSensorDPIFunction,
            parameters: []
        ),
            response.payload.count >= 5
        else {
            return nil
        }

        return currentDPI(from: Self.currentDPICandidates(from: response.payload))
    }

    private func currentDPI(from candidates: [Int]) -> Int? {
        if !supportedDPI.isEmpty,
           let supportedCandidate = candidates.first(where: { supportedDPI.contains($0) }) {
            return supportedCandidate
        }

        return candidates.first { $0 > 0 }
    }

    public func setDPI(_ dpi: Int) -> Int? {
        let targetDPI = supportedDPI(nearestTo: dpi)
        let parameters = [0x00, UInt8((targetDPI >> 8) & 0xFF), UInt8(targetDPI & 0xFF)]

        let response = transport.requestOnce(
            featureIndex: featureIndex,
            function: Constants.setSensorDPIFunction,
            parameters: parameters
        )

        return response == nil ? nil : targetDPI
    }

    public func supportedDPI(nearestTo dpi: Int) -> Int {
        guard !supportedDPI.isEmpty else {
            return Self.defaultSupportedDPI(nearestTo: dpi)
        }

        return supportedDPI.min { lhs, rhs in
            abs(lhs - dpi) < abs(rhs - dpi)
        } ?? dpi
    }

    public func canRepresentDPI(_ dpi: Int) -> Bool {
        if supportedDPI.isEmpty {
            return Self.isSaneDPI(dpi)
        }

        return supportedDPI.contains(dpi)
    }

    private static func readSupportedDPI(transport: HIDPPTransport, featureIndex: UInt8) -> [Int] {
        parseSupportedDPI(readSupportedDPIBytes(
            transport: transport,
            featureIndex: featureIndex
        ))
    }

    private static func readSupportedDPIBytes(
        transport: HIDPPTransport,
        featureIndex: UInt8
    ) -> [UInt8] {
        var bytes = [UInt8]()

        for index in UInt8.min ... UInt8.max {
            guard let response = transport.request(
                featureIndex: featureIndex,
                function: Constants.getSensorDPIListFunction,
                parameters: [0x00, 0x00, index]
            ),
                response.payload.count > 1
            else {
                break
            }

            let payload = response.payload
            bytes.append(contentsOf: payload.dropFirst())

            if bytes.count >= 2, Array(bytes.suffix(2)) == [0x00, 0x00] {
                break
            }
        }

        return bytes
    }

    private static func currentDPICandidates(from payload: [UInt8]) -> [Int] {
        guard payload.count >= 5 else {
            return []
        }

        return [
            uint16(payload[1], payload[2]),
            uint16(payload[3], payload[4])
        ]
    }

    public static func parseSupportedDPI(_ bytes: [UInt8]) -> [Int] {
        var values = [Int]()
        var index = 0

        while index + 1 < bytes.count {
            let value = uint16(bytes[index], bytes[index + 1])
            if value == 0 {
                break
            }

            if value >> 13 == 0b111 {
                guard index + 3 < bytes.count, let previous = values.last else {
                    break
                }

                let step = value & 0x1FFF
                let last = uint16(bytes[index + 2], bytes[index + 3])
                guard step > 0, last > previous else {
                    break
                }

                values.append(contentsOf: stride(from: previous + step, through: last, by: step))
                index += 4
            } else {
                values.append(value)
                index += 2
            }
        }

        return values
    }

    private static func normalizedSupportedDPI(_ values: [Int]) -> [Int] {
        Array(Set(values.filter(isSaneDPI))).sorted()
    }

    private static func isSaneDPI(_ dpi: Int) -> Bool {
        Constants.defaultDPIRange.contains(dpi) && dpi.isMultiple(of: Constants.defaultDPIStep)
    }

    private static func defaultSupportedDPI(nearestTo dpi: Int) -> Int {
        let clamped = min(max(dpi, Constants.defaultDPIRange.lowerBound), Constants.defaultDPIRange.upperBound)
        let lowerBound = Constants.defaultDPIRange.lowerBound
        let offset = clamped - lowerBound
        let roundedOffset = Int(round(Double(offset) / Double(Constants.defaultDPIStep))) * Constants.defaultDPIStep
        return min(
            max(lowerBound + roundedOffset, Constants.defaultDPIRange.lowerBound),
            Constants.defaultDPIRange.upperBound
        )
    }

    private static func uint16(_ high: UInt8, _ low: UInt8) -> Int {
        Int(high) << 8 | Int(low)
    }
}
