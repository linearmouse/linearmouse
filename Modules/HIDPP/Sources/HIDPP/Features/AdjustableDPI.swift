// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

public struct AdjustableDPI: HIDPPFeature {
    public static let featureID = HIDPPFeatureID.adjustableDPI

    enum SupportedDPIList: Equatable {
        case complete([Int])
        case incomplete
    }

    private enum Constants {
        static let getSensorDPIListFunction: UInt8 = 0x01
        static let getSensorDPIFunction: UInt8 = 0x02
        static let setSensorDPIFunction: UInt8 = 0x03
        static let defaultDPIRange = 100 ... 32_000
        static let defaultDPIStep = 50
    }

    private let supportedDPIList: SupportedDPIList

    public var supportedDPI: [Int] {
        guard case let .complete(values) = supportedDPIList else {
            return []
        }
        return values
    }

    private let transport: HIDPPTransport
    private let featureIndex: UInt8

    public init(transport: HIDPPTransport, featureIndex: UInt8) {
        let supportedDPIList = Self.loadSupportedDPI(
            transport: transport,
            featureIndex: featureIndex,
            deadline: nil
        ) { true }
        self.init(
            transport: transport,
            featureIndex: featureIndex,
            supportedDPIList: supportedDPIList
        )
    }

    public init?(
        transport: HIDPPTransport,
        featureIndex: UInt8,
        deadline: Date?,
        until shouldContinue: @escaping () -> Bool
    ) {
        guard case let .complete(supportedDPI) = Self.loadSupportedDPI(
            transport: transport,
            featureIndex: featureIndex,
            deadline: deadline,
            shouldContinue: shouldContinue
        ) else {
            return nil
        }
        self.init(
            transport: transport,
            featureIndex: featureIndex,
            supportedDPIList: .complete(supportedDPI)
        )
    }

    public init(
        transport: HIDPPTransport,
        featureIndex: UInt8,
        supportedDPI: [Int]
    ) {
        self.init(
            transport: transport,
            featureIndex: featureIndex,
            supportedDPIList: .complete(Self.normalizedSupportedDPI(supportedDPI))
        )
    }

    private init(
        transport: HIDPPTransport,
        featureIndex: UInt8,
        supportedDPIList: SupportedDPIList
    ) {
        self.transport = transport
        self.featureIndex = featureIndex
        self.supportedDPIList = supportedDPIList
    }

    public var receiverSlot: UInt8? {
        transport.receiverSlot
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
        currentDPI(deadline: nil) { true }
    }

    public func currentDPI(
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool
    ) -> Int? {
        guard let response = transport.request(
            featureIndex: featureIndex,
            function: Constants.getSensorDPIFunction,
            parameters: [],
            deadline: deadline,
            until: shouldContinue
        ),
            response.payload.count >= 5
        else {
            return nil
        }

        let current = Self.uint16(response.payload[1], response.payload[2])
        return current > 0 ? current : nil
    }

    public func setDPI(_ dpi: Int) -> Int? {
        setDPI(dpi, deadline: nil) { true }
    }

    public func setDPI(
        _ dpi: Int,
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool
    ) -> Int? {
        let targetDPI = supportedDPI(nearestTo: dpi)
        return setRepresentableDPI(
            targetDPI,
            deadline: deadline,
            until: shouldContinue
        )
    }

    /// Restores a value previously read from this exact sensor without
    /// quantizing it through a capability list that may be incomplete because
    /// a bounded request expired between pages.
    public func setDPIExactly(
        _ dpi: Int,
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool
    ) -> Int? {
        guard (1 ... Int(UInt16.max)).contains(dpi) else {
            return nil
        }
        return setRepresentableDPI(
            dpi,
            deadline: deadline,
            until: shouldContinue
        )
    }

    private func setRepresentableDPI(
        _ targetDPI: Int,
        deadline: Date?,
        until shouldContinue: @escaping () -> Bool
    ) -> Int? {
        let parameters = [0x00, UInt8((targetDPI >> 8) & 0xFF), UInt8(targetDPI & 0xFF)]

        let response = transport.requestOnce(
            featureIndex: featureIndex,
            function: Constants.setSensorDPIFunction,
            parameters: parameters,
            deadline: deadline,
            until: shouldContinue
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

    static func loadSupportedDPI(
        transport: HIDPPTransport,
        featureIndex: UInt8,
        deadline: Date?,
        shouldContinue: @escaping () -> Bool
    ) -> SupportedDPIList {
        let result = readSupportedDPIBytes(
            transport: transport,
            featureIndex: featureIndex,
            deadline: deadline,
            shouldContinue: shouldContinue
        )
        guard result.isComplete else {
            return .incomplete
        }
        return .complete(normalizedSupportedDPI(parseSupportedDPI(result.bytes)))
    }

    private static func readSupportedDPIBytes(
        transport: HIDPPTransport,
        featureIndex: UInt8,
        deadline: Date?,
        shouldContinue: @escaping () -> Bool
    ) -> (bytes: [UInt8], isComplete: Bool) {
        var bytes = [UInt8]()

        for index in UInt8.min ... UInt8.max {
            guard let response = transport.request(
                featureIndex: featureIndex,
                function: Constants.getSensorDPIListFunction,
                parameters: [0x00, 0x00, index],
                deadline: deadline,
                until: shouldContinue
            ),
                response.payload.count > 1
            else {
                break
            }

            let payload = response.payload
            bytes.append(contentsOf: payload.dropFirst())

            if bytes.count >= 2, Array(bytes.suffix(2)) == [0x00, 0x00] {
                return (bytes, true)
            }
        }

        return (bytes, false)
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
