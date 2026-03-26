// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Combine
import Foundation
import IOKit.hid
import ObservationToken
import os.log
import PointerKit

struct LogitechHIDPPDeviceMetadataProvider: VendorSpecificDeviceMetadataProvider {
    static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "LinearMouse",
        category: "LogitechHIDPP"
    )

    enum Constants {
        static let vendorID = 0x046D
        static let softwareID: UInt8 = 0x08
        static let shortReportID: UInt8 = 0x10
        static let longReportID: UInt8 = 0x11
        static let shortReportLength = 7
        static let longReportLength = 20
        static let timeout: TimeInterval = 2.0

        static let receiverIndex: UInt8 = 0xFF
        static let directReplyIndices: Set<UInt8> = [0x00, 0xFF]
        static let receiverNotificationFlagsRegister: UInt8 = 0x00
        static let receiverConnectionStateRegister: UInt8 = 0x02
        static let receiverInfoRegister: UInt8 = 0xB5
        static let receiverWirelessNotifications: UInt32 = 0x000100
        static let receiverSoftwarePresentNotifications: UInt32 = 0x000800
    }

    enum FeatureID: UInt16 {
        case root = 0x0000
        case deviceName = 0x0005
        case deviceFriendlyName = 0x0007
        case batteryStatus = 0x1000
        case batteryVoltage = 0x1001
        case unifiedBattery = 0x1004
        case reprogControlsV4 = 0x1B04
        case adcMeasurement = 0x1F20
    }

    enum ReprogControlsV4 {
        static let gestureButtonControlIDs: Set<UInt16> = [0x00C3, 0x00D0]
        static let virtualGestureButtonControlIDs: Set<UInt16> = [0x00D7]
        static let gestureButtonTaskIDs: Set<UInt16> = [0x009C, 0x00A9, 0x00AD]
        static let virtualGestureButtonTaskIDs: Set<UInt16> = [0x00B4]
        /// Control IDs that should never be diverted because they are natively handled by the OS.
        /// Diverting these would break their default behavior (click, back/forward, etc.).
        static let nativeControlIDs: Set<UInt16> = [
            0x0050, 0x0051, 0x0052, // Left / right / middle mouse button
            0x0053, 0x0056, // Standard back/forward
            0x00CE, 0x00CF, // Alternate back/forward
            0x00D9, 0x00DB // Additional back/forward variants
        ]
        /// Reserved button number written into config for virtual controls.
        /// Older versions do not generate this button, so persisted mappings will not misfire after downgrade.
        /// This value is intentionally vendor-agnostic so other protocol-backed controls can reuse it later.
        static let reservedVirtualButtonNumber = 0x1000

        static let getControlCountFunction: UInt8 = 0x00
        static let getControlInfoFunction: UInt8 = 0x01
        static let getControlReportingFunction: UInt8 = 0x02
        static let setControlReportingFunction: UInt8 = 0x03

        struct ControlFlags: OptionSet {
            let rawValue: UInt16

            static let mouseButton = Self(rawValue: 1 << 0)
            static let reprogrammable = Self(rawValue: 1 << 4)
            static let divertable = Self(rawValue: 1 << 5)
            static let persistentlyDivertable = Self(rawValue: 1 << 6)
            static let virtual = Self(rawValue: 1 << 7)
            static let rawXY = Self(rawValue: 1 << 8)
            static let forceRawXY = Self(rawValue: 1 << 9)
        }

        struct ReportingFlags: OptionSet {
            let rawValue: UInt16

            static let diverted = Self(rawValue: 1 << 0)
            static let persistentlyDiverted = Self(rawValue: 1 << 2)
            static let rawXYDiverted = Self(rawValue: 1 << 4)
            static let forceRawXYDiverted = Self(rawValue: 1 << 6)
        }
    }

    private enum DeviceKind: UInt8 {
        case keyboard = 0x01
        case mouse = 0x02
        case trackball = 0x08
        case touchpad = 0x09
    }

    struct Response {
        let payload: [UInt8]
    }

    struct ReceiverSlotInfo {
        let slot: UInt8
        let kind: UInt8
        let name: String?
        let productID: Int?
        let serialNumber: String?
        let batteryLevel: Int?
        let hasLiveMetadata: Bool
    }

    struct ReceiverSlotMetadata {
        let slot: UInt8
        let name: String?
        let batteryLevel: Int?
    }

    struct ReceiverConnectionSnapshot: Equatable {
        let isConnected: Bool
        let kind: UInt8?
    }

    struct ReceiverSlotDiscovery {
        let slots: [ReceiverSlotInfo]
        let connectionSnapshots: [UInt8: ReceiverConnectionSnapshot]
    }

    struct ReceiverPointingDeviceDiscovery {
        let identities: [ReceiverLogicalDeviceIdentity]
        let connectionSnapshots: [UInt8: ReceiverConnectionSnapshot]
        let liveReachableSlots: Set<UInt8>
    }

    struct ReceiverSlotMatchCandidate {
        let slot: UInt8
        let kind: UInt8
        let name: String?
        let serialNumber: String?
        let productID: Int?
        let batteryLevel: Int?
        let hasLiveMetadata: Bool
    }

    private enum ApproximateBatteryLevel: UInt8 {
        case full = 8
        case good = 4
        case low = 2
        case critical = 1

        var percent: Int {
            switch self {
            case .full:
                return 100
            case .good:
                return 50
            case .low:
                return 20
            case .critical:
                return 5
            }
        }
    }

    let matcher = VendorSpecificDeviceMatcher(
        vendorID: Constants.vendorID,
        productIDs: nil,
        transports: [PointerDeviceTransportName.bluetoothLowEnergy, PointerDeviceTransportName.usb]
    )

    func matches(device: VendorSpecificDeviceContext) -> Bool {
        let maxInputReportSize = device.maxInputReportSize ?? 0
        let maxOutputReportSize = device.maxOutputReportSize ?? 0

        if isReceiverVendorChannel(device) {
            return false
        }

        return matcher.matches(device: device)
            && maxInputReportSize >= Constants.shortReportLength
            && maxOutputReportSize >= Constants.shortReportLength
    }

    func metadata(for device: VendorSpecificDeviceContext) -> VendorSpecificDeviceMetadata? {
        if let directTransport = directTransport(for: device) {
            return metadata(using: directTransport)
        }

        if let receiverTransport = receiverTransport(for: device) {
            return metadata(using: receiverTransport)
        }

        return nil
    }

    func receiverPointingDeviceDiscovery(for device: VendorSpecificDeviceContext) -> ReceiverPointingDeviceDiscovery {
        guard device.transport == PointerDeviceTransportName.usb else {
            os_log(
                "Skip receiver discovery for non-USB device: name=%{public}@ transport=%{public}@",
                log: Self.log,
                type: .info,
                device.name,
                device.transport ?? "(nil)"
            )
            return .init(identities: [], connectionSnapshots: [:], liveReachableSlots: [])
        }

        guard let locationID = device.locationID else {
            os_log(
                "Skip receiver discovery without locationID: name=%{public}@",
                log: Self.log,
                type: .info,
                device.name
            )
            return .init(identities: [], connectionSnapshots: [:], liveReachableSlots: [])
        }

        guard let receiverChannel = openReceiverChannel(for: device) else {
            os_log(
                "Failed to open receiver channel: locationID=%{public}d name=%{public}@",
                log: Self.log,
                type: .info,
                locationID,
                device.product ?? device.name
            )
            return .init(identities: [], connectionSnapshots: [:], liveReachableSlots: [])
        }

        let discovery = receiverPointingDeviceDiscovery(for: device, using: receiverChannel)
        let slots = discovery.identities

        let slotSummary = slots.map { identity in
            let battery = identity.batteryLevel.map(String.init) ?? "(nil)"
            let name = identity.name
            return "slot=\(identity.slot) kind=\(identity.kind.rawValue) name=\(name) battery=\(battery)"
        }
        .joined(separator: ", ")

        os_log(
            "Receiver discovery produced identities: locationID=%{public}d count=%{public}u identities=%{public}@",
            log: Self.log,
            type: .info,
            locationID,
            UInt32(slots.count),
            slotSummary
        )

        return discovery
    }

    func receiverPointingDeviceIdentities(for device: VendorSpecificDeviceContext) -> [ReceiverLogicalDeviceIdentity] {
        receiverPointingDeviceDiscovery(for: device).identities
    }

    func openReceiverChannel(for device: VendorSpecificDeviceContext) -> LogitechReceiverChannel? {
        guard device.transport == PointerDeviceTransportName.usb,
              let locationID = device.locationID
        else {
            return nil
        }

        return LogitechReceiverChannel.open(locationID: locationID)
    }

    func receiverSlot(for device: VendorSpecificDeviceContext) -> UInt8? {
        guard device.transport == PointerDeviceTransportName.usb,
              let locationID = device.locationID,
              let receiverChannel = LogitechReceiverChannel.open(locationID: locationID)
        else {
            return nil
        }

        return receiverSlot(for: device, using: receiverChannel)
    }

    func receiverSlot(for device: VendorSpecificDeviceContext, using receiver: LogitechReceiverChannel) -> UInt8? {
        discoverReceiverSlot(for: device, using: receiver)?.slot
    }

    func receiverPointingDeviceDiscovery(
        for device: VendorSpecificDeviceContext,
        using receiverChannel: LogitechReceiverChannel
    ) -> ReceiverPointingDeviceDiscovery {
        receiverChannel.discoverPointingDeviceDiscovery(baseName: device.product ?? device.name)
    }

    func receiverSlotIdentity(
        for device: VendorSpecificDeviceContext,
        slot: UInt8,
        connectionSnapshot: ReceiverConnectionSnapshot?,
        using receiverChannel: LogitechReceiverChannel
    ) -> ReceiverLogicalDeviceIdentity? {
        guard let locationID = receiverChannel.locationID else {
            return nil
        }

        guard let slotInfo = receiverChannel.discoverSlotInfo(slot, connectionSnapshot: connectionSnapshot) else {
            return nil
        }

        guard let kind = ReceiverLogicalDeviceKind(rawValue: slotInfo.kind), kind.isPointingDevice else {
            return nil
        }

        return ReceiverLogicalDeviceIdentity(
            receiverLocationID: locationID,
            slot: slot,
            kind: kind,
            name: slotInfo.name ?? device.product ?? device.name,
            serialNumber: slotInfo.serialNumber,
            productID: slotInfo.productID,
            batteryLevel: slotInfo.batteryLevel
        )
    }

    func waitForReceiverConnectionChange(
        for device: VendorSpecificDeviceContext,
        timeout: TimeInterval,
        until shouldContinue: @escaping () -> Bool
    ) -> [UInt8: ReceiverConnectionSnapshot] {
        guard device.transport == PointerDeviceTransportName.usb,
              let locationID = device.locationID,
              let receiverChannel = LogitechReceiverChannel.open(locationID: locationID)
        else {
            os_log(
                "Skip receiver wait because channel is unavailable: name=%{public}@ transport=%{public}@ locationID=%{public}@",
                log: Self.log,
                type: .info,
                device.name,
                device.transport ?? "(nil)",
                device.locationID.map(String.init) ?? "(nil)"
            )

            let deadline = Date().addingTimeInterval(timeout)
            while shouldContinue(), Date() < deadline {
                CFRunLoopRunInMode(.defaultMode, 0.1, true)
            }
            return [:]
        }

        receiverChannel.enableWirelessNotifications()
        return receiverChannel.waitForConnectionSnapshots(timeout: timeout, until: shouldContinue)
    }

    func waitForReceiverConnectionChange(
        using receiverChannel: LogitechReceiverChannel,
        timeout: TimeInterval,
        until shouldContinue: @escaping () -> Bool
    ) -> [UInt8: ReceiverConnectionSnapshot] {
        receiverChannel.enableWirelessNotifications()
        return receiverChannel.waitForConnectionSnapshots(timeout: timeout, until: shouldContinue)
    }

    private func metadata(using transport: LogitechHIDPPTransport) -> VendorSpecificDeviceMetadata? {
        let name = readFriendlyName(using: transport) ?? readName(using: transport)
        let batteryLevel = transport
            .isReceiverRoutedDevice ? readReceiverBatteryLevel(using: transport) : readBatteryLevel(using: transport)

        if name == nil, batteryLevel == nil {
            return nil
        }

        return VendorSpecificDeviceMetadata(name: name, batteryLevel: batteryLevel)
    }

    private func directTransport(for device: VendorSpecificDeviceContext) -> LogitechHIDPPTransport? {
        guard device.transport == PointerDeviceTransportName.bluetoothLowEnergy else {
            return nil
        }

        return LogitechHIDPPTransport(device: device, deviceIndex: nil)
    }

    private func receiverTransport(for device: VendorSpecificDeviceContext) -> LogitechHIDPPTransport? {
        guard device.transport == PointerDeviceTransportName.usb,
              let locationID = device.locationID,
              let receiverChannel = LogitechReceiverChannel.open(locationID: locationID),
              let slot = discoverReceiverSlot(for: device, using: receiverChannel)?.slot
        else {
            return nil
        }

        return LogitechHIDPPTransport(device: receiverChannel, deviceIndex: slot)
    }

    private func discoverReceiverSlot(
        for device: VendorSpecificDeviceContext,
        using receiver: LogitechReceiverChannel
    ) -> ReceiverSlotMatchCandidate? {
        guard let discovery = receiver.discoverMatchCandidates(baseName: device.product ?? device.name) else {
            return nil
        }

        let slots = discovery.0

        let normalizedProduct = normalizeName(device.product ?? device.name)
        let normalizedSerial = normalizeSerial(device.serialNumber)
        let desiredProductID = device.productID

        if let serialMatch = slots.first(where: {
            normalizeSerial($0.serialNumber) == normalizedSerial && normalizedSerial != nil
        }) {
            return serialMatch
        }

        if let productIDMatch = slots.first(where: { candidate in
            guard let desiredProductID, let productID = candidate.productID else {
                return false
            }

            return productID == desiredProductID
        }) {
            return productIDMatch
        }

        if let exactNameMatch = slots.first(where: {
            guard let name = $0.name else {
                return false
            }
            return normalizeName(name) == normalizedProduct
        }) {
            return exactNameMatch
        }

        let desiredKinds = preferredReceiverDeviceKinds(for: device)
        if let kindMatch = slots.first(where: { desiredKinds.contains($0.kind) }) {
            return kindMatch
        }

        if slots.count == 1 {
            return slots[0]
        }

        return nil
    }

    fileprivate func discoverRoutedSlots(using receiver: LogitechReceiverChannel) -> [ReceiverSlotMetadata] {
        var results = [ReceiverSlotMetadata]()

        for slot in UInt8(1) ... UInt8(6) {
            guard let transport = LogitechHIDPPTransport(device: receiver, deviceIndex: slot) else {
                continue
            }

            let name = readFriendlyName(using: transport) ?? readName(using: transport)
            let batteryLevel = readReceiverBatteryLevel(using: transport)
            guard name != nil || batteryLevel != nil else {
                continue
            }

            results.append(.init(slot: slot, name: name, batteryLevel: batteryLevel))
        }

        return results
    }

    private func preferredReceiverDeviceKinds(for device: VendorSpecificDeviceContext) -> Set<UInt8> {
        guard device.primaryUsagePage == kHIDPage_GenericDesktop else {
            return []
        }

        switch device.primaryUsage {
        case kHIDUsage_GD_Mouse, kHIDUsage_GD_Pointer:
            return [DeviceKind.mouse.rawValue, DeviceKind.trackball.rawValue, DeviceKind.touchpad.rawValue]
        default:
            return []
        }
    }

    fileprivate func readFriendlyName(using transport: LogitechHIDPPTransport) -> String? {
        guard let featureIndex = transport.featureIndex(for: .deviceFriendlyName),
              let lengthResponse = transport.request(featureIndex: featureIndex, function: 0x00, parameters: []),
              let length = lengthResponse.payload.first,
              length > 0
        else {
            return nil
        }

        return readNameFragments(
            using: transport,
            featureIndex: featureIndex,
            length: Int(length),
            skipFirstPayloadByte: true
        )
    }

    fileprivate func readName(using transport: LogitechHIDPPTransport) -> String? {
        guard let featureIndex = transport.featureIndex(for: .deviceName),
              let lengthResponse = transport.request(featureIndex: featureIndex, function: 0x00, parameters: []),
              let length = lengthResponse.payload.first,
              length > 0
        else {
            return nil
        }

        return readNameFragments(
            using: transport,
            featureIndex: featureIndex,
            length: Int(length),
            skipFirstPayloadByte: false
        )
    }

    private func readNameFragments(
        using transport: LogitechHIDPPTransport,
        featureIndex: UInt8,
        length: Int,
        skipFirstPayloadByte: Bool
    ) -> String? {
        var bytes = [UInt8]()
        var offset = 0

        while offset < length {
            guard let response = transport.request(
                featureIndex: featureIndex,
                function: 0x01,
                parameters: [UInt8(offset)]
            ) else {
                return nil
            }

            let fragment = skipFirstPayloadByte ? Array(response.payload.dropFirst()) : response.payload
            if fragment.isEmpty {
                break
            }

            bytes.append(contentsOf: fragment)
            offset += fragment.count
        }

        guard !bytes.isEmpty else {
            return nil
        }

        let trimmed = Array(bytes.prefix(length).prefix { $0 != 0 })
        return String(bytes: trimmed.isEmpty ? Array(bytes.prefix(length)) : trimmed, encoding: .utf8)
    }

    fileprivate func readBatteryLevel(using transport: LogitechHIDPPTransport) -> Int? {
        if let featureIndex = transport.featureIndex(for: .batteryStatus),
           let response = transport.request(featureIndex: featureIndex, function: 0x00, parameters: []),
           response.payload.count >= 3,
           let level = response.payload.first,
           (1 ... 100).contains(level) {
            return Int(level)
        }

        if let featureIndex = transport.featureIndex(for: .unifiedBattery),
           let response = transport.request(featureIndex: featureIndex, function: 0x00, parameters: []),
           response.payload.count >= 2,
           let status = transport.request(featureIndex: featureIndex, function: 0x01, parameters: []),
           status.payload.count >= 4 {
            let exactPercent = status.payload[0]
            let supportsStateOfCharge = (response.payload[1] & 0x02) != 0
            if supportsStateOfCharge, (1 ... 100).contains(exactPercent) {
                return Int(exactPercent)
            }

            return ApproximateBatteryLevel(rawValue: status.payload[1])?.percent
        }

        if let featureIndex = transport.featureIndex(for: .batteryVoltage),
           let response = transport.request(featureIndex: featureIndex, function: 0x00, parameters: []),
           response.payload.count >= 2 {
            return estimateBatteryPercent(fromMillivolts: Int(response.payload[0]) << 8 | Int(response.payload[1]))
        }

        if let featureIndex = transport.featureIndex(for: .adcMeasurement),
           let response = transport.request(featureIndex: featureIndex, function: 0x00, parameters: []),
           response.payload.count >= 2 {
            return estimateBatteryPercent(fromMillivolts: Int(response.payload[0]) << 8 | Int(response.payload[1]))
        }

        return nil
    }

    fileprivate func readReceiverBatteryLevel(using transport: LogitechHIDPPTransport) -> Int? {
        readBatteryLevel(using: transport)
    }

    private func estimateBatteryPercent(fromMillivolts millivolts: Int) -> Int {
        let lowerBound = 3500
        let upperBound = 4200
        let clamped = max(lowerBound, min(upperBound, millivolts))
        return Int(round(Double(clamped - lowerBound) / Double(upperBound - lowerBound) * 100))
    }

    private func isReceiverVendorChannel(_ device: VendorSpecificDeviceContext) -> Bool {
        device.transport == PointerDeviceTransportName.usb
            && device.primaryUsagePage == 0xFF00
            && device.primaryUsage == 0x01
    }

    private func normalizeName(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeSerial(_ serialNumber: String?) -> String? {
        guard let serialNumber, !serialNumber.isEmpty else {
            return nil
        }

        return serialNumber.uppercased().replacingOccurrences(of: ":", with: "")
    }

    static func parseReceiverConnectionNotification(
        _ report: [UInt8]
    ) -> (slot: UInt8, snapshot: ReceiverConnectionSnapshot)? {
        guard report.count >= Constants.shortReportLength,
              report[0] == Constants.shortReportID
        else {
            return nil
        }

        switch report[2] {
        case 0x41:
            let flags = report[4]
            return (
                slot: report[1],
                snapshot: .init(isConnected: (flags & 0x40) == 0, kind: flags & 0x0F)
            )
        case 0x42:
            return (
                slot: report[1],
                snapshot: .init(isConnected: (report[3] & 0x01) == 0, kind: nil)
            )
        default:
            return nil
        }
    }

    static func parseConnectedDeviceCount(_ response: [UInt8]) -> Int? {
        guard response.count >= 6 else {
            return nil
        }

        return Int(response[5])
    }
}

struct LogitechHIDPPTransport {
    private let device: VendorSpecificDeviceContext
    private let reportID: UInt8
    private let reportLength: Int
    private let deviceIndex: UInt8
    private let acceptedReplyIndices: Set<UInt8>
    let isReceiverRoutedDevice: Bool

    init?(device: VendorSpecificDeviceContext, deviceIndex: UInt8?) {
        let maxOutputReportSize = device.maxOutputReportSize ?? 0
        if maxOutputReportSize >= LogitechHIDPPDeviceMetadataProvider.Constants.longReportLength {
            reportID = LogitechHIDPPDeviceMetadataProvider.Constants.longReportID
            reportLength = LogitechHIDPPDeviceMetadataProvider.Constants.longReportLength
        } else if maxOutputReportSize >= LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength {
            reportID = LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID
            reportLength = LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength
        } else {
            return nil
        }

        self.device = device
        self.deviceIndex = deviceIndex ?? LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex
        isReceiverRoutedDevice = deviceIndex != nil
        acceptedReplyIndices = deviceIndex.map { Set([$0]) } ?? LogitechHIDPPDeviceMetadataProvider.Constants
            .directReplyIndices
    }

    func featureIndex(for featureID: LogitechHIDPPDeviceMetadataProvider.FeatureID) -> UInt8? {
        guard let response = request(featureIndex: 0x00, function: 0x00, parameters: featureID.bytes),
              let featureIndex = response.payload.first,
              featureIndex != 0
        else {
            return nil
        }

        return featureIndex
    }

    func request(featureIndex: UInt8, function: UInt8, parameters: [UInt8]) -> LogitechHIDPPDeviceMetadataProvider
        .Response? {
        let address = (function << 4) | LogitechHIDPPDeviceMetadataProvider.Constants.softwareID
        var bytes = [UInt8](repeating: 0, count: reportLength)
        bytes[0] = reportID
        bytes[1] = deviceIndex
        bytes[2] = featureIndex
        bytes[3] = address
        for (index, parameter) in parameters.enumerated() where index + 4 < bytes.count {
            bytes[index + 4] = parameter
        }

        guard let response = device.performSynchronousOutputReportRequest(
            Data(bytes),
            timeout: LogitechHIDPPDeviceMetadataProvider.Constants.timeout,
            matching: { response in
                let reply = [UInt8](response)
                guard reply.count >= LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength,
                      [LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID,
                       LogitechHIDPPDeviceMetadataProvider.Constants.longReportID].contains(reply[0]),
                      acceptedReplyIndices.contains(reply[1])
                else {
                    return false
                }

                if reply[2] == 0xFF {
                    return reply.count >= 6 && reply[3] == featureIndex && reply[4] == address
                }

                return reply[2] == featureIndex && reply[3] == address
            }
        ) else {
            return nil
        }

        let reply = [UInt8](response)
        guard reply.count >= 4, reply[2] != 0xFF else {
            return nil
        }

        return .init(payload: Array(reply.dropFirst(4)))
    }
}

final class LogitechReceiverChannel: VendorSpecificDeviceContext {
    private enum RequestStrategy: CaseIterable {
        case outputCallback
        case featureCallback
        case outputFeatureGet
        case featureFeatureGet
        case outputInputGet
        case featureInputGet

        var requestType: IOHIDReportType {
            switch self {
            case .outputCallback, .outputFeatureGet, .outputInputGet:
                return kIOHIDReportTypeOutput
            case .featureCallback, .featureFeatureGet, .featureInputGet:
                return kIOHIDReportTypeFeature
            }
        }

        var responseType: IOHIDReportType? {
            switch self {
            case .outputCallback, .featureCallback:
                return nil
            case .outputFeatureGet, .featureFeatureGet:
                return kIOHIDReportTypeFeature
            case .outputInputGet, .featureInputGet:
                return kIOHIDReportTypeInput
            }
        }
    }

    let vendorID: Int?
    let productID: Int?
    let product: String?
    let name: String
    let serialNumber: String?
    let transport: String?
    let locationID: Int?
    let primaryUsagePage: Int?
    let primaryUsage: Int?
    let maxInputReportSize: Int?
    let maxOutputReportSize: Int?
    let maxFeatureReportSize: Int?

    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private var inputReportBuffer: UnsafeMutablePointer<UInt8>?
    private let pendingLock = NSLock()
    private let requestLock = NSLock()
    private let strategyLock = NSLock()
    private var pendingMatcher: ((Data) -> Bool)?
    private var pendingResponse: Data?
    private var pendingSemaphore: DispatchSemaphore?
    private var requestStrategy: RequestStrategy?

    private static let inputReportCallback: IOHIDReportCallback = { context, _, _, _, _, report, reportLength in
        guard let context else {
            return
        }

        let this = Unmanaged<LogitechReceiverChannel>.fromOpaque(context).takeUnretainedValue()
        this.handleInputReport(Data(bytes: report, count: reportLength))
    }

    static func open(locationID: Int) -> LogitechReceiverChannel? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching: [String: Any] = [
            kIOHIDVendorIDKey: LogitechHIDPPDeviceMetadataProvider.Constants.vendorID,
            "LocationID": locationID,
            "Transport": PointerDeviceTransportName.usb,
            kIOHIDPrimaryUsagePageKey: 0xFF00,
            kIOHIDPrimaryUsageKey: 0x01
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let hidDevice = devices.first
        else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }

        return LogitechReceiverChannel(manager: manager, device: hidDevice)
    }

    init?(manager: IOHIDManager, device: IOHIDDevice) {
        self.manager = manager
        self.device = device
        vendorID = Self.getProperty(kIOHIDVendorIDKey, from: device)
        productID = Self.getProperty(kIOHIDProductIDKey, from: device)
        product = Self.getProperty(kIOHIDProductKey, from: device)
        name = product ?? "(unknown)"
        serialNumber = Self.getProperty(kIOHIDSerialNumberKey, from: device)
        transport = Self.getProperty("Transport", from: device)
        locationID = Self.getProperty("LocationID", from: device)
        primaryUsagePage = Self.getProperty(kIOHIDPrimaryUsagePageKey, from: device)
        primaryUsage = Self.getProperty(kIOHIDPrimaryUsageKey, from: device)
        maxInputReportSize = Self.getProperty("MaxInputReportSize", from: device)
        maxOutputReportSize = Self.getProperty("MaxOutputReportSize", from: device)
        maxFeatureReportSize = Self.getProperty("MaxFeatureReportSize", from: device)

        let openStatus = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openStatus == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }

        let reportLength = max(
            maxInputReportSize ?? LogitechHIDPPDeviceMetadataProvider.Constants.longReportLength,
            LogitechHIDPPDeviceMetadataProvider.Constants.longReportLength
        )
        inputReportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportLength)
        guard let inputReportBuffer else {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }

        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(
            device,
            inputReportBuffer,
            reportLength,
            Self.inputReportCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    deinit {
        inputReportBuffer?.deallocate()
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func discoverSlots() -> LogitechHIDPPDeviceMetadataProvider.ReceiverSlotDiscovery? {
        let connectedDeviceCount = readConnectionState().flatMap { response in
            LogitechHIDPPDeviceMetadataProvider.parseConnectedDeviceCount(response)
        }
        let connectionSnapshots = discoverConnectionSnapshots()
        let snapshotSummary = connectionSnapshots.keys
            .sorted()
            .compactMap { slot -> String? in
                guard let snapshot = connectionSnapshots[slot] else {
                    return nil
                }

                let kind = snapshot.kind.map(String.init) ?? "(nil)"
                return "slot=\(slot) connected=\(snapshot.isConnected) kind=\(kind)"
            }
            .joined(separator: ", ")

        os_log(
            "Receiver slot discovery started: locationID=%{public}@ connectedCount=%{public}@ snapshots=%{public}@",
            log: LogitechHIDPPDeviceMetadataProvider.log,
            type: .info,
            locationID.map(String.init) ?? "(nil)",
            connectedDeviceCount.map(String.init) ?? "(nil)",
            snapshotSummary
        )

        var pairedSlots = [LogitechHIDPPDeviceMetadataProvider.ReceiverSlotInfo]()
        for slot in UInt8(1) ... UInt8(6) {
            guard let slotInfo = discoverSlotInfo(slot, connectionSnapshot: connectionSnapshots[slot]) else {
                os_log(
                    "Receiver slot %u has no pairing or name response",
                    log: LogitechHIDPPDeviceMetadataProvider.log,
                    type: .info,
                    slot
                )
                continue
            }

            pairedSlots.append(slotInfo)

            os_log(
                "Receiver slot %u raw candidate: name=%{public}@ kind=%{public}u battery=%{public}@",
                log: LogitechHIDPPDeviceMetadataProvider.log,
                type: .info,
                slot,
                slotInfo.name ?? "(nil)",
                UInt32(slotInfo.kind),
                slotInfo.batteryLevel.map(String.init) ?? "(nil)"
            )
        }

        let pairedSummary = pairedSlots.map { slot in
            let battery = slot.batteryLevel.map(String.init) ?? "(nil)"
            let name = slot.name ?? "(nil)"
            return "slot=\(slot.slot) kind=\(slot.kind) name=\(name) battery=\(battery)"
        }
        .joined(separator: ", ")

        os_log(
            "Receiver slot metadata discovered: locationID=%{public}@ paired=%{public}u slots=%{public}@",
            log: LogitechHIDPPDeviceMetadataProvider.log,
            type: .info,
            locationID.map(String.init) ?? "(nil)",
            UInt32(pairedSlots.count),
            pairedSummary
        )

        return pairedSlots.isEmpty ? nil : .init(slots: pairedSlots, connectionSnapshots: connectionSnapshots)
    }

    func discoverSlotInfo(
        _ slot: UInt8,
        connectionSnapshot: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot? = nil
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverSlotInfo? {
        let metadataProvider = LogitechHIDPPDeviceMetadataProvider()
        let pairingResponse = hidpp10LongRequest(
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverInfoRegister,
            subregister: UInt8(0x20 + Int(slot) - 1)
        )
        let extendedPairingResponse = hidpp10LongRequest(
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverInfoRegister,
            subregister: UInt8(0x30 + Int(slot) - 1)
        )
        let nameResponse = hidpp10LongRequest(
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverInfoRegister,
            subregister: UInt8(0x40 + Int(slot) - 1)
        )

        guard pairingResponse != nil || nameResponse != nil else {
            return nil
        }

        let kind = connectionSnapshot?.kind
            ?? pairingResponse.flatMap(Self.parseReceiverKind)
            ?? 0
        let routedTransport = LogitechHIDPPTransport(device: self, deviceIndex: slot)
        let routedName = routedTransport.flatMap { transport in
            metadataProvider.readFriendlyName(using: transport) ?? metadataProvider.readName(using: transport)
        }
        let batteryLevel = routedTransport.flatMap {
            metadataProvider.readReceiverBatteryLevel(using: $0)
        }
        let name = nameResponse.flatMap(Self.parseReceiverName) ?? routedName
        let productID = pairingResponse.flatMap(Self.parseReceiverProductID)
        let serialNumber = extendedPairingResponse.flatMap(Self.parseReceiverSerialNumber)

        return .init(
            slot: slot,
            kind: kind,
            name: name,
            productID: productID,
            serialNumber: serialNumber,
            batteryLevel: batteryLevel,
            hasLiveMetadata: routedName != nil || batteryLevel != nil
        )
    }

    private func discoverConnectionSnapshots()
        -> [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot] {
        guard triggerConnectionNotifications() else {
            return [:]
        }

        var snapshots = [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot]()
        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline {
            guard let report = waitForInputReport(timeout: 0.05, matching: { response in
                LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification(Array(response)) != nil
            }) else {
                continue
            }

            guard let notification = LogitechHIDPPDeviceMetadataProvider
                .parseReceiverConnectionNotification(Array(report)) else {
                continue
            }

            snapshots[notification.slot] = notification.snapshot
        }

        return snapshots
    }

    func discoverMatchCandidates(baseName: String)
        -> (
            [LogitechHIDPPDeviceMetadataProvider.ReceiverSlotMatchCandidate],
            [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot]
        )? {
        enableWirelessNotifications()

        guard let discovery = discoverSlots() else {
            return nil
        }

        let slots = discovery.slots

        let provider = LogitechHIDPPDeviceMetadataProvider()
        let candidates = slots.map { slot in
            LogitechHIDPPDeviceMetadataProvider.ReceiverSlotMatchCandidate(
                slot: slot.slot,
                kind: slot.kind,
                name: slot.name ?? baseName,
                serialNumber: slot.serialNumber,
                productID: slot.productID,
                batteryLevel: slot.batteryLevel ?? LogitechHIDPPTransport(device: self, deviceIndex: slot.slot)
                    .flatMap { provider.readReceiverBatteryLevel(using: $0) },
                hasLiveMetadata: slot.hasLiveMetadata
            )
        }

        guard !candidates.isEmpty else {
            return nil
        }

        return (candidates, discovery.connectionSnapshots)
    }

    func enableWirelessNotifications() {
        let currentFlags = readNotificationFlags() ?? 0
        let desiredFlags = currentFlags | LogitechHIDPPDeviceMetadataProvider.Constants.receiverWirelessNotifications
            | LogitechHIDPPDeviceMetadataProvider.Constants.receiverSoftwarePresentNotifications
        if desiredFlags != currentFlags {
            _ = writeNotificationFlags(desiredFlags)
        }
    }

    func discoverPointingDeviceDiscovery(baseName: String) -> LogitechHIDPPDeviceMetadataProvider
        .ReceiverPointingDeviceDiscovery {
        guard let locationID,
              let discovery = discoverMatchCandidates(baseName: baseName)
        else {
            return .init(identities: [], connectionSnapshots: [:], liveReachableSlots: [])
        }

        let (slots, connectionSnapshots) = discovery
        let liveReachableSlots = Set(slots.compactMap { slot in
            slot.hasLiveMetadata ? slot.slot : nil
        })

        let identities = slots.compactMap { slot -> ReceiverLogicalDeviceIdentity? in
            guard let kind = ReceiverLogicalDeviceKind(rawValue: slot.kind), kind.isPointingDevice else {
                return nil
            }

            return ReceiverLogicalDeviceIdentity(
                receiverLocationID: locationID,
                slot: slot.slot,
                kind: kind,
                name: slot.name ?? baseName,
                serialNumber: slot.serialNumber,
                productID: slot.productID,
                batteryLevel: slot.batteryLevel
            )
        }

        return .init(
            identities: identities,
            connectionSnapshots: connectionSnapshots,
            liveReachableSlots: liveReachableSlots
        )
    }

    func waitForConnectionSnapshots(
        timeout: TimeInterval,
        until shouldContinue: (() -> Bool)? = nil
    ) -> [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot] {
        guard let report = waitForInputReport(
            timeout: timeout,
            matching: { response in
                LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification(Array(response)) != nil
            },
            until: shouldContinue
        ),
            let initialNotification = LogitechHIDPPDeviceMetadataProvider
            .parseReceiverConnectionNotification(Array(report))
        else {
            return [:]
        }

        var snapshots = [initialNotification.slot: initialNotification.snapshot]
        let deadline = Date().addingTimeInterval(0.1)
        while Date() < deadline {
            guard let followup = waitForInputReport(
                timeout: 0.02,
                matching: { response in
                    LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification(Array(response)) != nil
                },
                until: shouldContinue
            ),
                let notification = LogitechHIDPPDeviceMetadataProvider
                .parseReceiverConnectionNotification(Array(followup))
            else {
                continue
            }

            snapshots[notification.slot] = notification.snapshot
        }

        return snapshots
    }

    func waitForHIDPPNotification(
        timeout: TimeInterval,
        matching: @escaping ([UInt8]) -> Bool,
        until shouldContinue: (() -> Bool)? = nil
    ) -> [UInt8]? {
        waitForInputReport(
            timeout: timeout,
            matching: { matching(Array($0)) },
            until: shouldContinue
        )
        .map(Array.init)
    }

    func readNotificationFlags() -> UInt32? {
        guard let response = hidpp10ShortRequest(
            subID: 0x81,
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverNotificationFlagsRegister,
            parameters: [0, 0, 0]
        ) else {
            return nil
        }

        return UInt32(response[4]) << 16 | UInt32(response[5]) << 8 | UInt32(response[6])
    }

    func writeNotificationFlags(_ value: UInt32) -> Bool {
        hidpp10ShortRequest(
            subID: 0x80,
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverNotificationFlagsRegister,
            parameters: [UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        ) != nil
    }

    func performSynchronousOutputReportRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool
    ) -> Data? {
        if let strategy = currentRequestStrategy(),
           let response = performRequest(report, timeout: timeout, matching: matching, strategy: strategy) {
            return response
        }

        for strategy in RequestStrategy.allCases {
            guard let response = performRequest(report, timeout: timeout, matching: matching, strategy: strategy) else {
                continue
            }

            setCurrentRequestStrategy(strategy)
            return response
        }

        clearCurrentRequestStrategy()
        return nil
    }

    private func performRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        strategy: RequestStrategy
    ) -> Data? {
        guard !report.isEmpty else {
            return nil
        }

        if let responseType = strategy.responseType {
            return performGetReportRequest(
                report,
                timeout: timeout,
                matching: matching,
                requestType: strategy.requestType,
                responseType: responseType
            )
        }

        return performCallbackRequest(report, timeout: timeout, matching: matching, reportType: strategy.requestType)
    }

    private func performCallbackRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        reportType: IOHIDReportType
    ) -> Data? {
        requestLock.lock()
        defer { requestLock.unlock() }

        let semaphore = DispatchSemaphore(value: 0)
        pendingLock.lock()
        pendingMatcher = matching
        pendingResponse = nil
        pendingSemaphore = semaphore
        pendingLock.unlock()

        let status = sendReport(report, type: reportType)
        guard status == kIOReturnSuccess else {
            clearPendingRequest()
            return nil
        }

        return waitForPendingResponse(timeout: timeout)
    }

    private func performGetReportRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        requestType: IOHIDReportType,
        responseType: IOHIDReportType
    ) -> Data? {
        requestLock.lock()
        defer { requestLock.unlock() }

        clearPendingRequest()
        guard sendReport(report, type: requestType) == kIOReturnSuccess else {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let response = getMatchingReport(type: responseType, matching: matching) {
                return response
            }

            CFRunLoopRunInMode(.defaultMode, 0.01, true)
        }

        return nil
    }

    private func sendReport(_ report: Data, type: IOHIDReportType) -> IOReturn {
        report.withUnsafeBytes { rawBuffer -> IOReturn in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return kIOReturnBadArgument
            }

            return IOHIDDeviceSetReport(device, type, CFIndex(report[0]), baseAddress, report.count)
        }
    }

    private func getMatchingReport(type: IOHIDReportType, matching: @escaping (Data) -> Bool) -> Data? {
        for candidate in candidateReportDescriptors() {
            guard let response = getReport(type: type, reportID: candidate.reportID, length: candidate.length),
                  matching(response) else {
                continue
            }

            return response
        }

        return nil
    }

    private func getReport(type: IOHIDReportType, reportID: UInt8, length: Int) -> Data? {
        guard length >= LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: length)
        buffer[0] = reportID
        var reportLength = CFIndex(length)

        let status = buffer.withUnsafeMutableBytes { rawBuffer -> IOReturn in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return kIOReturnBadArgument
            }

            return IOHIDDeviceGetReport(device, type, CFIndex(reportID), baseAddress, &reportLength)
        }

        guard status == kIOReturnSuccess,
              reportLength >= LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength else {
            return nil
        }

        return Data(buffer.prefix(reportLength))
    }

    private func candidateReportDescriptors() -> [(reportID: UInt8, length: Int)] {
        var descriptors = [(UInt8, Int)]()

        let shortLength = max(
            LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength,
            max(maxInputReportSize ?? 0, maxFeatureReportSize ?? 0)
        )
        descriptors.append((LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID, shortLength))

        let longLength = max(
            LogitechHIDPPDeviceMetadataProvider.Constants.longReportLength,
            max(maxInputReportSize ?? 0, maxFeatureReportSize ?? 0)
        )
        descriptors.append((LogitechHIDPPDeviceMetadataProvider.Constants.longReportID, longLength))

        return descriptors
    }

    private func currentRequestStrategy() -> RequestStrategy? {
        strategyLock.lock()
        defer { strategyLock.unlock() }
        return requestStrategy
    }

    private func setCurrentRequestStrategy(_ strategy: RequestStrategy) {
        strategyLock.lock()
        requestStrategy = strategy
        strategyLock.unlock()
    }

    private func clearCurrentRequestStrategy() {
        strategyLock.lock()
        requestStrategy = nil
        strategyLock.unlock()
    }

    private func waitForInputReport(
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        until shouldContinue: (() -> Bool)? = nil
    ) -> Data? {
        requestLock.lock()
        defer { requestLock.unlock() }

        let semaphore = DispatchSemaphore(value: 0)
        pendingLock.lock()
        pendingMatcher = matching
        pendingResponse = nil
        pendingSemaphore = semaphore
        pendingLock.unlock()

        return waitForPendingResponse(timeout: timeout, until: shouldContinue)
    }

    private func waitForPendingResponse(timeout: TimeInterval, until shouldContinue: (() -> Bool)? = nil) -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let shouldContinue, !shouldContinue() {
                clearPendingRequest()
                return nil
            }

            pendingLock.lock()
            let response = pendingResponse
            pendingLock.unlock()

            if let response {
                clearPendingRequest()
                return response
            }

            CFRunLoopRunInMode(.defaultMode, 0.01, true)
        }

        clearPendingRequest()
        return nil
    }

    private func handleInputReport(_ report: Data) {
        pendingLock.lock()
        defer { pendingLock.unlock() }

        guard let reportMatcher = pendingMatcher, reportMatcher(report) else {
            return
        }

        pendingResponse = report
        pendingMatcher = nil
        pendingSemaphore?.signal()
    }

    private func clearPendingRequest() {
        pendingLock.lock()
        pendingMatcher = nil
        pendingResponse = nil
        pendingSemaphore = nil
        pendingLock.unlock()
    }

    private func readConnectionState() -> [UInt8]? {
        hidpp10ShortRequest(
            subID: 0x81,
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverConnectionStateRegister,
            parameters: [0, 0, 0]
        )
    }

    private func triggerConnectionNotifications() -> Bool {
        hidpp10ShortRequest(
            subID: 0x80,
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverConnectionStateRegister,
            parameters: [0x02, 0x00, 0x00]
        ) != nil
    }

    private func hidpp10ShortRequest(subID: UInt8, register: UInt8, parameters: [UInt8]) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength)
        bytes[0] = LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID
        bytes[1] = LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex
        bytes[2] = subID
        bytes[3] = register
        for (index, parameter) in parameters.prefix(3).enumerated() {
            bytes[4 + index] = parameter
        }

        let response = performSynchronousOutputReportRequest(
            Data(bytes),
            timeout: LogitechHIDPPDeviceMetadataProvider.Constants.timeout
        ) { report in
            let reply = [UInt8](report)
            guard reply.count >= LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength else {
                return false
            }

            guard [
                LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID,
                LogitechHIDPPDeviceMetadataProvider.Constants.longReportID
            ].contains(reply[0]), reply[1] == LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex else {
                return false
            }

            if reply[2] == 0x8F {
                return reply[3] == subID && reply[4] == register
            }

            return reply[2] == subID
                && reply[3] == register
        }

        guard let response else {
            return nil
        }

        let responseBytes = Array(response)
        return responseBytes[2] == 0x8F ? nil : responseBytes
    }

    private func hidpp10LongRequest(register: UInt8, subregister: UInt8) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength)
        bytes[0] = LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID
        bytes[1] = LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex
        bytes[2] = 0x83
        bytes[3] = register
        bytes[4] = subregister

        let request = Data(bytes)

        let response = performSynchronousOutputReportRequest(
            request,
            timeout: LogitechHIDPPDeviceMetadataProvider.Constants.timeout
        ) { report in
            let reply = [UInt8](report)
            guard reply.count >= 5 else {
                return false
            }

            guard [
                LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID,
                LogitechHIDPPDeviceMetadataProvider.Constants.longReportID
            ].contains(reply[0]), reply[1] == LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex else {
                return false
            }

            if reply[2] == 0x8F {
                return reply[3] == 0x83 && reply[4] == register
            }

            return reply[2] == 0x83
                && reply[3] == register
                && reply[4] == subregister
        }

        guard let response else {
            return nil
        }

        let responseBytes = Array(response)
        return responseBytes[2] == 0x8F ? nil : responseBytes
    }

    private static func parseReceiverName(_ response: [UInt8]) -> String? {
        guard response.count >= 6 else {
            return nil
        }

        let length = Int(response[5])
        let bytes = Array(response.dropFirst(6).prefix(length))
        return String(bytes: bytes, encoding: .utf8)
    }

    private static func parseReceiverKind(_ response: [UInt8]) -> UInt8? {
        guard response.count >= 13 else {
            return nil
        }

        let candidateIndices = [11, 12]
        for index in candidateIndices where index < response.count {
            let kind = response[index] & 0x0F
            if kind != 0 {
                return kind
            }
        }

        return nil
    }

    private static func parseReceiverProductID(_ response: [UInt8]) -> Int? {
        guard response.count >= 9 else {
            return nil
        }

        return Int(response[7]) << 8 | Int(response[8])
    }

    private static func parseReceiverSerialNumber(_ response: [UInt8]) -> String? {
        guard response.count >= 10 else {
            return nil
        }

        return response[6 ... 9].map { String(format: "%02X", $0) }.joined()
    }

    private static func getProperty<T>(_ key: String, from device: IOHIDDevice) -> T? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else {
            return nil
        }

        return value as? T
    }
}

private extension LogitechHIDPPDeviceMetadataProvider.FeatureID {
    var bytes: [UInt8] {
        [UInt8(rawValue >> 8), UInt8(rawValue & 0xFF)]
    }
}

final class LogitechReprogrammableControlsMonitor {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "LogitechReprogrammableControls")

    private enum Constants {
        static let notificationTimeout: TimeInterval = 0.25
        static let stopTimeout: TimeInterval = 3
    }

    private struct ControlInfo {
        let controlID: UInt16
        let taskID: UInt16
        let position: UInt8
        let group: UInt8
        let groupMask: UInt8
        let flags: LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.ControlFlags
    }

    private struct ReportingInfo {
        let flags: LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.ReportingFlags
        let mappedControlID: UInt16
    }

    struct TargetDevice {
        let slot: UInt8
        let identity: ReceiverLogicalDeviceIdentity?
    }

    private struct MonitorTarget {
        let slot: UInt8
        let identity: ReceiverLogicalDeviceIdentity?
        let transport: LogitechHIDPPTransport
        let featureIndex: UInt8
        let controls: [ControlInfo]
        let notificationEndpoint: HIDPPNotificationHandling
    }

    private let device: Device
    private let provider = LogitechHIDPPDeviceMetadataProvider()
    private let stateLock = NSLock()
    private var subscriptions = Set<AnyCancellable>()
    private var directDeviceReportObservationToken: ObservationToken?

    private var workerThread: Thread?
    private var running = false
    private var pressedButtons = Set<Int>()
    private var needsReconfiguration = false

    init(device: Device) {
        self.device = device
    }

    static func supports(device: Device) -> Bool {
        guard let vendorID = device.vendorID,
              vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID,
              [PointerDeviceTransportName.usb, PointerDeviceTransportName.bluetoothLowEnergy]
              .contains(device.pointerDevice.transport)
        else {
            return false
        }

        return true
    }

    func start() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !running else {
            return
        }

        running = true
        let thread = Thread { [weak self] in
            self?.workerMain()
        }
        thread.name = "linearmouse.logitech-controls.\(device.id)"
        workerThread = thread
        thread.start()

        observeConfigurationChangesIfNeeded()
    }

    func stop() {
        stateLock.lock()
        running = false
        let thread = workerThread
        workerThread = nil
        stateLock.unlock()

        thread?.cancel()
        subscriptions.removeAll()
        directDeviceReportObservationToken = nil
    }

    private func workerMain() {
        defer {
            releaseButtonIfNeeded()
        }

        guard let monitorTarget = resolveMonitorTarget() else {
            finishVirtualButtonRecordingPreparationIfNeeded(sessionID: SettingsState.shared
                .virtualButtonRecordingSessionID)
            os_log(
                "Skip Logitech controls monitor because initialization failed: device=%{public}@",
                log: Self.log,
                type: .info,
                String(describing: device)
            )
            return
        }

        let locationID = device.pointerDevice.locationID ?? 0
        let slot = monitorTarget.slot
        let transport = monitorTarget.transport
        let featureIndex = monitorTarget.featureIndex
        let allControls = monitorTarget.controls
        let targetIdentity = monitorTarget.identity
        let targetName = targetIdentity?.name ?? device.productName ?? device.name
        var pendingReportingRestoreByControlID = [UInt16: ReportingInfo]()

        monitorTarget.notificationEndpoint.enableNotifications()
        logAvailableControls(transport: transport, featureIndex: featureIndex, slot: slot, locationID: locationID)

        while shouldContinueRunning() {
            if !pendingReportingRestoreByControlID.isEmpty {
                pendingReportingRestoreByControlID = restoreReportingState(
                    pendingReportingRestoreByControlID,
                    using: transport,
                    featureIndex: featureIndex,
                    locationID: locationID,
                    slot: slot,
                    reason: "retry pending restore"
                )
            }

            let desiredControlIDs = desiredDivertedControlIDs(availableControls: allControls, identity: targetIdentity)
            let isRecording = SettingsState.shared.recording
            let recordingSessionID = isRecording ? SettingsState.shared.virtualButtonRecordingSessionID : nil
            let monitoredControls = isRecording
                ? allControls
                : allControls.filter { desiredControlIDs.contains($0.controlID) }
            let monitoredControlIDs = Set(monitoredControls.map(\.controlID))
            let reservedVirtualButtonNumber =
                LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.reservedVirtualButtonNumber

            if !isRecording {
                let controlsToRestore = pendingReportingRestoreByControlID
                    .filter { !desiredControlIDs.contains($0.key) }
                if !controlsToRestore.isEmpty {
                    let failedRestoreByControlID = restoreReportingState(
                        controlsToRestore,
                        using: transport,
                        featureIndex: featureIndex,
                        locationID: locationID,
                        slot: slot,
                        reason: "apply native reporting to unmonitored controls"
                    )

                    for controlID in Set(controlsToRestore.keys).subtracting(failedRestoreByControlID.keys) {
                        pendingReportingRestoreByControlID.removeValue(forKey: controlID)
                    }

                    pendingReportingRestoreByControlID.merge(failedRestoreByControlID) { _, new in new }
                }
            }

            if monitoredControls.isEmpty {
                finishVirtualButtonRecordingPreparationIfNeeded(sessionID: recordingSessionID)
                os_log(
                    "Pause Logitech control diversion until configuration changes: locationID=%{public}d slot=%{public}u device=%{public}@ recording=%{public}@",
                    log: Self.log,
                    type: .info,
                    locationID,
                    slot,
                    targetName,
                    isRecording ? "true" : "false"
                )

                guard waitForReconfigurationOrStop() else {
                    return
                }

                continue
            }

            let originalReportingByControlID = monitoredControls
                .reduce(into: [UInt16: ReportingInfo]()) { result, control in
                    guard let reportingInfo = readReportingInfo(
                        for: control.controlID,
                        using: transport,
                        featureIndex: featureIndex
                    ) else {
                        return
                    }

                    result[control.controlID] = reportingInfo
                }
            let activeControlIDs = monitoredControls.compactMap { control -> UInt16? in
                guard setDiverted(true, for: control.controlID, using: transport, featureIndex: featureIndex) else {
                    os_log(
                        "Failed to enable Logitech control diversion: locationID=%{public}d slot=%{public}u cid=0x%{public}04X",
                        log: Self.log,
                        type: .error,
                        locationID,
                        slot,
                        control.controlID
                    )
                    return nil
                }

                return control.controlID
            }

            guard !activeControlIDs.isEmpty else {
                finishVirtualButtonRecordingPreparationIfNeeded(sessionID: recordingSessionID)
                os_log(
                    "Failed to enable any Logitech control diversion: locationID=%{public}d slot=%{public}u device=%{public}@",
                    log: Self.log,
                    type: .error,
                    locationID,
                    slot,
                    targetName
                )

                guard waitForReconfigurationOrStop() else {
                    return
                }

                continue
            }

            let activeReportingByControlID = activeControlIDs
                .reduce(into: [UInt16: ReportingInfo]()) { result, controlID in
                    guard let reportingInfo = readReportingInfo(
                        for: controlID,
                        using: transport,
                        featureIndex: featureIndex
                    ) else {
                        return
                    }

                    result[controlID] = reportingInfo
                }

            let controlSummary = monitoredControls.map { control in
                let originalReporting = originalReportingByControlID[control.controlID]
                let activeReporting = activeReportingByControlID[control.controlID]
                return String(
                    format: "cid=0x%04X button=%d tid=0x%04X flags=%@ reporting=%@ mapped=0x%04X",
                    control.controlID,
                    reservedVirtualButtonNumber,
                    control.taskID,
                    describeControlFlags(control.flags),
                    describeReportingFlags(activeReporting?.flags ?? originalReporting?.flags ?? []),
                    activeReporting?.mappedControlID ?? originalReporting?.mappedControlID ?? control.controlID
                )
            }
            .joined(separator: " | ")

            os_log(
                "Logitech controls monitor enabled: locationID=%{public}d slot=%{public}u device=%{public}@ controls=%{public}@",
                log: Self.log,
                type: .info,
                locationID,
                slot,
                targetName,
                controlSummary
            )

            finishVirtualButtonRecordingPreparationIfNeeded(sessionID: recordingSessionID)

            var pressedControls = Set<UInt16>()
            defer {
                releaseButtonIfNeeded()

                let failedRestoreByControlID = restoreReportingState(
                    originalReportingByControlID,
                    using: transport,
                    featureIndex: featureIndex,
                    locationID: locationID,
                    slot: slot,
                    reason: "restore original reporting"
                )

                pendingReportingRestoreByControlID.merge(failedRestoreByControlID) { _, new in new }
                for controlID in Set(originalReportingByControlID.keys).subtracting(failedRestoreByControlID.keys) {
                    pendingReportingRestoreByControlID.removeValue(forKey: controlID)
                }
            }

            while shouldContinueRunning() {
                if consumeReconfigurationRequest() {
                    os_log(
                        "Restart Logitech control monitor to refresh diverted controls: locationID=%{public}d slot=%{public}u device=%{public}@",
                        log: Self.log,
                        type: .info,
                        locationID,
                        slot,
                        targetName
                    )
                    break
                }

                guard let report = monitorTarget.notificationEndpoint.waitForHIDPPNotification(
                    timeout: Constants.notificationTimeout,
                    matching: { response in
                        Self.isDivertedButtonsNotification(response, featureIndex: featureIndex, slot: slot)
                    },
                    until: { [weak self] in self?.shouldContinueRunning() == true }
                ) else {
                    continue
                }

                let activeControls = Self.parseDivertedButtonsNotification(report).intersection(monitoredControlIDs)
                let changedControls = activeControls.symmetricDifference(pressedControls).sorted()
                pressedControls = activeControls

                for controlID in changedControls {
                    let isPressed = activeControls.contains(controlID)
                    os_log(
                        "Logitech reprogrammable control event: locationID=%{public}d slot=%{public}u device=%{public}@ cid=0x%{public}04X button=%{public}d state=%{public}@ active=%{public}@",
                        log: Self.log,
                        type: .info,
                        locationID,
                        slot,
                        targetName,
                        controlID,
                        reservedVirtualButtonNumber,
                        isPressed ? "down" : "up",
                        activeControls.map { String(format: "0x%04X", $0) }.sorted().joined(separator: ",")
                    )

                    device.markActive(reason: "Received Logitech reprogrammable control event")

                    let modifierFlags = ModifierState.shared.currentFlags
                    let controlIdentity = LogitechControlIdentity(
                        controlID: Int(controlID),
                        productID: targetIdentity?.productID,
                        serialNumber: targetIdentity?.serialNumber
                    )

                    if isRecording {
                        if isPressed {
                            DispatchQueue.main.async {
                                SettingsState.shared.recordedVirtualButtonEvent = .init(
                                    button: .logitechControl(controlIdentity),
                                    modifierFlags: modifierFlags
                                )
                            }
                        }
                        continue
                    }

                    let mouseLocation = NSEvent.mouseLocation
                    let mouseLocationWindowID = CGWindowID(NSWindow.windowNumber(
                        at: mouseLocation,
                        belowWindowWithWindowNumber: 0
                    ))
                    let mouseLocationPid = mouseLocationWindowID.ownerPid
                        ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
                    let display = ScreenManager.shared.currentScreenName
                    let transformer = EventTransformerManager.shared.get(
                        withDevice: device,
                        withPid: mouseLocationPid,
                        withDisplay: display
                    )

                    let logitechContext = ButtonActionsTransformer.LogitechEventContext(
                        device: device,
                        pid: mouseLocationPid,
                        display: display,
                        controlIdentity: controlIdentity,
                        isPressed: isPressed,
                        modifierFlags: modifierFlags
                    )

                    let handledInternally = (transformer as? [EventTransformer])?.contains { transformer in
                        if let transformer = transformer as? ButtonActionsTransformer {
                            return transformer.handleLogitechControlEvent(logitechContext)
                        }

                        if let transformer = transformer as? AutoScrollTransformer {
                            return transformer.handleLogitechControlEvent(logitechContext)
                        }

                        if let transformer = transformer as? GestureButtonTransformer {
                            return transformer.handleLogitechControlEvent(logitechContext)
                        }

                        return false
                    } == true

                    guard !handledInternally else {
                        continue
                    }

                    postSyntheticButton(
                        button: reservedVirtualButtonNumber,
                        down: isPressed
                    )
                }
            }
        }
    }

    private func waitForReconfigurationOrStop() -> Bool {
        while shouldContinueRunning() {
            if consumeReconfigurationRequest() {
                return true
            }

            Thread.sleep(forTimeInterval: Constants.notificationTimeout)
        }

        return false
    }

    private func finishVirtualButtonRecordingPreparationIfNeeded(sessionID: UUID?) {
        guard let sessionID else {
            return
        }

        DispatchQueue.main.async {
            SettingsState.shared.finishVirtualButtonRecordingPreparation(
                for: self.device.id,
                sessionID: sessionID
            )
        }
    }

    private func findMonitoredControls(using transport: LogitechHIDPPTransport, featureIndex: UInt8) -> [ControlInfo] {
        let controls = fetchControls(using: transport, featureIndex: featureIndex)
        return controls
            .filter(Self.shouldMonitor)
            .sorted { lhs, rhs in
                if lhs.controlID != rhs.controlID {
                    return lhs.controlID < rhs.controlID
                }

                return lhs.taskID < rhs.taskID
            }
    }

    private func resolveMonitorTarget() -> MonitorTarget? {
        if device.pointerDevice.transport == PointerDeviceTransportName.bluetoothLowEnergy {
            return buildDirectMonitorTarget()
        }

        guard let receiverChannel = provider.openReceiverChannel(for: device.pointerDevice) else {
            return nil
        }

        return resolveMonitorTarget(using: receiverChannel)
    }

    private func buildDirectMonitorTarget() -> MonitorTarget? {
        guard let transport = LogitechHIDPPTransport(device: device.pointerDevice, deviceIndex: nil),
              let featureIndex = transport.featureIndex(for: .reprogControlsV4) else {
            return nil
        }

        let controls = findMonitoredControls(using: transport, featureIndex: featureIndex)
        guard !controls.isEmpty else {
            return nil
        }

        let identity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: device.pointerDevice.locationID ?? 0,
            slot: 0,
            kind: .mouse,
            name: device.productName ?? device.name,
            serialNumber: device.serialNumber,
            productID: device.productID,
            batteryLevel: device.batteryLevel
        )

        return MonitorTarget(
            slot: LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex,
            identity: identity,
            transport: transport,
            featureIndex: featureIndex,
            controls: controls,
            notificationEndpoint: directNotificationEndpoint()
        )
    }

    private func directNotificationEndpoint() -> HIDPPNotificationEndpoint {
        directDeviceReportObservationToken = nil
        let endpoint = HIDPPNotificationEndpoint()
        directDeviceReportObservationToken = device.pointerDevice.observeReport { _, report in
            endpoint.handleInputReport(report)
        }
        return endpoint
    }

    private func resolveTargetDevice(using receiverChannel: LogitechReceiverChannel) -> TargetDevice? {
        if let slot = provider.receiverSlot(for: device.pointerDevice, using: receiverChannel) {
            let discovery = provider.receiverPointingDeviceDiscovery(for: device.pointerDevice, using: receiverChannel)
            let identity = discovery.identities.first { $0.slot == slot }
            return TargetDevice(slot: slot, identity: identity)
        }

        return nil
    }

    private func resolveMonitorTarget(using receiverChannel: LogitechReceiverChannel) -> MonitorTarget? {
        let discovery = provider.receiverPointingDeviceDiscovery(for: device.pointerDevice, using: receiverChannel)

        if let targetDevice = resolveTargetDevice(using: receiverChannel),
           let target = buildMonitorTarget(
               slot: targetDevice.slot,
               identity: targetDevice.identity,
               using: receiverChannel
           ) {
            return target
        }

        let scannedTargets = (UInt8(1) ... UInt8(6)).compactMap { slot in
            buildMonitorTarget(
                slot: slot,
                identity: discovery.identities.first { $0.slot == slot },
                using: receiverChannel
            )
        }

        if scannedTargets.count == 1 {
            let target = scannedTargets[0]
            os_log(
                "Resolved Logitech monitor target by slot scan: receiver=%{public}@ slot=%{public}u name=%{public}@",
                log: Self.log,
                type: .info,
                device.productName ?? device.name,
                target.slot,
                target.identity?.name ?? "(nil)"
            )
            return target
        }

        let candidatesDescription = scannedTargets.map { target in
            let name = target.identity?.name ?? "(nil)"
            let firstControl = target.controls.first
            return String(
                format: "slot=%u name=%@ firstCID=0x%04X count=%u",
                target.slot,
                name,
                firstControl?.controlID ?? 0,
                target.controls.count
            )
        }
        .joined(separator: ", ")

        os_log(
            "Failed to resolve Logitech monitor target: receiver=%{public}@ discoveryCount=%{public}u candidates=%{public}@",
            log: Self.log,
            type: .info,
            device.productName ?? device.name,
            UInt32(discovery.identities.count),
            candidatesDescription
        )
        return nil
    }

    private func buildMonitorTarget(
        slot: UInt8,
        identity: ReceiverLogicalDeviceIdentity?,
        using receiverChannel: LogitechReceiverChannel
    ) -> MonitorTarget? {
        guard let transport = LogitechHIDPPTransport(device: receiverChannel, deviceIndex: slot),
              let featureIndex = transport.featureIndex(for: .reprogControlsV4)
        else {
            return nil
        }

        let controls = findMonitoredControls(using: transport, featureIndex: featureIndex)
        guard !controls.isEmpty else {
            return nil
        }

        return MonitorTarget(
            slot: slot,
            identity: identity,
            transport: transport,
            featureIndex: featureIndex,
            controls: controls,
            notificationEndpoint: receiverChannel
        )
    }

    private static func shouldMonitor(_ control: ControlInfo) -> Bool {
        guard control.flags.contains(.mouseButton), !control.flags.contains(.virtual) else {
            return false
        }

        let isDivertable = control.flags.contains(.divertable) || control.flags.contains(.persistentlyDivertable)
        guard isDivertable else {
            return false
        }

        guard !LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.nativeControlIDs
            .contains(control.controlID) else {
            return false
        }

        if LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.gestureButtonControlIDs.contains(control.controlID)
            || LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.gestureButtonTaskIDs.contains(control.taskID) {
            return true
        }

        if control.flags.contains(.rawXY) {
            return true
        }

        return control.controlID >= 0x00C0 || control.taskID >= 0x0090
    }

    private func observeConfigurationChangesIfNeeded() {
        guard subscriptions.isEmpty else {
            return
        }

        ConfigurationState.shared
            .$configuration
            .dropFirst()
            .sink { [weak self] _ in
                self?.requestReconfiguration()
            }
            .store(in: &subscriptions)

        SettingsState.shared
            .$recording
            .dropFirst()
            .sink { [weak self] _ in
                self?.requestReconfiguration()
            }
            .store(in: &subscriptions)

        ScreenManager.shared
            .$currentScreenName
            .dropFirst()
            .sink { [weak self] _ in
                self?.requestReconfiguration()
            }
            .store(in: &subscriptions)

        NSWorkspace.shared
            .notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in
                self?.requestReconfiguration()
            }
            .store(in: &subscriptions)
    }

    private func requestReconfiguration() {
        stateLock.lock()
        needsReconfiguration = true
        stateLock.unlock()
    }

    private func consumeReconfigurationRequest() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard needsReconfiguration else {
            return false
        }

        needsReconfiguration = false
        return true
    }

    private func desiredDivertedControlIDs(
        availableControls: [ControlInfo],
        identity: ReceiverLogicalDeviceIdentity?
    ) -> Set<UInt16> {
        if SettingsState.shared.recording {
            return Set(availableControls.map(\.controlID))
        }

        let scheme = ConfigurationState.shared.configuration.matchScheme(
            withDevice: device,
            withPid: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            withDisplay: ScreenManager.shared.currentScreenName
        )

        let directMappings: [UInt16] = (scheme.buttons.mappings ?? [])
            .compactMap { (mapping: Scheme.Buttons.Mapping) -> UInt16? in
                guard let logiButton = mapping.button?.logitechControl else {
                    return nil
                }

                guard matches(logiButton: logiButton, identity: identity) else {
                    return nil
                }

                return logiButton.controlIDValue
            }

        let autoScrollControlID: UInt16? = {
            guard scheme.buttons.autoScroll.enabled ?? true,
                  let logiButton = scheme.buttons.autoScroll.trigger?.button?.logitechControl,
                  matches(logiButton: logiButton, identity: identity) else {
                return nil
            }
            return logiButton.controlIDValue
        }()

        let gestureControlID: UInt16? = {
            guard scheme.buttons.gesture.enabled ?? true,
                  let logiButton = scheme.buttons.gesture.trigger?.button?.logitechControl,
                  matches(logiButton: logiButton, identity: identity) else {
                return nil
            }
            return logiButton.controlIDValue
        }()

        return Set(directMappings + [autoScrollControlID, gestureControlID].compactMap(\.self))
            .intersection(availableControls.map(\.controlID))
    }

    private func matches(logiButton: LogitechControlIdentity, identity: ReceiverLogicalDeviceIdentity?) -> Bool {
        if let configuredSerialNumber = logiButton.serialNumber {
            guard let serialNumber = identity?.serialNumber else {
                return false
            }
            return configuredSerialNumber.caseInsensitiveCompare(serialNumber) == .orderedSame
        }

        if let configuredProductID = logiButton.productID {
            guard let productID = identity?.productID else {
                return false
            }
            return configuredProductID == productID
        }

        return logiButton.serialNumber == nil && logiButton.productID == nil
    }

    private func fetchControls(using transport: LogitechHIDPPTransport, featureIndex: UInt8) -> [ControlInfo] {
        guard let countResponse = transport.request(
            featureIndex: featureIndex,
            function: LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.getControlCountFunction,
            parameters: []
        ), let count = countResponse.payload.first else {
            return []
        }

        return (0 ..< count).compactMap { readControlInfo(index: $0, using: transport, featureIndex: featureIndex) }
    }

    private func readControlInfo(
        index: UInt8,
        using transport: LogitechHIDPPTransport,
        featureIndex: UInt8
    ) -> ControlInfo? {
        guard let response = transport.request(
            featureIndex: featureIndex,
            function: LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.getControlInfoFunction,
            parameters: [index]
        ) else {
            return nil
        }

        let payload = response.payload
        guard payload.count >= 9 else {
            return nil
        }

        let controlID = UInt16(payload[0]) << 8 | UInt16(payload[1])
        let taskID = UInt16(payload[2]) << 8 | UInt16(payload[3])
        let flagsRaw = UInt16(payload[4]) | (UInt16(payload[8]) << 8)

        return ControlInfo(
            controlID: controlID,
            taskID: taskID,
            position: payload[5],
            group: payload[6],
            groupMask: payload[7],
            flags: .init(rawValue: flagsRaw)
        )
    }

    private func readReportingInfo(
        for controlID: UInt16,
        using transport: LogitechHIDPPTransport,
        featureIndex: UInt8
    ) -> ReportingInfo? {
        guard let response = transport.request(
            featureIndex: featureIndex,
            function: LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.getControlReportingFunction,
            parameters: controlID.bytes
        ), response.payload.count >= 3 else {
            return nil
        }

        let mappedControlID: UInt16
        if response.payload.count >= 5 {
            let mapped = UInt16(response.payload[3]) << 8 | UInt16(response.payload[4])
            mappedControlID = mapped == 0 ? controlID : mapped
        } else {
            mappedControlID = controlID
        }

        let flagsRaw = UInt16(response.payload[2]) |
            (response.payload.count >= 6 ? UInt16(response.payload[5]) << 8 : 0)
        return ReportingInfo(
            flags: .init(rawValue: flagsRaw),
            mappedControlID: mappedControlID
        )
    }

    private func setDiverted(
        _ enabled: Bool,
        for controlID: UInt16,
        using transport: LogitechHIDPPTransport,
        featureIndex: UInt8
    ) -> Bool {
        let flags = enabled
            ? UInt8(LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.ReportingFlags.diverted.rawValue)
            : 0
        let changeBits: UInt8 = enabled ? 0x03 : 0x02

        guard let response = transport.request(
            featureIndex: featureIndex,
            function: LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.setControlReportingFunction,
            parameters: controlID.bytes + [UInt8(changeBits | flags), 0x00, 0x00]
        ), response.payload.count >= 2 else {
            return false
        }

        let didEchoControlID = response.payload[0] == UInt8(controlID >> 8)
            && response.payload[1] == UInt8(controlID & 0xFF)
        if !didEchoControlID {
            os_log(
                "Logitech setCidReporting did not echo control ID: cid=0x%{public}04X payload=%{public}@",
                log: Self.log,
                type: .info,
                controlID,
                response.payload.map { String(format: "%02X", $0) }.joined(separator: " ")
            )
        }

        return true
    }

    private func restoreReportingState(
        _ reportingByControlID: [UInt16: ReportingInfo],
        using transport: LogitechHIDPPTransport,
        featureIndex: UInt8,
        locationID: Int,
        slot: UInt8,
        reason: StaticString
    ) -> [UInt16: ReportingInfo] {
        reportingByControlID.reduce(into: [UInt16: ReportingInfo]()) { result, entry in
            let (controlID, reportingInfo) = entry
            let shouldBeDiverted = reportingInfo.flags.contains(.diverted)

            guard setDiverted(shouldBeDiverted, for: controlID, using: transport, featureIndex: featureIndex) else {
                os_log(
                    "%{public}s failed: locationID=%{public}d slot=%{public}u cid=0x%{public}04X target=%{public}@",
                    log: Self.log,
                    type: .error,
                    String(describing: reason),
                    locationID,
                    slot,
                    controlID,
                    shouldBeDiverted ? "diverted" : "native"
                )
                result[controlID] = reportingInfo
                return
            }

            guard let currentReportingInfo = readReportingInfo(
                for: controlID,
                using: transport,
                featureIndex: featureIndex
            ) else {
                os_log(
                    "%{public}s verification failed: locationID=%{public}d slot=%{public}u cid=0x%{public}04X",
                    log: Self.log,
                    type: .error,
                    String(describing: reason),
                    locationID,
                    slot,
                    controlID
                )
                result[controlID] = reportingInfo
                return
            }

            let isDiverted = currentReportingInfo.flags.contains(.diverted)
            guard isDiverted == shouldBeDiverted else {
                os_log(
                    "%{public}s verification mismatch: locationID=%{public}d slot=%{public}u cid=0x%{public}04X target=%{public}@ actual=%{public}@ reporting=%{public}@",
                    log: Self.log,
                    type: .error,
                    String(describing: reason),
                    locationID,
                    slot,
                    controlID,
                    shouldBeDiverted ? "diverted" : "native",
                    isDiverted ? "diverted" : "native",
                    describeReportingFlags(currentReportingInfo.flags)
                )
                result[controlID] = reportingInfo
                return
            }
        }
    }

    private func shouldContinueRunning() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running && !Thread.current.isCancelled
    }

    private func postSyntheticButton(button: Int, down: Bool) {
        stateLock.lock()
        let shouldPost = down ? pressedButtons.insert(button).inserted : pressedButtons.remove(button) != nil
        stateLock.unlock()

        guard shouldPost else {
            return
        }

        SyntheticMouseButtonEventEmitter.post(button: button, down: down)
    }

    private func releaseButtonIfNeeded() {
        stateLock.lock()
        let buttonsToRelease = pressedButtons
        pressedButtons.removeAll()
        stateLock.unlock()

        for button in buttonsToRelease {
            SyntheticMouseButtonEventEmitter.post(button: button, down: false)
        }
    }

    static func isDivertedButtonsNotification(_ report: [UInt8], featureIndex: UInt8, slot: UInt8) -> Bool {
        guard report.count >= 4,
              [LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID,
               LogitechHIDPPDeviceMetadataProvider.Constants.longReportID].contains(report[0]),
              report[1] == slot,
              report[2] == featureIndex
        else {
            return false
        }

        return (report[3] >> 4) == 0x00
    }

    static func parseDivertedButtonsNotification(_ report: [UInt8]) -> Set<UInt16> {
        let payload = Array(report.dropFirst(4))
        guard payload.count >= 2 else {
            return []
        }

        var controls = Set<UInt16>()
        var index = 0
        while index + 1 < payload.count {
            let controlID = UInt16(payload[index]) << 8 | UInt16(payload[index + 1])
            guard controlID != 0 else {
                break
            }

            controls.insert(controlID)
            index += 2
        }

        return controls
    }

    private func logAvailableControls(
        transport: LogitechHIDPPTransport,
        featureIndex: UInt8,
        slot: UInt8,
        locationID: Int
    ) {
        let controls = fetchControls(using: transport, featureIndex: featureIndex)
        guard !controls.isEmpty else {
            os_log(
                "No Logitech reprogrammable controls discovered: locationID=%{public}d slot=%{public}u",
                log: Self.log,
                type: .info,
                locationID,
                slot
            )
            return
        }

        let summary = controls.map { control -> String in
            let reporting = readReportingInfo(for: control.controlID, using: transport, featureIndex: featureIndex)
            return String(
                format: "cid=0x%04X tid=0x%04X pos=%u group=%u mask=0x%02X flags=%@ reporting=%@ mapped=0x%04X",
                control.controlID,
                control.taskID,
                control.position,
                control.group,
                control.groupMask,
                describeControlFlags(control.flags),
                describeReportingFlags(reporting?.flags ?? []),
                reporting?.mappedControlID ?? control.controlID
            )
        }
        .joined(separator: " | ")

        os_log(
            "Logitech REPROG_CONTROLS_V4 dump: locationID=%{public}d slot=%{public}u controls=%{public}@",
            log: Self.log,
            type: .info,
            locationID,
            slot,
            summary
        )
    }

    private func describeControlFlags(_ flags: LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4
        .ControlFlags) -> String {
        var parts = [String]()
        if flags.contains(.mouseButton) {
            parts.append("mse")
        }
        if flags.contains(.reprogrammable) {
            parts.append("reprogrammable")
        }
        if flags.contains(.divertable) {
            parts.append("divertable")
        }
        if flags.contains(.persistentlyDivertable) {
            parts.append("persistently_divertable")
        }
        if flags.contains(.virtual) {
            parts.append("virtual")
        }
        if flags.contains(.rawXY) {
            parts.append("raw_xy")
        }
        if flags.contains(.forceRawXY) {
            parts.append("force_raw_xy")
        }
        return parts.isEmpty ? "none" : parts.joined(separator: ",")
    }

    private func describeReportingFlags(_ flags: LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4
        .ReportingFlags) -> String {
        var parts = [String]()
        if flags.contains(.diverted) {
            parts.append("diverted")
        }
        if flags.contains(.persistentlyDiverted) {
            parts.append("persistently_diverted")
        }
        if flags.contains(.rawXYDiverted) {
            parts.append("raw_xy_diverted")
        }
        if flags.contains(.forceRawXYDiverted) {
            parts.append("force_raw_xy_diverted")
        }
        return parts.isEmpty ? "default" : parts.joined(separator: ",")
    }
}

private protocol HIDPPNotificationHandling: AnyObject {
    func enableNotifications()
    func waitForHIDPPNotification(
        timeout: TimeInterval,
        matching: @escaping ([UInt8]) -> Bool,
        until shouldContinue: (() -> Bool)?
    ) -> [UInt8]?
}

private final class HIDPPNotificationEndpoint: HIDPPNotificationHandling {
    private static let maxBufferedReports = 64

    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var bufferedReports = [[UInt8]]()

    func enableNotifications() {}

    func handleInputReport(_ report: Data) {
        let bytes = [UInt8](report)
        guard let reportID = bytes.first,
              [LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID,
               LogitechHIDPPDeviceMetadataProvider.Constants.longReportID].contains(reportID) else {
            return
        }

        lock.lock()
        bufferedReports.append(bytes)
        if bufferedReports.count > Self.maxBufferedReports {
            bufferedReports.removeFirst(bufferedReports.count - Self.maxBufferedReports)
        }
        lock.unlock()
        semaphore.signal()
    }

    func waitForHIDPPNotification(
        timeout: TimeInterval,
        matching: @escaping ([UInt8]) -> Bool,
        until shouldContinue: (() -> Bool)? = nil
    ) -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let shouldContinue, !shouldContinue() {
                return nil
            }

            if let report = dequeueFirstMatchingReport(matching: matching) {
                return report
            }

            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                break
            }

            _ = semaphore.wait(timeout: .now() + min(remaining, 0.01))
        }

        return dequeueFirstMatchingReport(matching: matching)
    }

    private func dequeueFirstMatchingReport(matching: ([UInt8]) -> Bool) -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }

        guard let index = bufferedReports.firstIndex(where: matching) else {
            return nil
        }

        return bufferedReports.remove(at: index)
    }
}

extension LogitechReceiverChannel: HIDPPNotificationHandling {
    func enableNotifications() {
        enableWirelessNotifications()
    }
}

private extension UInt16 {
    var bytes: [UInt8] {
        [UInt8(self >> 8), UInt8(self & 0xFF)]
    }
}
