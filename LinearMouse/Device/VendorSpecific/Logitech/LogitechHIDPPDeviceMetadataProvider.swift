// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import IOKit.hid
import os.log

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
        static let djShortReportID: UInt8 = 0x20
        static let djLongReportID: UInt8 = 0x21
        static let shortReportLength = 7
        static let longReportLength = 20
        static let djShortReportLength = 15
        static let djLongReportLength = 32
        static let timeout: TimeInterval = 2.0

        static let receiverIndex: UInt8 = 0xFF
        static let directReplyIndices: Set<UInt8> = [0x00, 0xFF]
        static let receiverNotificationFlagsRegister: UInt8 = 0x00
        static let receiverConnectionStateRegister: UInt8 = 0x02
        static let receiverInfoRegister: UInt8 = 0xB5
        static let receiverWirelessNotifications: UInt32 = 0x000100
        static let receiverSoftwarePresentNotifications: UInt32 = 0x000800
        static let djSwitchCommand: UInt8 = 0x80
        static let djSwitchDeviceBitfield: UInt8 = 0x3F
    }

    enum FeatureID: UInt16 {
        case root = 0x0000
        case deviceName = 0x0005
        case deviceFriendlyName = 0x0007
        case batteryStatus = 0x1000
        case batteryVoltage = 0x1001
        case unifiedBattery = 0x1004
        case adcMeasurement = 0x1F20
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
    }

    struct ReceiverSlotMetadata {
        let slot: UInt8
        let name: String?
        let batteryLevel: Int?
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
        transports: ["Bluetooth Low Energy", "USB"]
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

    func receiverPointingDeviceIdentities(for device: VendorSpecificDeviceContext) -> [ReceiverLogicalDeviceIdentity] {
        guard device.transport == "USB",
              let locationID = device.locationID,
              let receiverChannel = LogitechReceiverChannel.open(locationID: locationID),
              let slots = receiverChannel.discoverSlots()
        else {
            return []
        }

        return slots.compactMap { slot -> ReceiverLogicalDeviceIdentity? in
            guard let kind = ReceiverLogicalDeviceKind(rawValue: slot.kind), kind.isPointingDevice else {
                return nil
            }

            let name = slot.name ?? device.product ?? device.name
            return ReceiverLogicalDeviceIdentity(
                receiverLocationID: locationID,
                slot: slot.slot,
                kind: kind,
                name: name,
                serialNumber: slot.serialNumber,
                productID: slot.productID,
                batteryLevel: slot.batteryLevel
            )
        }
    }

    func receiverActivityChannel(for locationID: Int) -> LogitechReceiverChannel? {
        LogitechReceiverChannel.open(locationID: locationID)
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
        guard device.transport == "Bluetooth Low Energy" else {
            return nil
        }

        return LogitechHIDPPTransport(device: device, deviceIndex: nil)
    }

    private func receiverTransport(for device: VendorSpecificDeviceContext) -> LogitechHIDPPTransport? {
        guard device.transport == "USB",
              let locationID = device.locationID,
              let receiverChannel = LogitechReceiverChannel.open(locationID: locationID),
              let slot = discoverReceiverSlot(for: device, using: receiverChannel)
        else {
            return nil
        }

        return LogitechHIDPPTransport(device: receiverChannel, deviceIndex: slot)
    }

    private func discoverReceiverSlot(
        for device: VendorSpecificDeviceContext,
        using receiver: LogitechReceiverChannel
    ) -> UInt8? {
        let currentFlags = receiver.readNotificationFlags() ?? 0
        let desiredFlags = currentFlags | Constants.receiverWirelessNotifications | Constants
            .receiverSoftwarePresentNotifications
        if desiredFlags != currentFlags {
            _ = receiver.writeNotificationFlags(desiredFlags)
        }

        guard let slots = receiver.discoverSlots() else {
            return nil
        }

        let normalizedProduct = normalizeName(device.product ?? device.name)

        if let exactNameMatch = slots.first(where: {
            guard let name = $0.name else {
                return false
            }
            return normalizeName(name) == normalizedProduct
        }) {
            return exactNameMatch.slot
        }

        let desiredKinds = preferredReceiverDeviceKinds(for: device)
        if let kindMatch = slots.first(where: { desiredKinds.contains($0.kind) }) {
            return kindMatch.slot
        }

        if slots.count == 1 {
            return slots[0].slot
        }

        let routedSlots = discoverRoutedSlots(using: receiver)

        if let exactRoutedNameMatch = routedSlots.first(where: {
            guard let name = $0.name else {
                return false
            }
            return normalizeName(name) == normalizedProduct
        }) {
            return exactRoutedNameMatch.slot
        }

        if routedSlots.count == 1 {
            return routedSlots[0].slot
        }

        if let batteryBackedSlot = routedSlots.first(where: { $0.batteryLevel != nil }) {
            return batteryBackedSlot.slot
        }

        return nil
    }

    private func discoverRoutedSlots(using receiver: LogitechReceiverChannel) -> [ReceiverSlotMetadata] {
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

    private func readFriendlyName(using transport: LogitechHIDPPTransport) -> String? {
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

    private func readName(using transport: LogitechHIDPPTransport) -> String? {
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
        device.transport == "USB"
            && device.primaryUsagePage == 0xFF00
            && device.primaryUsage == 0x01
    }

    private func normalizeName(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct LogitechHIDPPTransport {
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
            "Transport": "USB",
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

    func discoverSlots() -> [LogitechHIDPPDeviceMetadataProvider.ReceiverSlotInfo]? {
        _ = readConnectionState()

        var discovered = [UInt8: UInt8]()
        if triggerConnectionNotifications() {
            let deadline = Date().addingTimeInterval(0.5)
            while Date() < deadline {
                guard let report = waitForInputReport(timeout: 0.05, matching: { response in
                    let bytes = [UInt8](response)
                    return bytes.count >= 7 && bytes[0] == LogitechHIDPPDeviceMetadataProvider.Constants
                        .shortReportID && bytes[2] == 0x41
                }) else {
                    continue
                }

                let bytes = [UInt8](report)
                discovered[bytes[1]] = bytes[4] & 0x0F
            }
        }

        var slots = [LogitechHIDPPDeviceMetadataProvider.ReceiverSlotInfo]()
        for slot in UInt8(1) ... UInt8(6) {
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
                continue
            }

            let kind = discovered[slot]
                ?? pairingResponse.flatMap(Self.parseReceiverKind)
                ?? 0
            let name = nameResponse.flatMap(Self.parseReceiverName)
            let productID = pairingResponse.flatMap(Self.parseReceiverProductID)
            let serialNumber = extendedPairingResponse.flatMap(Self.parseReceiverSerialNumber)
            let batteryLevel = LogitechHIDPPTransport(device: self, deviceIndex: slot).flatMap {
                LogitechHIDPPDeviceMetadataProvider().readReceiverBatteryLevel(using: $0)
            }
            slots.append(
                .init(
                    slot: slot,
                    kind: kind,
                    name: name,
                    productID: productID,
                    serialNumber: serialNumber,
                    batteryLevel: batteryLevel
                )
            )
        }

        return slots.isEmpty ? nil : slots
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

    private func waitForInputReport(timeout: TimeInterval, matching: @escaping (Data) -> Bool) -> Data? {
        requestLock.lock()
        defer { requestLock.unlock() }

        let semaphore = DispatchSemaphore(value: 0)
        pendingLock.lock()
        pendingMatcher = matching
        pendingResponse = nil
        pendingSemaphore = semaphore
        pendingLock.unlock()

        return waitForPendingResponse(timeout: timeout)
    }

    private func waitForPendingResponse(timeout: TimeInterval) -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
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

extension LogitechReceiverChannel: ReceiverActivityChannel {
    func enableWirelessNotifications() {
        let currentFlags = readNotificationFlags() ?? 0
        let desiredFlags = currentFlags | LogitechHIDPPDeviceMetadataProvider.Constants
            .receiverWirelessNotifications | LogitechHIDPPDeviceMetadataProvider.Constants
            .receiverSoftwarePresentNotifications
        if desiredFlags != currentFlags {
            _ = writeNotificationFlags(desiredFlags)
        }
    }

    func switchToDJMode() {
        var bytes = [UInt8](repeating: 0, count: LogitechHIDPPDeviceMetadataProvider.Constants.djShortReportLength)
        bytes[0] = LogitechHIDPPDeviceMetadataProvider.Constants.djShortReportID
        bytes[1] = LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex
        bytes[2] = LogitechHIDPPDeviceMetadataProvider.Constants.djSwitchCommand
        bytes[3] = LogitechHIDPPDeviceMetadataProvider.Constants.djSwitchDeviceBitfield
        bytes[4] = 0x00

        let strategies: [IOHIDReportType] = {
            if let strategy = currentRequestStrategy() {
                return [strategy.requestType]
            }
            return [kIOHIDReportTypeOutput, kIOHIDReportTypeFeature]
        }()

        for reportType in strategies {
            let status = bytes.withUnsafeBytes { rawBuffer -> IOReturn in
                guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return kIOReturnBadArgument
                }

                return IOHIDDeviceSetReport(device, reportType, CFIndex(bytes[0]), baseAddress, bytes.count)
            }

            if status == kIOReturnSuccess {
                os_log(
                    "Receiver DJ mode switch sent: locationID=%{public}u reportType=%{public}d",
                    log: LogitechHIDPPDeviceMetadataProvider.log,
                    type: .info,
                    UInt32(locationID ?? 0),
                    Int(reportType.rawValue)
                )
                Thread.sleep(forTimeInterval: 0.05)
                return
            }
        }

        os_log(
            "Receiver DJ mode switch failed: locationID=%{public}u",
            log: LogitechHIDPPDeviceMetadataProvider.log,
            type: .info,
            UInt32(locationID ?? 0)
        )
    }

    func discoverPointingDeviceIdentities() -> [ReceiverLogicalDeviceIdentity] {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        guard let locationID,
              let slots = discoverSlots()
        else {
            return []
        }

        return slots.compactMap { slot in
            guard let kind = ReceiverLogicalDeviceKind(rawValue: slot.kind), kind.isPointingDevice else {
                return nil
            }

            return ReceiverLogicalDeviceIdentity(
                receiverLocationID: locationID,
                slot: slot.slot,
                kind: kind,
                name: slot.name ?? name,
                serialNumber: slot.serialNumber,
                productID: slot.productID,
                batteryLevel: slot.batteryLevel ?? LogitechHIDPPTransport(device: self, deviceIndex: slot.slot)
                    .flatMap { provider.readReceiverBatteryLevel(using: $0) }
            )
        }
    }

    func waitForActivePointingSlot(timeout: TimeInterval) -> UInt8? {
        let report = waitForInputReport(timeout: timeout) { response in
            let bytes = [UInt8](response)
            if let slot = ReceiverPacketParser.activePointingSlot(from: response) {
                os_log(
                    "Receiver raw activity packet: reportID=%{public}u slot=%{public}u type=%{public}u bytes=%{public}@",
                    log: LogitechHIDPPDeviceMetadataProvider.log,
                    type: .info,
                    UInt32(bytes[0]),
                    UInt32(slot),
                    UInt32(bytes[2]),
                    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                )
                return true
            }

            if bytes.count >= 3,
               [LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID,
                LogitechHIDPPDeviceMetadataProvider.Constants.longReportID,
                LogitechHIDPPDeviceMetadataProvider.Constants.djShortReportID,
                LogitechHIDPPDeviceMetadataProvider.Constants.djLongReportID].contains(bytes[0]) {
                os_log(
                    "Receiver raw packet: bytes=%{public}@",
                    log: LogitechHIDPPDeviceMetadataProvider.log,
                    type: .debug,
                    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                )
            }

            return false
        }
        return report.flatMap(ReceiverPacketParser.activePointingSlot)
    }
}

private extension LogitechHIDPPDeviceMetadataProvider.FeatureID {
    var bytes: [UInt8] {
        [UInt8(rawValue >> 8), UInt8(rawValue & 0xFF)]
    }
}
