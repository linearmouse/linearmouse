// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import Combine
import Foundation
import HIDPP
import IOKit.hid
import ObservationToken
import os.log
import PointerKit

/// Discovers Logitech HID++ metadata and owns shared receiver/device transports.
struct LogitechHIDPPDeviceMetadataProvider: VendorSpecificDeviceMetadataProvider {
    static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "LinearMouse",
        category: "LogitechHIDPP"
    )

    enum Constants {
        static let vendorID = HIDPPConstants.vendorID
        static let shortReportID = HIDPPConstants.shortReportID
        static let longReportID = HIDPPConstants.longReportID
        static let shortReportLength = HIDPPConstants.shortReportLength
        static let longReportLength = HIDPPConstants.longReportLength
        static let timeout = HIDPPConstants.timeout
        static let receiverProbeTimeout: TimeInterval = 0.25

        static let receiverIndex = HIDPPConstants.receiverIndex
        static let directReplyIndices = HIDPPConstants.directReplyIndices
        static let receiverNotificationFlagsRegister: UInt8 = 0x00
        static let receiverConnectionStateRegister: UInt8 = 0x02
        static let receiverInfoRegister: UInt8 = 0xB5
        static let receiverWirelessNotifications: UInt32 = 0x000100
        static let receiverSoftwarePresentNotifications: UInt32 = 0x000800
        /// Receiver PID source:
        /// - Solaar receiver catalog: https://pwr-solaar.github.io/Solaar/devices/
        /// - Linux receiver driver IDs: https://codebrowser.dev/linux/linux/drivers/hid/hid-logitech-dj.c.html
        ///
        /// Classic and Lightspeed receiver monitoring use the same receiver-level
        /// HID++ path: vendor HID application 0xFF000001, receiver index 0xFF,
        /// and HID++ 1.0 receiver registers 0x00/0x02/0xB5.
        static let monitorableClassicReceiverProductIDs: Set<Int> = [
            0xC52B, // Unifying receiver
            0xC532 // Unifying receiver
        ]
        static let monitorableLightspeedReceiverProductIDs: Set<Int> = [
            0xC539,
            0xC53A,
            0xC53D,
            0xC53F,
            0xC541,
            0xC543,
            0xC545,
            0xC547,
            0xC54D
        ]
        static let monitorableBoltReceiverProductIDs: Set<Int> = [
            0xC548 // Bolt receiver
        ]
        /// These are recognized as receiver dongles, but receiver monitoring is
        /// intentionally disabled until their protocol/transport path is implemented.
        static let knownReceiverProductIDsWithoutMonitoringSupport: Set<Int> = [
            // 27 MHz / early HID++ receivers.
            0xC513,
            0xC517,
            0xC51B,
            // Nano receivers. Some are partial HID++ 1.0 devices, and C52F is
            // mouse-only, so they need receiver-kind-specific handling.
            0xC518,
            0xC51A,
            0xC521,
            0xC525,
            0xC526,
            0xC52E,
            0xC52F,
            0xC534,
            0xC535,
            0xC542,
            // Early gaming receivers need Nano-specific handling.
            0xC531,
            0xC537
        ]
        static let knownReceiverProductIDs: Set<Int> = [
            monitorableClassicReceiverProductIDs,
            monitorableLightspeedReceiverProductIDs,
            monitorableBoltReceiverProductIDs,
            knownReceiverProductIDsWithoutMonitoringSupport
        ].reduce(into: []) { result, productIDs in
            result.formUnion(productIDs)
        }
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

    struct ReceiverConnectionSnapshotBatch {
        let snapshots: [UInt8: ReceiverConnectionSnapshot]
        let reconnectedSlots: Set<UInt8>

        static let empty = Self(snapshots: [:], reconnectedSlots: [])
    }

    /// Accumulates receiver connection notifications. A complete connected
    /// count is only actionable after a quiet wait: buffered follow-up events
    /// for the same slot must be allowed to replace an earlier snapshot.
    struct ReceiverConnectionSnapshotCollector {
        private let expectedConnectedDeviceCount: Int?
        private(set) var snapshots = [UInt8: ReceiverConnectionSnapshot]()
        private(set) var reconnectedSlots = Set<UInt8>()

        init(expectedConnectedDeviceCount: Int?) {
            self.expectedConnectedDeviceCount = expectedConnectedDeviceCount
        }

        mutating func record(slot: UInt8, snapshot: ReceiverConnectionSnapshot) {
            if snapshots[slot]?.isConnected == false, snapshot.isConnected {
                reconnectedSlots.insert(slot)
            }
            snapshots[slot] = snapshot
        }

        var batch: ReceiverConnectionSnapshotBatch {
            .init(snapshots: snapshots, reconnectedSlots: reconnectedSlots)
        }

        var isCompleteAfterQuietWait: Bool {
            guard let expectedConnectedDeviceCount else {
                return false
            }

            return snapshots.values.filter(\.isConnected).count >= expectedConnectedDeviceCount
        }
    }

    struct ReceiverSlotDiscovery {
        let slots: [ReceiverSlotInfo]
        let connectionSnapshots: [UInt8: ReceiverConnectionSnapshot]
        let expectedConnectedDeviceCount: Int?
        let inventoryAvailable: Bool
    }

    struct ReceiverPointingDeviceDiscovery {
        let identities: [ReceiverLogicalDeviceIdentity]
        let connectionSnapshots: [UInt8: ReceiverConnectionSnapshot]
        let liveReachableSlots: Set<UInt8>
        let expectedConnectedDeviceCount: Int?
        let inventoryAvailable: Bool
        /// Slot types successfully read during discovery, including keyboards
        /// and other non-pointing devices that are intentionally absent from
        /// `identities`.
        let observedSlotKinds: [UInt8: UInt8]

        init(
            identities: [ReceiverLogicalDeviceIdentity],
            connectionSnapshots: [UInt8: ReceiverConnectionSnapshot],
            liveReachableSlots: Set<UInt8>,
            expectedConnectedDeviceCount: Int? = nil,
            inventoryAvailable: Bool = true,
            observedSlotKinds: [UInt8: UInt8] = [:]
        ) {
            self.identities = identities
            self.connectionSnapshots = connectionSnapshots
            self.liveReachableSlots = liveReachableSlots
            self.expectedConnectedDeviceCount = expectedConnectedDeviceCount
            self.inventoryAvailable = inventoryAvailable
            self.observedSlotKinds = observedSlotKinds
        }
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

    enum ReceiverProtocolFamily: Equatable {
        case classic
        case lightspeed
        case bolt
    }

    static func receiverProtocolFamily(vendorID: Int?, productID: Int?, transport: String?) -> ReceiverProtocolFamily? {
        guard vendorID == Constants.vendorID,
              transport == PointerDeviceTransportName.usb,
              let productID
        else {
            return nil
        }

        if Constants.monitorableClassicReceiverProductIDs.contains(productID) {
            return .classic
        }

        if Constants.monitorableLightspeedReceiverProductIDs.contains(productID) {
            return .lightspeed
        }

        if Constants.monitorableBoltReceiverProductIDs.contains(productID) {
            return .bolt
        }

        return nil
    }

    static func supportsClassicReceiverMonitoring(vendorID: Int?, productID: Int?, transport: String?) -> Bool {
        receiverProtocolFamily(vendorID: vendorID, productID: productID, transport: transport) == .classic
    }

    static func supportsReprogrammableControlsMonitoring(
        vendorID: Int?,
        productID: Int?,
        transport: String?
    ) -> Bool {
        switch receiverProtocolFamily(vendorID: vendorID, productID: productID, transport: transport) {
        case .classic, .bolt:
            return true
        case .lightspeed, nil:
            return false
        }
    }

    static func supportsReceiverMonitoring(vendorID: Int?, productID: Int?, transport: String?) -> Bool {
        receiverProtocolFamily(vendorID: vendorID, productID: productID, transport: transport) != nil
    }

    static func isKnownReceiver(vendorID: Int?, productID: Int?) -> Bool {
        guard vendorID == Constants.vendorID,
              let productID
        else {
            return false
        }

        return Constants.knownReceiverProductIDs.contains(productID)
    }

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

    func metadata(
        for device: VendorSpecificDeviceContext,
        deadline: Date?,
        until operationShouldContinue: @escaping () -> Bool
    ) -> VendorSpecificDeviceMetadata? {
        let shouldContinue = {
            operationShouldContinue()
                && deadline.map { Date() < $0 } != false
        }
        guard shouldContinue() else {
            return nil
        }

        if let directTransport = directTransport(
            for: device,
            deadline: deadline,
            until: shouldContinue
        ) {
            return metadata(using: directTransport)
        }

        if let receiverTransport = receiverTransport(
            for: device,
            deadline: deadline,
            until: shouldContinue
        ) {
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

    func receiverSlot(
        for device: VendorSpecificDeviceContext,
        identities: [ReceiverLogicalDeviceIdentity]
    ) -> UInt8? {
        let normalizedSerial = LogitechStableSerial.normalize(device.serialNumber)
        if let serialMatch = uniqueIdentityMatch(identities, matching: {
            normalizedSerial != nil && LogitechStableSerial.normalize($0.serialNumber) == normalizedSerial
        }) {
            return serialMatch.slot
        }

        if let productID = device.productID,
           let productIDMatch = uniqueIdentityMatch(identities, matching: { $0.productID == productID }) {
            return productIDMatch.slot
        }

        let normalizedName = normalizeName(device.product ?? device.name)
        if let nameMatch = uniqueIdentityMatch(identities, matching: {
            normalizeName($0.name) == normalizedName
        }) {
            return nameMatch.slot
        }

        guard identities.count == 1 else {
            return nil
        }

        return identities[0].slot
    }

    func receiverSlot(
        for device: VendorSpecificDeviceContext,
        discovery: ReceiverPointingDeviceDiscovery
    ) -> UInt8? {
        guard let expectedConnectedDeviceCount = discovery.expectedConnectedDeviceCount else {
            // Explicit compatibility path for receivers without a usable
            // connected-count register.
            return receiverSlot(for: device, identities: discovery.identities)
        }
        guard expectedConnectedDeviceCount > 0 else {
            return nil
        }

        let activeSlots = Set(discovery.connectionSnapshots.compactMap { slot, snapshot in
            snapshot.isConnected ? slot : nil
        }).union(discovery.liveReachableSlots)
        let activeKinds = Dictionary(uniqueKeysWithValues: activeSlots.compactMap { slot -> (
            UInt8,
            ReceiverLogicalDeviceKind
        )? in
            guard let kind = resolveReceiverLogicalDeviceKind(
                snapshotRaw: discovery.connectionSnapshots[slot]?.kind,
                pairingRaw: discovery.observedSlotKinds[slot]
            ) else {
                return nil
            }
            return (slot, kind)
        })
        let activeIdentities = discovery.identities.filter { activeSlots.contains($0.slot) }

        let normalizedSerial = LogitechStableSerial.normalize(device.serialNumber)
        let serialMatches = activeIdentities.filter {
            normalizedSerial != nil && LogitechStableSerial.normalize($0.serialNumber) == normalizedSerial
        }
        if let serialMatch = uniqueIdentityMatch(serialMatches, matching: { _ in true }) {
            guard activeKinds[serialMatch.slot]?.isPointingDevice == true else {
                return nil
            }
            return serialMatch.slot
        }

        let pointingActiveSlots = Set(activeKinds.compactMap { slot, kind in
            kind.isPointingDevice ? slot : nil
        })
        let activeIdentitySlots = Set(activeIdentities.map(\.slot))
        guard discovery.inventoryAvailable,
              activeSlots.count == expectedConnectedDeviceCount,
              activeKinds.count == activeSlots.count,
              activeIdentitySlots == pointingActiveSlots
        else {
            return nil
        }

        return receiverSlot(for: device, identities: activeIdentities)
    }

    func openReceiverChannel(
        for device: VendorSpecificDeviceContext,
        notificationOwnershipSession: ReceiverNotificationOwnershipSession = .init()
    ) -> LogitechReceiverChannel? {
        guard device.transport == PointerDeviceTransportName.usb,
              let locationID = device.locationID
        else {
            return nil
        }

        return LogitechReceiverChannel.open(
            locationID: locationID,
            notificationOwnershipSession: notificationOwnershipSession
        )
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
        using receiverChannel: LogitechReceiverChannel,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> ReceiverPointingDeviceDiscovery {
        if Self.receiverProtocolFamily(
            vendorID: device.vendorID,
            productID: device.productID,
            transport: device.transport
        ) == .bolt {
            return receiverChannel.discoverBoltPointingDeviceDiscovery(
                baseName: device.product ?? device.name,
                until: shouldContinue
            )
        }

        return receiverChannel.discoverPointingDeviceDiscovery(
            baseName: device.product ?? device.name,
            until: shouldContinue
        )
    }

    func receiverSlotIdentity(
        for device: VendorSpecificDeviceContext,
        slot: UInt8,
        connectionSnapshot: ReceiverConnectionSnapshot?,
        using receiverChannel: LogitechReceiverChannel,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> ReceiverLogicalDeviceIdentity? {
        guard let locationID = receiverChannel.locationID else {
            return nil
        }

        let slotInfo: ReceiverSlotInfo?
        if Self.receiverProtocolFamily(
            vendorID: device.vendorID,
            productID: device.productID,
            transport: device.transport
        ) == .bolt {
            slotInfo = receiverChannel.discoverBoltSlotInfo(
                slot,
                connectionSnapshot: connectionSnapshot,
                until: shouldContinue
            )
        } else {
            slotInfo = receiverChannel.discoverSlotInfo(
                slot,
                connectionSnapshot: connectionSnapshot,
                until: shouldContinue
            )
        }

        guard let slotInfo else {
            return nil
        }

        guard let kind = resolveReceiverPointingIdentityKind(
            snapshotRaw: connectionSnapshot?.kind,
            pairingRaw: slotInfo.kind
        ), kind.isPointingDevice else {
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

    func validateReceiverSlotIdentity(
        for device: VendorSpecificDeviceContext,
        slot: UInt8,
        connectionSnapshot: ReceiverConnectionSnapshot? = nil,
        using receiverChannel: LogitechReceiverChannel,
        deadline: Date,
        until shouldContinue: @escaping () -> Bool
    ) -> ReceiverLogicalDeviceIdentity? {
        guard let locationID = receiverChannel.locationID else {
            return nil
        }
        let slotInfo: ReceiverSlotInfo?
        if Self.receiverProtocolFamily(
            vendorID: device.vendorID,
            productID: device.productID,
            transport: device.transport
        ) == .bolt {
            slotInfo = receiverChannel.validateBoltSlotIdentity(
                slot,
                deadline: deadline,
                until: shouldContinue
            )
        } else {
            slotInfo = receiverChannel.validateSlotIdentity(
                slot,
                deadline: deadline,
                until: shouldContinue
            )
        }
        guard let slotInfo,
              let kind = resolveReceiverPointingIdentityKind(
                  snapshotRaw: connectionSnapshot?.kind,
                  pairingRaw: slotInfo.kind
              ),
              kind.isPointingDevice
        else {
            return nil
        }

        return ReceiverLogicalDeviceIdentity(
            receiverLocationID: locationID,
            slot: slot,
            kind: kind,
            name: device.product ?? device.name,
            serialNumber: slotInfo.serialNumber,
            productID: slotInfo.productID,
            batteryLevel: nil
        )
    }

    func connectedDeviceCount(
        for device: VendorSpecificDeviceContext,
        using receiverChannel: LogitechReceiverChannel,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> Int? {
        let deadline = Date().addingTimeInterval(Constants.receiverProbeTimeout)
        switch Self.receiverProtocolFamily(
            vendorID: device.vendorID,
            productID: device.productID,
            transport: device.transport
        ) {
        case .bolt:
            return receiverChannel.boltConnectedDeviceCount(
                deadline: deadline,
                until: shouldContinue
            )
        case .classic, .lightspeed, nil:
            return receiverChannel.connectedDeviceCount(
                deadline: deadline,
                until: shouldContinue
            )
        }
    }

    func waitForReceiverConnectionChange(
        for device: VendorSpecificDeviceContext,
        timeout: TimeInterval,
        until shouldContinue: @escaping () -> Bool
    ) -> ReceiverConnectionSnapshotBatch {
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
                Thread.sleep(forTimeInterval: min(0.1, max(0, deadline.timeIntervalSinceNow)))
            }
            return .empty
        }

        return waitForReceiverConnectionChange(
            for: device,
            using: receiverChannel,
            timeout: timeout,
            until: shouldContinue
        )
    }

    func waitForReceiverConnectionChange(
        for device: VendorSpecificDeviceContext,
        using receiverChannel: LogitechReceiverChannel,
        timeout: TimeInterval,
        until shouldContinue: @escaping () -> Bool
    ) -> ReceiverConnectionSnapshotBatch {
        switch Self.receiverProtocolFamily(
            vendorID: device.vendorID,
            productID: device.productID,
            transport: device.transport
        ) {
        case .classic, .lightspeed:
            receiverChannel.enableWirelessNotifications(until: shouldContinue)
            return receiverChannel.waitForConnectionSnapshots(timeout: timeout, until: shouldContinue)
        case .bolt:
            return receiverChannel.waitForBoltConnectionSnapshots(timeout: timeout, until: shouldContinue)
        case nil:
            return .empty
        }
    }

    func receiverChannelIsReachable(
        for device: VendorSpecificDeviceContext,
        using receiverChannel: LogitechReceiverChannel,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> Bool {
        let deadline = Date().addingTimeInterval(Constants.receiverProbeTimeout)
        switch Self.receiverProtocolFamily(
            vendorID: device.vendorID,
            productID: device.productID,
            transport: device.transport
        ) {
        case .classic, .lightspeed:
            return receiverChannel.readNotificationFlags(
                deadline: deadline,
                until: shouldContinue
            ) != nil
        case .bolt:
            return receiverChannel.isBoltReceiverReachable(
                deadline: deadline,
                until: shouldContinue
            )
        case nil:
            return false
        }
    }

    private func metadata(using transport: HIDPPTransport) -> VendorSpecificDeviceMetadata? {
        let name = readFriendlyName(using: transport) ?? readName(using: transport)
        let batteryLevel = transport
            .isReceiverRoutedDevice ? readReceiverBatteryLevel(using: transport) : readBatteryLevel(using: transport)

        if name == nil, batteryLevel == nil {
            return nil
        }

        return VendorSpecificDeviceMetadata(name: name, batteryLevel: batteryLevel)
    }

    private func directTransport(
        for device: VendorSpecificDeviceContext,
        deadline: Date?,
        until shouldContinue: @escaping () -> Bool
    ) -> HIDPPTransport? {
        guard device.transport == PointerDeviceTransportName.bluetoothLowEnergy else {
            return nil
        }

        return HIDPPTransport(
            device: device,
            deviceIndex: nil,
            deadline: deadline,
            shouldContinue: shouldContinue
        )
    }

    private func receiverTransport(
        for device: VendorSpecificDeviceContext,
        deadline: Date?,
        until shouldContinue: @escaping () -> Bool
    ) -> HIDPPTransport? {
        guard device.transport == PointerDeviceTransportName.usb,
              let locationID = device.locationID,
              let receiverChannel = LogitechReceiverChannel.open(locationID: locationID),
              let slot = discoverReceiverSlot(
                  for: device,
                  using: receiverChannel,
                  until: shouldContinue
              )?.slot
        else {
            return nil
        }

        return HIDPPTransport(
            device: receiverChannel,
            deviceIndex: slot,
            deadline: deadline,
            shouldContinue: shouldContinue
        )
    }

    private func discoverReceiverSlot(
        for device: VendorSpecificDeviceContext,
        using receiver: LogitechReceiverChannel,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> ReceiverSlotMatchCandidate? {
        guard let discovery = receiver.discoverMatchCandidates(
            baseName: device.product ?? device.name,
            until: shouldContinue
        ) else {
            return nil
        }

        return receiverSlotCandidate(
            for: device,
            slots: discovery.slots,
            connectionSnapshots: discovery.connectionSnapshots,
            expectedConnectedDeviceCount: discovery.expectedConnectedDeviceCount,
            inventoryAvailable: discovery.inventoryAvailable
        )
    }

    /// Resolves a legacy receiver route only when the candidate can be uniquely
    /// identified. Compatibility fallbacks remain available for receivers that
    /// expose no per-device metadata, but they must be unique as well.
    func receiverSlotCandidate(
        for device: VendorSpecificDeviceContext,
        slots: [ReceiverSlotMatchCandidate]
    ) -> ReceiverSlotMatchCandidate? {
        resolveReceiverSlotCandidate(for: device, slots: slots)
    }

    func receiverSlotCandidate(
        for device: VendorSpecificDeviceContext,
        slots: [ReceiverSlotMatchCandidate],
        connectionSnapshots: [UInt8: ReceiverConnectionSnapshot],
        expectedConnectedDeviceCount: Int?,
        inventoryAvailable: Bool
    ) -> ReceiverSlotMatchCandidate? {
        guard let expectedConnectedDeviceCount else {
            // Legacy receivers that cannot report a count keep the existing,
            // explicitly compatibility-oriented fallback behavior.
            return resolveReceiverSlotCandidate(for: device, slots: slots)
        }
        guard expectedConnectedDeviceCount > 0 else {
            return nil
        }

        let activeSlots = Set(connectionSnapshots.compactMap { slot, snapshot in
            snapshot.isConnected ? slot : nil
        }).union(slots.filter(\.hasLiveMetadata).map(\.slot))
        let candidatesBySlot = Dictionary(uniqueKeysWithValues: slots.map { ($0.slot, $0) })
        let resolvedKinds = Dictionary(uniqueKeysWithValues: activeSlots.compactMap { slot -> (
            UInt8,
            ReceiverLogicalDeviceKind
        )? in
            guard let kind = resolveReceiverLogicalDeviceKind(
                snapshotRaw: connectionSnapshots[slot]?.kind,
                pairingRaw: candidatesBySlot[slot]?.kind
            ) else {
                return nil
            }
            return (slot, kind)
        })

        let pointingSlotsWithCandidates = Set(activeSlots.filter { slot in
            guard resolvedKinds[slot]?.isPointingDevice == true,
                  let candidateKind = candidatesBySlot[slot]
                  .flatMap({ ReceiverLogicalDeviceKind(rawValue: $0.kind) })
            else {
                return false
            }
            return candidateKind.isPointingDevice
        })

        let desiredKinds = preferredReceiverDeviceKinds(for: device)
        let routeCandidates = slots.filter { candidate in
            guard pointingSlotsWithCandidates.contains(candidate.slot) else {
                return false
            }
            guard !desiredKinds.isEmpty else {
                return true
            }

            return desiredKinds.contains(candidate.kind)
        }

        let normalizedSerial = LogitechStableSerial.normalize(device.serialNumber)
        let serialMatches = routeCandidates.filter {
            normalizedSerial != nil && LogitechStableSerial.normalize($0.serialNumber) == normalizedSerial
        }
        if let serialMatch = uniqueSlotMatch(serialMatches) {
            // A precise active serial match remains safe even while another
            // connected slot is incompletely observed.
            return serialMatch
        }

        guard inventoryAvailable,
              activeSlots.count == expectedConnectedDeviceCount,
              resolvedKinds.count == activeSlots.count,
              pointingSlotsWithCandidates == Set(resolvedKinds.compactMap { slot, kind in
                  kind.isPointingDevice ? slot : nil
              })
        else {
            return nil
        }

        return resolveReceiverSlotCandidate(for: device, slots: routeCandidates)
    }

    private func resolveReceiverSlotCandidate(
        for device: VendorSpecificDeviceContext,
        slots: [ReceiverSlotMatchCandidate]
    ) -> ReceiverSlotMatchCandidate? {
        guard !slots.isEmpty else {
            return nil
        }

        let normalizedProduct = normalizeName(device.product ?? device.name)
        let normalizedSerial = LogitechStableSerial.normalize(device.serialNumber)
        let desiredProductID = device.productID

        let serialMatches = slots.filter {
            LogitechStableSerial.normalize($0.serialNumber) == normalizedSerial && normalizedSerial != nil
        }
        if !serialMatches.isEmpty {
            return uniqueSlotMatch(serialMatches)
        }

        let productIDMatches = slots.filter { candidate in
            guard let desiredProductID, let productID = candidate.productID else {
                return false
            }

            return productID == desiredProductID
        }
        if !productIDMatches.isEmpty {
            return uniqueSlotMatch(productIDMatches)
        }

        let nameMatches = slots.filter {
            guard let name = $0.name else {
                return false
            }
            return normalizeName(name) == normalizedProduct
        }
        if !nameMatches.isEmpty {
            return uniqueSlotMatch(nameMatches)
        }

        let desiredKinds = preferredReceiverDeviceKinds(for: device)
        let kindMatches = slots.filter { desiredKinds.contains($0.kind) }
        if !kindMatches.isEmpty {
            return uniqueSlotMatch(kindMatches)
        }

        if slots.count == 1 {
            let candidate = slots[0]
            if !desiredKinds.isEmpty,
               ReceiverLogicalDeviceKind(rawValue: candidate.kind) != nil,
               !desiredKinds.contains(candidate.kind) {
                return nil
            }
            return candidate
        }

        return nil
    }

    fileprivate func discoverRoutedSlots(using receiver: LogitechReceiverChannel) -> [ReceiverSlotMetadata] {
        var results = [ReceiverSlotMetadata]()

        for slot in UInt8(1) ... UInt8(6) {
            guard let transport = HIDPPTransport(device: receiver, deviceIndex: slot) else {
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

    func readFriendlyName(using transport: HIDPPTransport) -> String? {
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

    func readName(using transport: HIDPPTransport) -> String? {
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
        using transport: HIDPPTransport,
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

    fileprivate func readBatteryLevel(using transport: HIDPPTransport) -> Int? {
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

    func readReceiverBatteryLevel(using transport: HIDPPTransport) -> Int? {
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

    private func normalizeName(_ name: String?) -> String? {
        guard let name else {
            return nil
        }

        let normalized = normalizeName(name)
        return normalized.isEmpty ? nil : normalized
    }

    private func uniqueIdentityMatch(
        _ identities: [ReceiverLogicalDeviceIdentity],
        matching matches: (ReceiverLogicalDeviceIdentity) -> Bool
    ) -> ReceiverLogicalDeviceIdentity? {
        let matchingIdentities = identities.filter(matches)
        return matchingIdentities.count == 1 ? matchingIdentities[0] : nil
    }

    private func uniqueSlotMatch(
        _ slots: [ReceiverSlotMatchCandidate]
    ) -> ReceiverSlotMatchCandidate? {
        slots.count == 1 ? slots[0] : nil
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

enum HIDPPCommittedTransaction {
    /// A sent transaction retains exclusive ownership until its matching reply,
    /// transport invalidation, or deadline. Cancellation only discards the
    /// result so a late reply cannot satisfy the next transaction.
    static func settle<Response>(
        until deadline: Date,
        shouldDeliverResult: () -> Bool,
        isTransportValid: () -> Bool,
        wait: (TimeInterval) -> Void,
        response: () -> Response?
    ) -> Response? {
        while Date() < deadline {
            if let response = response() {
                return shouldDeliverResult() ? response : nil
            }
            guard isTransportValid() else {
                return nil
            }

            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                break
            }
            wait(min(remaining, 0.05))
        }

        guard let response = response() else {
            return nil
        }
        return shouldDeliverResult() ? response : nil
    }
}

enum SharedChannelOwnership {
    static func detach<Channel: AnyObject>(
        _ expected: Channel,
        from current: inout Channel?
    ) -> Bool {
        guard current === expected else {
            return false
        }
        current = nil
        return true
    }
}

final class LogitechReceiverChannel: VendorSpecificDeviceContext, HIDPPCancellableDeviceIO {
    private final class WeakChannelReference {
        weak var channel: LogitechReceiverChannel?

        init(_ channel: LogitechReceiverChannel) {
            self.channel = channel
        }
    }

    private struct ChannelClose {
        let channel: LogitechReceiverChannel
        let ownership: ReceiverChannelClosingOwnership
    }

    private enum OpenPreparation {
        case existing(LogitechReceiverChannel)
        case create(ReceiverChannelOpeningOwnership)
        case unavailable
    }

    /// Retains one exact receiver channel while its monitor producer is being
    /// stopped and terminal hardware restoration is in progress.
    ///
    /// Finishing first detaches only this channel from the shared cache, then
    /// invalidates it away from the main thread. A stale lease can therefore
    /// neither detach nor close a replacement channel.
    final class TerminalTeardown {
        let locationID: Int
        let retainedAdmissionChannel: Bool

        private let ownership: ReceiverChannelTerminalOwnership
        private let notificationOwnershipSession: ReceiverNotificationOwnershipSession
        private let finishState: ReceiverChannelTerminalFinishState
        private let channel: ReceiverChannelTerminalResource<LogitechReceiverChannel>

        fileprivate init(
            locationID: Int,
            channel: LogitechReceiverChannel?,
            ownership: ReceiverChannelTerminalOwnership,
            notificationOwnershipSession: ReceiverNotificationOwnershipSession
        ) {
            self.locationID = locationID
            retainedAdmissionChannel = channel != nil
            self.channel = ReceiverChannelTerminalResource(channel)
            self.ownership = ownership
            self.notificationOwnershipSession = notificationOwnershipSession
            finishState = ReceiverChannelTerminalFinishState { action in
                let runLoop = CFRunLoopGetMain()
                CFRunLoopPerformBlock(
                    runLoop,
                    CFRunLoopMode.commonModes.rawValue,
                    action
                )
                CFRunLoopWakeUp(runLoop)
            }
        }

        deinit {
            finish()
        }

        func restoreOwnedNotificationFlags(
            until shouldContinue: @escaping () -> Bool = { true },
            completion: @escaping () -> Void
        ) {
            DispatchQueue.global(qos: .utility).async { [self] in
                guard shouldContinue(), finishState.allowsRestore,
                      let channel = resolvedChannel(until: shouldContinue)
                else {
                    LogitechReceiverChannel.deliverOnMainRunLoop(completion)
                    return
                }
                let hasStableReceiverIdentity = LogitechStableSerial.normalize(channel.serialNumber) != nil
                guard retainedAdmissionChannel || hasStableReceiverIdentity else {
                    // A newly opened serial-less channel might be a physical
                    // replacement at the same USB topology. Session ownership
                    // cannot authorize a write to that unverified receiver.
                    LogitechReceiverChannel.deliverOnMainRunLoop(completion)
                    return
                }

                channel.restoreOwnedNotificationFlags(
                    shouldContinue: { [self, channel] in
                        shouldContinue() && isCurrentOwner(channel)
                    },
                    completion: completion
                )
            }
        }

        /// Re-reads only the expected logical slot on the exact terminal-owned
        /// channel. A full six-slot inventory can exceed the quit budget; this
        /// targeted check is sufficient to prove a stable route before writing.
        func validateLogicalDevice(
            for device: VendorSpecificDeviceContext,
            slot: UInt8,
            deadline: Date,
            until shouldContinue: @escaping () -> Bool,
            completion: @escaping (ReceiverLogicalDeviceIdentity?) -> Void
        ) {
            DispatchQueue.global(qos: .utility).async { [self] in
                guard shouldContinue(), finishState.allowsRestore,
                      let channel = resolvedChannel(until: shouldContinue)
                else {
                    LogitechReceiverChannel.deliverOnMainRunLoop { completion(nil) }
                    return
                }

                let identity = LogitechHIDPPDeviceMetadataProvider()
                    .validateReceiverSlotIdentity(
                        for: device,
                        slot: slot,
                        using: channel,
                        deadline: deadline,
                        until: shouldContinue
                    )
                LogitechReceiverChannel.deliverOnMainRunLoop {
                    completion(shouldContinue() ? identity : nil)
                }
            }
        }

        /// Idempotently releases terminal ownership. IOHID cancellation is not
        /// allowed to hold AppKit's termination run loop hostage.
        func finish(completion: @escaping () -> Void = {}) {
            let finishState = finishState
            guard finishState.begin(completion: completion) else {
                return
            }

            let closingLocationID = locationID
            let terminalOwnership = ownership
            let retainedChannel = channel.takeForFinish()
            let close = LogitechReceiverChannel.beginTerminalChannelClose(
                locationID: closingLocationID,
                matching: retainedChannel,
                terminalOwnership: terminalOwnership
            )
            guard let close else {
                finishState.complete()
                return
            }

            DispatchQueue.global(qos: .utility).async {
                close.channel.invalidate()
                LogitechReceiverChannel.completeSharedChannelClose(
                    locationID: closingLocationID,
                    closingOwnership: close.ownership
                )
                finishState.complete()
            }
        }

        private func resolvedChannel(
            until shouldContinue: @escaping () -> Bool
        ) -> LogitechReceiverChannel? {
            if let channel = channel.current {
                return channel
            }
            guard let resolvedChannel = LogitechReceiverChannel.openTerminalChannel(
                locationID: locationID,
                terminalOwnership: ownership,
                notificationOwnershipSession: notificationOwnershipSession,
                until: shouldContinue,
                accept: { [channel] candidate in
                    shouldContinue() && channel.accept(candidate)
                }
            ) else {
                return nil
            }
            return resolvedChannel
        }

        private func isCurrentOwner(_ channel: LogitechReceiverChannel) -> Bool {
            finishState.allowsRestore
                && channel.terminalAdmission.isOwned(by: ownership)
                && LogitechReceiverChannel.isCurrentSharedChannel(
                    channel,
                    locationID: locationID
                )
        }
    }

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
    private let ioQueue: DispatchQueue
    private let ioQueueKey = DispatchSpecificKey<Void>()
    private let cancellationSemaphore = DispatchSemaphore(value: 0)
    private let lifecycleLock = NSLock()
    private var isActivated = false
    private let inputReportBufferLength: Int
    private var inputReportBuffer: UnsafeMutablePointer<UInt8>?
    private let pendingLock = NSLock()
    private let requestLock = NSLock()
    private let strategyLock = NSLock()
    private var pendingMatcher: ((Data) -> Bool)?
    private var pendingResponse: Data?
    private var pendingSemaphore: DispatchSemaphore?
    private var requestStrategy: RequestStrategy?
    private var requestStrategyFailureCount = 0
    private let notificationBuffer = HIDPPNotificationBuffer()
    private let terminalAdmission = ReceiverChannelTerminalAdmission()

    /// Serial-backed receiver ownership survives the process. An unidentified
    /// receiver remains scoped to its concrete monitor session, which can span
    /// safe channel reconstruction but is never recreated from a location ID.
    private static let receiverNotificationOwnershipStore = ReceiverNotificationOwnershipStore()
    private let receiverNotificationOwnershipSession: ReceiverNotificationOwnershipSession

    // Keep one I/O reader per physical receiver. Opening the same macOS HID
    // interface more than once can route a command response to another callback.
    private static var sharedChannels = [Int: WeakChannelReference]()
    private static var openingChannels = ReceiverChannelOwnershipRegistry<ReceiverChannelOpeningOwnership>()
    private static var closingChannels = ReceiverChannelOwnershipRegistry<ReceiverChannelClosingOwnership>()
    private static var terminalChannels = ReceiverChannelOwnershipRegistry<ReceiverChannelTerminalOwnership>()
    private static let notificationOwnershipSessions = ReceiverNotificationOwnershipSessionRegistry()
    private static let sharedChannelsLock = NSLock()

    private static let inputReportCallback: IOHIDReportCallback = { context, _, _, _, _, report, reportLength in
        guard let context else {
            return
        }

        let this = Unmanaged<LogitechReceiverChannel>.fromOpaque(context).takeUnretainedValue()
        this.handleInputReport(Data(bytes: report, count: reportLength))
    }

    private static func deliverOnMainRunLoop(_ action: @escaping () -> Void) {
        let runLoop = CFRunLoopGetMain()
        CFRunLoopPerformBlock(
            runLoop,
            CFRunLoopMode.commonModes.rawValue,
            action
        )
        CFRunLoopWakeUp(runLoop)
    }

    static func open(
        locationID: Int,
        notificationOwnershipSession: ReceiverNotificationOwnershipSession = .init()
    ) -> LogitechReceiverChannel? {
        let preparation = sharedChannelsLock.withLock {
            prepareNormalOpenLocked(locationID: locationID)
        }
        switch preparation {
        case let .existing(channel):
            return channel
        case .unavailable:
            return nil
        case let .create(openingOwnership):
            let notificationOwnershipResolution = sharedChannelsLock.withLock {
                notificationOwnershipSessions.resolveForOpen(
                    locationID: locationID,
                    proposed: notificationOwnershipSession
                )
            }
            let channel = makeChannel(
                locationID: locationID,
                notificationOwnershipSession: notificationOwnershipResolution.session
            )
            return completeNormalOpen(
                channel,
                locationID: locationID,
                openingOwnership: openingOwnership,
                notificationOwnershipResolution: notificationOwnershipResolution
            )
        }
    }

    static func registerNotificationOwnershipSession(
        locationID: Int,
        proposed: ReceiverNotificationOwnershipSession
    ) -> ReceiverNotificationOwnershipSessionRegistry.Registration {
        sharedChannelsLock.withLock {
            notificationOwnershipSessions.register(
                locationID: locationID,
                proposed: proposed,
                existingChannelSession: sharedChannels[locationID]?.channel?
                    .receiverNotificationOwnershipSession
            )
        }
    }

    static func unregisterNotificationOwnershipSession(
        locationID: Int,
        matching registration: ReceiverNotificationOwnershipSessionRegistry.Registration
    ) {
        sharedChannelsLock.withLock {
            notificationOwnershipSessions.unregister(
                locationID: locationID,
                registration: registration
            )
        }
    }

    /// Main-thread terminal admission is deliberately lock-only. A missing
    /// channel is opened later by TerminalTeardown's utility worker, inside the
    /// existing hard cleanup deadline.
    static func beginTerminalTeardown(
        locationID: Int,
        notificationOwnershipSession: ReceiverNotificationOwnershipSession
    ) -> TerminalTeardown? {
        sharedChannelsLock.withLock {
            let ownership = ReceiverChannelTerminalOwnership()
            guard terminalChannels.begin(locationID: locationID, ownership: ownership) else {
                return nil
            }

            let channel = sharedChannels[locationID]?.channel
            if let channel, !channel.terminalAdmission.begin(ownership: ownership) {
                _ = terminalChannels.release(locationID: locationID, ownership: ownership)
                return nil
            }

            return TerminalTeardown(
                locationID: locationID,
                channel: channel,
                ownership: ownership,
                notificationOwnershipSession: notificationOwnershipSession
            )
        }
    }

    private static func makeChannel(
        locationID: Int,
        notificationOwnershipSession: ReceiverNotificationOwnershipSession
    ) -> LogitechReceiverChannel? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching: [String: Any] = [
            kIOHIDVendorIDKey: LogitechHIDPPDeviceMetadataProvider.Constants.vendorID,
            "LocationID": locationID,
            "Transport": PointerDeviceTransportName.usb,
            kIOHIDPrimaryUsagePageKey: 0xFF00,
            kIOHIDPrimaryUsageKey: 0x01
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let hidDevice = devices.first
        else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }

        guard let channel = LogitechReceiverChannel(
            manager: manager,
            device: hidDevice,
            notificationOwnershipSession: notificationOwnershipSession
        ) else {
            return nil
        }
        return channel
    }

    private static func prepareNormalOpenLocked(locationID: Int) -> OpenPreparation {
        // A terminal claim forbids creating another reader, but the exact
        // retained shared channel remains the transport for DPI, wheel and
        // controls restoration after their feature caches are invalidated.
        if let channel = sharedChannels[locationID]?.channel {
            return .existing(channel)
        }
        guard !terminalChannels.isClaimed(locationID: locationID),
              !openingChannels.isClaimed(locationID: locationID),
              !closingChannels.isClaimed(locationID: locationID)
        else {
            return .unavailable
        }

        let ownership = ReceiverChannelOpeningOwnership()
        guard openingChannels.begin(locationID: locationID, ownership: ownership) else {
            return .unavailable
        }
        return .create(ownership)
    }

    private static func completeNormalOpen(
        _ channel: LogitechReceiverChannel?,
        locationID: Int,
        openingOwnership: ReceiverChannelOpeningOwnership,
        notificationOwnershipResolution: ReceiverNotificationOwnershipSessionRegistry.OpenResolution
    ) -> LogitechReceiverChannel? {
        let adopted = sharedChannelsLock.withLock { () -> Bool in
            guard openingChannels.isOwned(locationID: locationID, by: openingOwnership) else {
                return false
            }
            guard let channel,
                  sharedChannels[locationID]?.channel == nil,
                  !closingChannels.isClaimed(locationID: locationID),
                  !terminalChannels.isClaimed(locationID: locationID),
                  notificationOwnershipResolution.session === channel.receiverNotificationOwnershipSession,
                  notificationOwnershipSessions.permitsAdoption(
                      locationID: locationID,
                      resolution: notificationOwnershipResolution
                  )
            else {
                return false
            }

            sharedChannels[locationID] = WeakChannelReference(channel)
            _ = openingChannels.release(locationID: locationID, ownership: openingOwnership)
            return true
        }
        if adopted {
            return channel
        }

        // Retain the opening claim through cancellation so another opener can
        // never overlap this rejected physical reader.
        channel?.invalidate()
        sharedChannelsLock.withLock {
            _ = openingChannels.release(locationID: locationID, ownership: openingOwnership)
        }
        return nil
    }

    private static func openTerminalChannel(
        locationID: Int,
        terminalOwnership: ReceiverChannelTerminalOwnership,
        notificationOwnershipSession: ReceiverNotificationOwnershipSession,
        until shouldContinue: @escaping () -> Bool,
        accept: @escaping (LogitechReceiverChannel) -> Bool
    ) -> LogitechReceiverChannel? {
        var backoff = ExponentialBackoff(initialDelay: 0.02, maximumDelay: 0.2)
        while shouldContinue() {
            let preparation = sharedChannelsLock.withLock {
                prepareTerminalOpenLocked(
                    locationID: locationID,
                    terminalOwnership: terminalOwnership
                )
            }
            switch preparation {
            case let .existing(channel):
                return channel
            case .unavailable:
                Thread.sleep(forTimeInterval: backoff.nextDelay())
            case let .create(openingOwnership):
                guard shouldContinue() else {
                    _ = completeTerminalOpen(
                        nil,
                        locationID: locationID,
                        openingOwnership: openingOwnership,
                        terminalOwnership: terminalOwnership,
                        accept: accept
                    )
                    return nil
                }
                let channel = makeChannel(
                    locationID: locationID,
                    notificationOwnershipSession: notificationOwnershipSession
                )
                if let adopted = completeTerminalOpen(
                    channel,
                    locationID: locationID,
                    openingOwnership: openingOwnership,
                    terminalOwnership: terminalOwnership,
                    accept: accept
                ) {
                    return adopted
                }
                if shouldContinue() {
                    Thread.sleep(forTimeInterval: backoff.nextDelay())
                }
            }
        }
        return nil
    }

    private static func prepareTerminalOpenLocked(
        locationID: Int,
        terminalOwnership: ReceiverChannelTerminalOwnership
    ) -> OpenPreparation {
        guard terminalChannels.isOwned(locationID: locationID, by: terminalOwnership) else {
            return .unavailable
        }
        if let channel = sharedChannels[locationID]?.channel {
            guard channel.terminalAdmission.isOwned(by: terminalOwnership)
                || channel.terminalAdmission.begin(ownership: terminalOwnership)
            else {
                return .unavailable
            }
            return .existing(channel)
        }
        guard !openingChannels.isClaimed(locationID: locationID),
              !closingChannels.isClaimed(locationID: locationID)
        else {
            return .unavailable
        }

        let ownership = ReceiverChannelOpeningOwnership()
        guard openingChannels.begin(locationID: locationID, ownership: ownership) else {
            return .unavailable
        }
        return .create(ownership)
    }

    private static func completeTerminalOpen(
        _ channel: LogitechReceiverChannel?,
        locationID: Int,
        openingOwnership: ReceiverChannelOpeningOwnership,
        terminalOwnership: ReceiverChannelTerminalOwnership,
        accept: (LogitechReceiverChannel) -> Bool
    ) -> LogitechReceiverChannel? {
        let adopted = sharedChannelsLock.withLock { () -> Bool in
            guard openingChannels.isOwned(locationID: locationID, by: openingOwnership) else {
                return false
            }
            guard let channel,
                  terminalChannels.isOwned(locationID: locationID, by: terminalOwnership),
                  sharedChannels[locationID]?.channel == nil,
                  !closingChannels.isClaimed(locationID: locationID),
                  channel.terminalAdmission.begin(ownership: terminalOwnership),
                  accept(channel)
            else {
                return false
            }

            sharedChannels[locationID] = WeakChannelReference(channel)
            _ = openingChannels.release(locationID: locationID, ownership: openingOwnership)
            return true
        }
        if adopted {
            return channel
        }

        channel?.invalidate()
        sharedChannelsLock.withLock {
            _ = openingChannels.release(locationID: locationID, ownership: openingOwnership)
        }
        return nil
    }

    private static func isCurrentSharedChannel(
        _ channel: LogitechReceiverChannel,
        locationID: Int
    ) -> Bool {
        sharedChannelsLock.withLock {
            sharedChannels[locationID]?.channel === channel
        }
    }

    /// Retires an ordinary monitor channel with exact close ownership. The
    /// location remains unavailable until IOHID cancellation has completed,
    /// so a replacement reader can never overlap the old one.
    @discardableResult
    static func retireSharedChannel(locationID: Int, matching channel: LogitechReceiverChannel) -> Bool {
        let close = sharedChannelsLock.withLock { () -> ChannelClose? in
            guard channel.terminalAdmission.allowsProducerMutation else {
                return nil
            }
            return beginSharedChannelCloseLocked(locationID: locationID, matching: channel)
        }
        guard let close else {
            return false
        }

        let budget = ReceiverChannelRetirementBudget()
        _ = close.channel.restoreOwnedNotificationFlagsSynchronously(deadline: budget.deadline) {
            budget.shouldContinue(transportIsActive: close.channel.isTransportActive)
        }
        close.channel.invalidate()
        completeSharedChannelClose(
            locationID: locationID,
            closingOwnership: close.ownership
        )
        return true
    }

    private static func beginTerminalChannelClose(
        locationID: Int,
        matching channel: LogitechReceiverChannel?,
        terminalOwnership: ReceiverChannelTerminalOwnership
    ) -> ChannelClose? {
        sharedChannelsLock.withLock {
            guard terminalChannels.isOwned(locationID: locationID, by: terminalOwnership) else {
                return nil
            }
            defer {
                _ = terminalChannels.release(locationID: locationID, ownership: terminalOwnership)
            }
            guard let channel,
                  channel.terminalAdmission.isOwned(by: terminalOwnership) else {
                return nil
            }
            return beginSharedChannelCloseLocked(locationID: locationID, matching: channel)
        }
    }

    private static func completeSharedChannelClose(
        locationID: Int,
        closingOwnership: ReceiverChannelClosingOwnership
    ) {
        sharedChannelsLock.withLock {
            _ = closingChannels.release(
                locationID: locationID,
                ownership: closingOwnership
            )
        }
    }

    private static func beginSharedChannelCloseLocked(
        locationID: Int,
        matching channel: LogitechReceiverChannel
    ) -> ChannelClose? {
        let ownership = ReceiverChannelClosingOwnership()
        guard !openingChannels.isClaimed(locationID: locationID),
              closingChannels.begin(locationID: locationID, ownership: ownership),
              detachSharedChannelLocked(locationID: locationID, matching: channel)
        else {
            _ = closingChannels.release(locationID: locationID, ownership: ownership)
            return nil
        }
        return ChannelClose(channel: channel, ownership: ownership)
    }

    private static func detachSharedChannelLocked(
        locationID: Int,
        matching channel: LogitechReceiverChannel
    ) -> Bool {
        var currentChannel = sharedChannels[locationID]?.channel
        let detached = SharedChannelOwnership.detach(channel, from: &currentChannel)
        if detached {
            sharedChannels.removeValue(forKey: locationID)
        }
        return detached
    }

    init?(
        manager: IOHIDManager,
        device: IOHIDDevice,
        notificationOwnershipSession: ReceiverNotificationOwnershipSession
    ) {
        self.manager = manager
        self.device = device
        receiverNotificationOwnershipSession = notificationOwnershipSession
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
        ioQueue = DispatchQueue(
            label: "app.linearmouse.logitech-receiver.\(locationID ?? 0)",
            qos: .default
        )
        inputReportBufferLength = max(
            maxInputReportSize ?? LogitechHIDPPDeviceMetadataProvider.Constants.longReportLength,
            LogitechHIDPPDeviceMetadataProvider.Constants.longReportLength
        )

        let openStatus = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openStatus == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return nil
        }

        let inputReportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: inputReportBufferLength)
        self.inputReportBuffer = inputReportBuffer

        ioQueue.setSpecific(key: ioQueueKey, value: ())
        IOHIDDeviceSetDispatchQueue(device, ioQueue)
        IOHIDDeviceRegisterInputReportCallback(
            device,
            inputReportBuffer,
            inputReportBufferLength,
            Self.inputReportCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDDeviceSetCancelHandler(device) { [cancellationSemaphore, device, inputReportBuffer, manager] in
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            inputReportBuffer.deallocate()
            cancellationSemaphore.signal()
        }
        IOHIDDeviceActivate(device)
        lifecycleLock.withLock {
            isActivated = true
        }
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        let shouldCancel = lifecycleLock.withLock { () -> Bool in
            guard isActivated else {
                return false
            }

            isActivated = false
            return true
        }
        guard shouldCancel else {
            return
        }

        wake()
        IOHIDDeviceCancel(device)
        if DispatchQueue.getSpecific(key: ioQueueKey) == nil {
            cancellationSemaphore.wait()
        }
        inputReportBuffer = nil
    }

    func discoverSlots(
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverSlotDiscovery? {
        guard shouldContinue() else {
            return nil
        }
        let connectedDeviceCount = readConnectionState(
            deadline: Date().addingTimeInterval(
                LogitechHIDPPDeviceMetadataProvider.Constants.receiverProbeTimeout
            ),
            until: shouldContinue
        ).flatMap { response in
            LogitechHIDPPDeviceMetadataProvider.parseConnectedDeviceCount(response)
        }
        guard shouldContinue() else {
            return nil
        }
        let connectionSnapshots = discoverConnectionSnapshots(
            expectedCount: connectedDeviceCount,
            until: shouldContinue
        )
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

        // Prioritize slots known to be connected, then scan remaining slots
        let connectedSlotNumbers = connectionSnapshots
            .filter(\.value.isConnected)
            .map(\.key)
            .sorted()
        let remainingSlots = (UInt8(1) ... UInt8(6)).filter { !connectedSlotNumbers.contains($0) }
        let orderedSlots = connectedSlotNumbers + remainingSlots

        var pairedSlots = [LogitechHIDPPDeviceMetadataProvider.ReceiverSlotInfo]()
        for slot in orderedSlots {
            guard shouldContinue() else {
                return nil
            }
            guard let slotInfo = discoverSlotInfo(
                slot,
                connectionSnapshot: connectionSnapshots[slot],
                until: shouldContinue
            ) else {
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

        guard connectedDeviceCount != nil || !connectionSnapshots.isEmpty || !pairedSlots.isEmpty else {
            return nil
        }

        return .init(
            slots: pairedSlots,
            connectionSnapshots: connectionSnapshots,
            expectedConnectedDeviceCount: connectedDeviceCount,
            inventoryAvailable: true
        )
    }

    func connectedDeviceCount(
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> Int? {
        readConnectionState(deadline: deadline, until: shouldContinue).flatMap {
            LogitechHIDPPDeviceMetadataProvider.parseConnectedDeviceCount($0)
        }
    }

    func discoverSlotInfo(
        _ slot: UInt8,
        connectionSnapshot: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverSlotInfo? {
        let metadataProvider = LogitechHIDPPDeviceMetadataProvider()
        let pairingResponse = hidpp10LongRequest(
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverInfoRegister,
            subregister: UInt8(0x20 + Int(slot) - 1),
            deadline: Date().addingTimeInterval(
                LogitechHIDPPDeviceMetadataProvider.Constants.receiverProbeTimeout
            ),
            until: shouldContinue
        )
        let extendedPairingResponse = hidpp10LongRequest(
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverInfoRegister,
            subregister: UInt8(0x30 + Int(slot) - 1),
            deadline: Date().addingTimeInterval(
                LogitechHIDPPDeviceMetadataProvider.Constants.receiverProbeTimeout
            ),
            until: shouldContinue
        )
        let nameResponse = hidpp10LongRequest(
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverInfoRegister,
            subregister: UInt8(0x40 + Int(slot) - 1),
            deadline: Date().addingTimeInterval(
                LogitechHIDPPDeviceMetadataProvider.Constants.receiverProbeTimeout
            ),
            until: shouldContinue
        )

        guard pairingResponse != nil || nameResponse != nil else {
            return nil
        }

        let kind = pairingResponse.flatMap(Self.parseReceiverKind)
            ?? connectionSnapshot?.kind
            ?? 0
        let routedTransport = HIDPPTransport(
            device: self,
            deviceIndex: slot,
            requestTimeout: LogitechHIDPPDeviceMetadataProvider.Constants.receiverProbeTimeout,
            shouldContinue: shouldContinue
        )
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

    func validateSlotIdentity(
        _ slot: UInt8,
        deadline: Date,
        until shouldContinue: @escaping () -> Bool
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverSlotInfo? {
        let pairingResponse = hidpp10LongRequest(
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverInfoRegister,
            subregister: UInt8(0x20 + Int(slot) - 1),
            deadline: deadline,
            until: shouldContinue
        )
        guard shouldContinue(), let pairingResponse else {
            return nil
        }
        let extendedPairingResponse = hidpp10LongRequest(
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverInfoRegister,
            subregister: UInt8(0x30 + Int(slot) - 1),
            deadline: deadline,
            until: shouldContinue
        )
        guard shouldContinue() else {
            return nil
        }

        return .init(
            slot: slot,
            kind: Self.parseReceiverKind(pairingResponse) ?? 0,
            name: nil,
            productID: Self.parseReceiverProductID(pairingResponse),
            serialNumber: extendedPairingResponse.flatMap(Self.parseReceiverSerialNumber),
            batteryLevel: nil,
            hasLiveMetadata: false
        )
    }

    private func discoverConnectionSnapshots(
        expectedCount: Int? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot] {
        guard triggerConnectionNotifications(
            deadline: Date().addingTimeInterval(
                LogitechHIDPPDeviceMetadataProvider.Constants.receiverProbeTimeout
            ),
            until: shouldContinue
        ) else {
            return [:]
        }

        var collector = LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshotCollector(
            expectedConnectedDeviceCount: expectedCount
        )
        let deadline = Date().addingTimeInterval(0.5)
        while shouldContinue(), Date() < deadline {
            guard let report = waitForInputReport(timeout: 0.05, matching: { response in
                LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification(Array(response)) != nil
            }, until: shouldContinue) else {
                // No more notifications pending — if we already have enough connected snapshots, exit early
                if collector.isCompleteAfterQuietWait {
                    break
                }
                continue
            }

            guard let notification = LogitechHIDPPDeviceMetadataProvider
                .parseReceiverConnectionNotification(Array(report)) else {
                continue
            }

            collector.record(slot: notification.slot, snapshot: notification.snapshot)
        }

        return collector.snapshots
    }

    func discoverMatchCandidates(
        baseName: String,
        until shouldContinue: @escaping () -> Bool = { true }
    )
        -> (
            slots: [LogitechHIDPPDeviceMetadataProvider.ReceiverSlotMatchCandidate],
            connectionSnapshots: [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot],
            expectedConnectedDeviceCount: Int?,
            inventoryAvailable: Bool
        )? {
        enableWirelessNotifications(until: shouldContinue)

        guard let discovery = discoverSlots(until: shouldContinue) else {
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
                batteryLevel: slot.batteryLevel ?? HIDPPTransport(
                    device: self,
                    deviceIndex: slot.slot,
                    requestTimeout: LogitechHIDPPDeviceMetadataProvider.Constants.receiverProbeTimeout,
                    shouldContinue: shouldContinue
                )
                .flatMap { provider.readReceiverBatteryLevel(using: $0) },
                hasLiveMetadata: slot.hasLiveMetadata
            )
        }

        return (
            candidates,
            discovery.connectionSnapshots,
            discovery.expectedConnectedDeviceCount,
            discovery.inventoryAvailable
        )
    }

    func enableWirelessNotifications(
        until producerShouldContinue: @escaping () -> Bool = { true }
    ) {
        let ownership = receiverNotificationOwnership
        let requestedFlags = LogitechHIDPPDeviceMetadataProvider.Constants.receiverWirelessNotifications
            | LogitechHIDPPDeviceMetadataProvider.Constants.receiverSoftwarePresentNotifications
        let shouldContinue = { [self] in
            producerShouldContinue() && receiverNotificationIOIsCurrent()
        }
        let enabled = ownership.store.enable(
            requestedFlags,
            for: ownership.target,
            read: { [self] in readNotificationFlags(until: shouldContinue) },
            committingWrite: { [self] value, didCommit in
                writeNotificationFlags(
                    value,
                    until: shouldContinue,
                    onCommitted: didCommit
                )
            },
            shouldContinue: shouldContinue
        )
        if !enabled {
            os_log(
                "Failed to enable receiver wireless notifications: locationID=%{public}@",
                log: LogitechHIDPPDeviceMetadataProvider.log,
                type: .info,
                locationID.map(String.init) ?? "(nil)"
            )
        }
    }

    private var receiverNotificationOwnership: (
        store: ReceiverNotificationOwnershipStore,
        target: ReceiverNotificationOwnershipTarget
    ) {
        if let target = ReceiverNotificationOwnershipTarget.stableReceiver(
            vendorID: vendorID,
            serialNumber: serialNumber
        ) {
            return (Self.receiverNotificationOwnershipStore, target)
        }

        return (
            receiverNotificationOwnershipSession.store,
            .session(receiverNotificationOwnershipSession.identity)
        )
    }

    private func receiverNotificationIOIsCurrent() -> Bool {
        guard terminalAdmission.allowsProducerMutation else {
            return false
        }
        guard let locationID else {
            return true
        }
        return Self.isCurrentSharedChannel(self, locationID: locationID)
    }

    private func restoreOwnedNotificationFlags(
        shouldContinue: @escaping () -> Bool,
        completion: @escaping () -> Void
    ) {
        DispatchQueue.global(qos: .utility).async { [self] in
            let restored = restoreOwnedNotificationFlagsSynchronously(
                shouldContinue: shouldContinue
            )
            if !restored {
                os_log(
                    "Failed to restore owned receiver notification flags: locationID=%{public}@",
                    log: LogitechHIDPPDeviceMetadataProvider.log,
                    type: .error,
                    locationID.map(String.init) ?? "(nil)"
                )
            }
            Self.deliverOnMainRunLoop(completion)
        }
    }

    @discardableResult
    private func restoreOwnedNotificationFlagsSynchronously(
        deadline: Date? = nil,
        shouldContinue: @escaping () -> Bool
    ) -> Bool {
        let ownership = receiverNotificationOwnership
        return ownership.store.restoreOwnedBits(
            for: ownership.target,
            read: { [self] in
                readNotificationFlags(deadline: deadline, until: shouldContinue)
            },
            write: { [self] value in
                writeNotificationFlags(value, deadline: deadline, until: shouldContinue)
            },
            shouldContinue: shouldContinue
        )
    }

    func discoverPointingDeviceDiscovery(
        baseName: String,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> LogitechHIDPPDeviceMetadataProvider
        .ReceiverPointingDeviceDiscovery {
        guard let locationID else {
            return .init(
                identities: [],
                connectionSnapshots: [:],
                liveReachableSlots: [],
                inventoryAvailable: false
            )
        }

        guard let discovery = discoverMatchCandidates(
            baseName: baseName,
            until: shouldContinue
        ) else {
            return .init(
                identities: [],
                connectionSnapshots: [:],
                liveReachableSlots: [],
                inventoryAvailable: false
            )
        }

        let slots = discovery.slots
        let connectionSnapshots = discovery.connectionSnapshots
        let liveReachableSlots = Set(slots.compactMap { slot in
            slot.hasLiveMetadata ? slot.slot : nil
        })

        let identities = slots.compactMap { slot -> ReceiverLogicalDeviceIdentity? in
            guard let kind = resolveReceiverPointingIdentityKind(
                snapshotRaw: connectionSnapshots[slot.slot]?.kind,
                pairingRaw: slot.kind
            ), kind.isPointingDevice else {
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
            liveReachableSlots: liveReachableSlots,
            expectedConnectedDeviceCount: discovery.expectedConnectedDeviceCount,
            inventoryAvailable: discovery.inventoryAvailable,
            observedSlotKinds: Dictionary(uniqueKeysWithValues: slots.map {
                ($0.slot, $0.kind)
            })
        )
    }

    func waitForConnectionSnapshots(
        timeout: TimeInterval,
        until shouldContinue: (() -> Bool)? = nil
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshotBatch {
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
            return .empty
        }

        var collector = LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshotCollector(
            expectedConnectedDeviceCount: nil
        )
        collector.record(slot: initialNotification.slot, snapshot: initialNotification.snapshot)
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

            collector.record(slot: notification.slot, snapshot: notification.snapshot)
        }

        return collector.batch
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

    func readNotificationFlags(
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> UInt32? {
        guard let response = hidpp10ShortRequest(
            subID: 0x81,
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverNotificationFlagsRegister,
            parameters: [0, 0, 0],
            deadline: deadline,
            until: shouldContinue
        ) else {
            return nil
        }

        return UInt32(response[4]) << 16 | UInt32(response[5]) << 8 | UInt32(response[6])
    }

    func writeNotificationFlags(
        _ value: UInt32,
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true },
        onCommitted: () -> Void = {}
    ) -> Bool {
        hidpp10ShortRequest(
            subID: 0x80,
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverNotificationFlagsRegister,
            parameters: [UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)],
            deadline: deadline,
            until: shouldContinue,
            onReportCommitted: onCommitted
        ) != nil
    }

    func performSynchronousOutputReportRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool
    ) -> Data? {
        performSynchronousOutputReportRequest(
            report,
            timeout: timeout,
            matching: matching
        ) { true }
    }

    func performSynchronousOutputReportRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        until shouldContinue: @escaping () -> Bool
    ) -> Data? {
        performSynchronousOutputReportRequest(
            report,
            timeout: timeout,
            matching: matching,
            until: shouldContinue
        ) {}
    }

    private func performSynchronousOutputReportRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        until shouldContinue: @escaping () -> Bool,
        onReportCommitted: () -> Void
    ) -> Data? {
        guard shouldContinue() else {
            return nil
        }
        let deadline = Date().addingTimeInterval(timeout)
        let remainingTimeout = {
            max(0, deadline.timeIntervalSinceNow)
        }

        if let strategy = currentRequestStrategy(), shouldContinue() {
            let remaining = remainingTimeout()
            guard remaining > 0 else {
                return nil
            }
            let response = performRequest(
                report,
                timeout: remaining,
                matching: matching,
                strategy: strategy,
                until: shouldContinue,
                onReportCommitted: onReportCommitted
            )
            if response != nil {
                recordRequestStrategySuccess(strategy)
            } else if shouldContinue() {
                recordRequestStrategyFailure(strategy)
            }
            return response
        }

        // Strategy detection should be quick. Giving every callback strategy the
        // full HID++ timeout can turn one failed request into several seconds.
        for strategy in RequestStrategy.allCases {
            let remaining = remainingTimeout()
            guard shouldContinue(), remaining > 0 else {
                return nil
            }

            guard let response = performRequest(
                report,
                timeout: min(remaining, 0.25),
                matching: matching,
                strategy: strategy,
                until: shouldContinue,
                onReportCommitted: onReportCommitted
            ) else {
                continue
            }

            recordRequestStrategySuccess(strategy)
            return response
        }

        clearCurrentRequestStrategy()
        return nil
    }

    func performSynchronousOutputReportRequestOnce(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool
    ) -> Data? {
        performSynchronousOutputReportRequestOnce(
            report,
            timeout: timeout,
            matching: matching
        ) { true }
    }

    func performSynchronousOutputReportRequestOnce(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        until shouldContinue: @escaping () -> Bool
    ) -> Data? {
        // A write (notably Adjustable DPI) must remain a single transaction.
        // Reuse a strategy established by a successful read request, but never
        // probe alternatives here: every probe would repeat the side effect.
        guard let strategy = currentRequestStrategy(), shouldContinue() else {
            return nil
        }

        let response = performRequest(
            report,
            timeout: timeout,
            matching: matching,
            strategy: strategy,
            until: shouldContinue
        )
        if response != nil {
            recordRequestStrategySuccess(strategy)
        } else if shouldContinue() {
            recordRequestStrategyFailure(strategy)
        }
        return response
    }

    private func performRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        strategy: RequestStrategy,
        until shouldContinue: @escaping () -> Bool,
        onReportCommitted: () -> Void = {}
    ) -> Data? {
        guard !report.isEmpty, shouldContinue() else {
            return nil
        }

        if let responseType = strategy.responseType {
            return performGetReportRequest(
                report,
                timeout: timeout,
                matching: matching,
                requestType: strategy.requestType,
                responseType: responseType,
                until: shouldContinue,
                onReportCommitted: onReportCommitted
            )
        }

        return performCallbackRequest(
            report,
            timeout: timeout,
            matching: matching,
            reportType: strategy.requestType,
            until: shouldContinue,
            onReportCommitted: onReportCommitted
        )
    }

    private func performCallbackRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        reportType: IOHIDReportType,
        until shouldContinue: @escaping () -> Bool,
        onReportCommitted: () -> Void
    ) -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        guard acquireRequestLock(until: deadline, while: shouldContinue) else {
            return nil
        }
        defer { requestLock.unlock() }

        guard shouldContinue() else {
            return nil
        }

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
        onReportCommitted()

        return settleCommittedPendingResponse(
            timeout: max(0, deadline.timeIntervalSinceNow),
            until: shouldContinue
        )
    }

    private func performGetReportRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        requestType: IOHIDReportType,
        responseType: IOHIDReportType,
        until shouldContinue: @escaping () -> Bool,
        onReportCommitted: () -> Void
    ) -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        guard acquireRequestLock(until: deadline, while: shouldContinue) else {
            return nil
        }
        defer { requestLock.unlock() }

        guard shouldContinue() else {
            return nil
        }

        clearPendingRequest()
        guard sendReport(report, type: requestType) == kIOReturnSuccess else {
            return nil
        }
        onReportCommitted()

        return settleCommittedGetReport(
            type: responseType,
            matching: matching,
            timeout: max(0, deadline.timeIntervalSinceNow),
            until: shouldContinue
        )
    }

    private func acquireRequestLock(
        until deadline: Date,
        while shouldContinue: () -> Bool
    ) -> Bool {
        while shouldContinue(), Date() < deadline {
            if requestLock.lock(before: min(deadline, Date().addingTimeInterval(0.05))) {
                return true
            }
        }

        return false
    }

    private func sendReport(_ report: Data, type: IOHIDReportType) -> IOReturn {
        report.withUnsafeBytes { rawBuffer -> IOReturn in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return kIOReturnBadArgument
            }

            return IOHIDDeviceSetReport(device, type, CFIndex(report[0]), baseAddress, report.count)
        }
    }

    private func getMatchingReport(
        type: IOHIDReportType,
        matching: @escaping (Data) -> Bool
    ) -> Data? {
        for candidate in candidateReportDescriptors() {
            guard let response = getReport(type: type, reportID: candidate.reportID, length: candidate.length),
                  matching(response) else {
                continue
            }

            return response
        }

        return nil
    }

    private func settleCommittedGetReport(
        type: IOHIDReportType,
        matching: @escaping (Data) -> Bool,
        timeout: TimeInterval,
        until shouldContinue: @escaping () -> Bool
    ) -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        // GetReport does not have a transaction-owned callback to wake this
        // poll. Keep the yield local so notifications from older transactions
        // cannot accumulate permits and create an I/O burst.
        let pollYield = DispatchSemaphore(value: 0)
        return HIDPPCommittedTransaction.settle(
            until: deadline,
            shouldDeliverResult: shouldContinue,
            isTransportValid: { self.isTransportActive },
            wait: { interval in
                _ = pollYield.wait(timeout: .now() + interval)
            },
            response: {
                self.getMatchingReport(type: type, matching: matching)
            }
        )
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

    private func recordRequestStrategySuccess(_ strategy: RequestStrategy) {
        strategyLock.lock()
        requestStrategy = strategy
        requestStrategyFailureCount = 0
        strategyLock.unlock()
    }

    private func recordRequestStrategyFailure(_ strategy: RequestStrategy) {
        strategyLock.lock()
        if requestStrategy == strategy {
            requestStrategyFailureCount += 1
            if requestStrategyFailureCount >= 2 {
                requestStrategy = nil
                requestStrategyFailureCount = 0
            }
        }
        strategyLock.unlock()
    }

    private func clearCurrentRequestStrategy() {
        strategyLock.lock()
        requestStrategy = nil
        requestStrategyFailureCount = 0
        strategyLock.unlock()
    }

    private func waitForInputReport(
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        until shouldContinue: (() -> Bool)? = nil
    ) -> Data? {
        notificationBuffer.wait(
            timeout: timeout,
            matching: { matching(Data($0)) },
            until: shouldContinue
        )
        .map { Data($0) }
    }

    private func settleCommittedPendingResponse(
        timeout: TimeInterval,
        until shouldContinue: @escaping () -> Bool
    ) -> Data? {
        pendingLock.lock()
        let semaphore = pendingSemaphore
        pendingLock.unlock()
        guard let semaphore else {
            return nil
        }

        defer { clearPendingRequest() }

        let deadline = Date().addingTimeInterval(timeout)
        return HIDPPCommittedTransaction.settle(
            until: deadline,
            shouldDeliverResult: shouldContinue,
            isTransportValid: { self.isTransportActive },
            wait: { interval in
                _ = semaphore.wait(timeout: .now() + interval)
            },
            response: { [weak self] in
                guard let self else {
                    return nil
                }
                self.pendingLock.lock()
                let response = self.pendingResponse
                self.pendingLock.unlock()
                return response
            }
        )
    }

    private func waitForResponse(
        timeout: TimeInterval,
        until shouldContinue: (() -> Bool)?,
        semaphore: DispatchSemaphore,
        response: () -> Data?
    ) -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let shouldContinue, !shouldContinue() {
                return nil
            }

            if let response = response() {
                return response
            }

            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                break
            }

            _ = semaphore.wait(timeout: .now() + min(remaining, 0.05))
        }

        return response()
    }

    private func handleInputReport(_ report: Data) {
        pendingLock.lock()
        var semaphores = [DispatchSemaphore]()
        var wasClaimedByTransaction = false

        if let reportMatcher = pendingMatcher, reportMatcher(report) {
            pendingResponse = report
            pendingMatcher = nil
            wasClaimedByTransaction = true
            if let pendingSemaphore {
                semaphores.append(pendingSemaphore)
            }
        }

        pendingLock.unlock()
        semaphores.forEach { $0.signal() }
        if !wasClaimedByTransaction {
            notificationBuffer.appendIfUnsolicited(report)
        }
    }

    private var isTransportActive: Bool {
        lifecycleLock.withLock { isActivated }
    }

    private func clearPendingRequest() {
        pendingLock.lock()
        pendingMatcher = nil
        pendingResponse = nil
        pendingSemaphore = nil
        pendingLock.unlock()
    }

    func wake() {
        pendingLock.lock()
        let semaphores = [pendingSemaphore].compactMap(\.self)
        pendingLock.unlock()
        semaphores.forEach { $0.signal() }
        notificationBuffer.wake()
    }

    private func readConnectionState(
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> [UInt8]? {
        hidpp10ShortRequest(
            subID: 0x81,
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverConnectionStateRegister,
            parameters: [0, 0, 0],
            deadline: deadline,
            until: shouldContinue
        )
    }

    private func triggerConnectionNotifications(
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> Bool {
        hidpp10ShortRequest(
            subID: 0x80,
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverConnectionStateRegister,
            parameters: [0x02, 0x00, 0x00],
            deadline: deadline,
            until: shouldContinue
        ) != nil
    }

    private func hidpp10ShortRequest(
        subID: UInt8,
        register: UInt8,
        parameters: [UInt8],
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true },
        onReportCommitted: () -> Void = {}
    ) -> [UInt8]? {
        let requestShouldContinue = {
            shouldContinue() && deadline.map { Date() < $0 } != false
        }
        let timeout = min(
            LogitechHIDPPDeviceMetadataProvider.Constants.timeout,
            deadline.map { max(0, $0.timeIntervalSinceNow) }
                ?? LogitechHIDPPDeviceMetadataProvider.Constants.timeout
        )
        guard timeout > 0, requestShouldContinue() else {
            return nil
        }
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
            timeout: timeout,
            matching: { report in
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
            },
            until: requestShouldContinue,
            onReportCommitted: onReportCommitted
        )

        guard let response else {
            return nil
        }

        let responseBytes = Array(response)
        return responseBytes[2] == 0x8F ? nil : responseBytes
    }

    private func hidpp10LongRequest(
        register: UInt8,
        subregister: UInt8,
        deadline: Date? = nil,
        until shouldContinue: @escaping () -> Bool = { true }
    ) -> [UInt8]? {
        let requestShouldContinue = {
            shouldContinue() && deadline.map { Date() < $0 } != false
        }
        let timeout = min(
            LogitechHIDPPDeviceMetadataProvider.Constants.timeout,
            deadline.map { max(0, $0.timeIntervalSinceNow) }
                ?? LogitechHIDPPDeviceMetadataProvider.Constants.timeout
        )
        guard timeout > 0, requestShouldContinue() else {
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength)
        bytes[0] = LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID
        bytes[1] = LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex
        bytes[2] = 0x83
        bytes[3] = register
        bytes[4] = subregister

        let request = Data(bytes)

        let response = performSynchronousOutputReportRequest(
            request,
            timeout: timeout,
            matching: { report in
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
            },
            until: requestShouldContinue
        )

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

    static func parseReceiverSerialNumber(_ response: [UInt8]) -> String? {
        guard response.count >= 9 else {
            return nil
        }

        // HID++ 1.0 extended pairing info stores serial r1...r4 directly
        // after the subregister byte: report indices 5...8.
        return LogitechStableSerial.encode(response[5 ... 8])
    }

    private static func getProperty<T>(_ key: String, from device: IOHIDDevice) -> T? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else {
            return nil
        }

        return value as? T
    }
}

final class LogitechReprogrammableControlsMonitor {
    private static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "LogitechReprogrammableControls")

    private enum Constants {
        static let notificationTimeout: TimeInterval = 0.25
        static let initializationRetryInitialTimeout: TimeInterval = 2
        static let initializationRetryMaxTimeout: TimeInterval = 60
    }

    private struct ControlInfo {
        let controlID: UInt16
        let taskID: UInt16
        let position: UInt8
        let group: UInt8
        let groupMask: UInt8
        let flags: LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.ControlFlags
    }

    struct ReportingInfo: Equatable {
        let flags: LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.ReportingFlags
        let mappedControlID: UInt16

        init(
            flags: LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.ReportingFlags,
            mappedControlID: UInt16
        ) {
            self.flags = flags
            self.mappedControlID = mappedControlID
        }

        init(baseline: LogitechHardwareBaselineStore.ControlsReportingBaseline) {
            flags = .init(rawValue: baseline.flagsRawValue)
            mappedControlID = baseline.mappedControlID
        }

        var baseline: LogitechHardwareBaselineStore.ControlsReportingBaseline {
            .init(flagsRawValue: flags.rawValue, mappedControlID: mappedControlID)
        }
    }

    private struct MonitorTarget {
        let slot: UInt8
        let identity: ReceiverLogicalDeviceIdentity?
        let allowsIdentityFallback: Bool
        let notificationDeviceIndices: Set<UInt8>
        let transport: HIDPPTransport
        let featureIndex: UInt8
        let controls: [ControlInfo]
        let notificationEndpoint: HIDPPNotificationHandling
    }

    struct EphemeralControlsTargetKey: Hashable {
        let locationID: Int
        let slot: UInt8
        let kind: ReceiverLogicalDeviceKind?
        let productID: Int?
    }

    /// Keeps in-memory baselines for direct/legacy targets that do not have a
    /// stable hardware identity. A receiver route can be replaced while its
    /// previous worker is unwinding, so every claim owns its target's current
    /// entry. Invalidating the store removes those entries, making a stale
    /// worker's final write a no-op instead of transferring its baseline to a
    /// replacement target.
    final class UnkeyedControlsRestoreStore {
        final class EntryOwnership {}

        struct Claim {
            let ownership: EntryOwnership
            let reporting: [UInt16: ReportingInfo]
        }

        private struct Entry {
            let ownership: EntryOwnership
            var reporting: [UInt16: ReportingInfo]
        }

        private let lock = NSLock()
        private var entries = [EphemeralControlsTargetKey: Entry]()

        func claim(for key: EphemeralControlsTargetKey) -> Claim {
            lock.withLock {
                if let entry = entries[key] {
                    return Claim(ownership: entry.ownership, reporting: entry.reporting)
                }

                let entry = Entry(ownership: EntryOwnership(), reporting: [:])
                entries[key] = entry
                return Claim(ownership: entry.ownership, reporting: entry.reporting)
            }
        }

        @discardableResult
        func replace(
            _ reporting: [UInt16: ReportingInfo],
            for key: EphemeralControlsTargetKey,
            expectedOwnership: EntryOwnership
        ) -> Bool {
            lock.withLock {
                guard let entry = entries[key],
                      entry.ownership === expectedOwnership
                else {
                    return false
                }

                // Keep the empty entry as an ownership reservation for the
                // active worker. A later failed restore must still be able to
                // publish its baseline through this same claim.
                entries[key]?.reporting = reporting
                return true
            }
        }

        func invalidateAll() {
            lock.withLock {
                entries.removeAll()
            }
        }

        var hasPending: Bool {
            lock.withLock { entries.values.contains { !$0.reporting.isEmpty } }
        }
    }

    private let device: Device
    private let provider = LogitechHIDPPDeviceMetadataProvider()
    private let state = LogitechReprogrammableControlsMonitorState()
    private var subscriptions = Set<AnyCancellable>()
    private let unkeyedRestoreStore = UnkeyedControlsRestoreStore()

    init(device: Device) {
        self.device = device
    }

    static func supports(device: Device) -> Bool {
        supports(
            vendorID: device.vendorID,
            productID: device.productID,
            transport: device.pointerDevice.transport
        )
    }

    static func supports(vendorID: Int?, productID: Int?, transport: String?) -> Bool {
        guard vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID else {
            return false
        }

        switch transport {
        case PointerDeviceTransportName.bluetoothLowEnergy:
            return true
        case PointerDeviceTransportName.usb:
            return LogitechHIDPPDeviceMetadataProvider.supportsReprogrammableControlsMonitoring(
                vendorID: vendorID,
                productID: productID,
                transport: transport
            )
        default:
            return false
        }
    }

    static func isNeeded(configuration: Configuration = ConfigurationState.shared.configuration) -> Bool {
        SettingsState.shared.recording || configuration.schemes.contains(where: containsLogitechControl)
    }

    static func isNeeded(for device: Device, configuration: Configuration = ConfigurationState.shared.configuration)
        -> Bool {
        if SettingsState.shared.recording {
            return true
        }

        guard device.pointerDevice.transport == PointerDeviceTransportName.bluetoothLowEnergy else {
            return isNeeded(configuration: configuration)
        }

        return isNeeded(
            configuration: configuration,
            identity: directIdentity(for: device),
            allowsIdentityFallback: true
        )
    }

    static func isNeeded(
        configuration: Configuration,
        identity: ReceiverLogicalDeviceIdentity,
        allowsIdentityFallback: Bool = false
    ) -> Bool {
        configuration.schemes.contains { scheme in
            logitechControls(in: scheme).contains {
                matches(logiButton: $0, identity: identity, allowsIdentityFallback: allowsIdentityFallback)
            }
        }
    }

    private static func containsLogitechControl(in scheme: Scheme) -> Bool {
        !logitechControls(in: scheme).isEmpty
    }

    private static func logitechControls(in scheme: Scheme) -> [LogitechControlIdentity] {
        let buttons = scheme.buttons
        let mappedControls = (buttons.mappings ?? []).flatMap { mapping in
            if let trigger = mapping.trigger {
                return trigger.statefulButtons.compactMap(\.logitechControl)
            }
            return [mapping.button?.logitechControl].compactMap(\.self)
        }
        let autoScrollControl: LogitechControlIdentity? = {
            guard buttons.$autoScroll?.enabled ?? false else {
                return nil
            }

            return buttons.$autoScroll?.trigger?.button?.logitechControl
        }()
        let gestureControl: LogitechControlIdentity? = {
            guard buttons.$gesture?.enabled ?? false else {
                return nil
            }

            return buttons.$gesture?.trigger?.button?.logitechControl
        }()

        return mappedControls + [autoScrollControl, gestureControl].compactMap(\.self)
    }

    private static func directIdentity(for device: Device) -> ReceiverLogicalDeviceIdentity {
        ReceiverLogicalDeviceIdentity(
            receiverLocationID: device.pointerDevice.locationID ?? 0,
            slot: 0,
            kind: device.category == .trackpad ? .touchpad : .mouse,
            name: device.productName ?? device.name,
            serialNumber: device.serialNumber,
            productID: device.productID,
            batteryLevel: device.batteryLevel
        )
    }

    func enable() {
        state.enable(makeWorkerThread: makeWorkerThread)
        observeConfigurationChangesIfNeeded()
    }

    func disable() {
        state.disable()
        releaseButtonIfNeeded()
        subscriptions.removeAll()
    }

    /// Stops monitoring for system sleep and best-effort restores reporting
    /// while the current target is still reachable. A failed restore keeps its
    /// store claim for the terminal restore path instead of consuming it.
    func stopForSleep(
        authorization: CancellationToken,
        deadline: Date,
        completion: @escaping () -> Void
    ) {
        state.cancelResumeAfterSleep()
        restorePendingReporting(
            authorization: authorization,
            deadline: deadline,
            completion: completion
        )
        releaseButtonIfNeeded()
        subscriptions.removeAll()
    }

    /// Reconciles ordinary monitoring after the sleep restore-only worker has
    /// released its completion barrier. Repeated wake requests coalesce in the
    /// state object, and terminal teardown cancels the pending action.
    func resumeAfterSleep(_ reconcileDemand: @escaping () -> Void) {
        state.resumeAfterSleep(reconcileDemand)
    }

    /// Drops monitor ownership without attempting HID++ reporting cleanup.
    /// This is for final device teardown, where the transport can no longer be
    /// assumed to be valid and no completion barrier should retain the device.
    func abandon() {
        state.abandon()
        releaseButtonIfNeeded()
        subscriptions.removeAll()
    }

    /// Restores any store-backed reporting baseline before a terminal
    /// teardown. This is deliberately independent from configuration demand:
    /// after sleep a monitor may be stopped even though a baseline still needs
    /// to be written back.
    func restorePendingForTeardown(
        authorization: CancellationToken,
        deadline: Date,
        completion: @escaping () -> Void
    ) {
        state.cancelResumeAfterSleep()
        restorePendingReporting(
            authorization: authorization,
            deadline: deadline,
            completion: completion
        )
    }

    private func restorePendingReporting(
        authorization: CancellationToken,
        deadline: Date,
        completion: @escaping () -> Void
    ) {
        state.restorePendingForTeardown(
            needsRestoreWorkerForCurrentTarget(),
            authorization: authorization,
            deadline: deadline,
            makeWorkerThread: makeWorkerThread,
            completion: completion
        )
    }

    /// A logical receiver target changed. The retiring worker must never write
    /// its baseline through a receiver slot that may now address a replacement.
    /// Keep demand observation alive so a fresh worker can bind the new target.
    func invalidateTarget() {
        state.invalidateTarget {
            unkeyedRestoreStore.invalidateAll()
        }
        releaseButtonIfNeeded()
    }

    func needsRestoreWorkerForCurrentTarget() -> Bool {
        let keyedTarget = device.logitechHardwareTargetKey(
            receiverSlot: device.logitechReceiverRouteSnapshot?.slot
        )
        let hasKeyedPending: Bool
        if let store = device.logitechHardwareBaselineStore,
           let keyedTarget {
            hasKeyedPending = !store.pendingControlsBaselines(for: keyedTarget).isEmpty
        } else {
            hasKeyedPending = false
        }
        return Self.needsRestoreWorker(
            hasKeyedPending: hasKeyedPending,
            hasUnkeyedPending: unkeyedRestoreStore.hasPending,
            hasActiveUnkeyedTarget: state.hasActiveUnkeyedTarget
        )
    }

    static func needsRestoreWorker(
        hasKeyedPending: Bool,
        hasUnkeyedPending: Bool,
        hasActiveUnkeyedTarget: Bool
    ) -> Bool {
        hasKeyedPending || hasUnkeyedPending || hasActiveUnkeyedTarget
    }

    private func workerMain() {
        defer {
            let restartIfEnabled = Thread.current.isCancelled
            releaseButtonIfNeeded()
            state.workerDidStop(
                restartIfEnabled: restartIfEnabled,
                makeWorkerThread: makeWorkerThread
            )
        }

        var initializationBackoff = ExponentialBackoff(
            initialDelay: Constants.initializationRetryInitialTimeout,
            maximumDelay: Constants.initializationRetryMaxTimeout
        )

        targetLoop: while shouldContinueRunning() {
            guard let monitorTarget = resolveMonitorTarget() else {
                let retryTimeout = initializationBackoff.nextDelay()
                finishVirtualButtonRecordingPreparationIfNeeded(
                    sessionID: readMainThreadSnapshotFromWorker {
                        SettingsState.shared.buttonMappingRecordingSessionID
                    }
                )
                os_log(
                    "Retry Logitech controls monitor initialization because device is not ready: retryTimeout=%{public}.1f device=%{public}@",
                    log: Self.log,
                    type: .info,
                    retryTimeout,
                    String(describing: device)
                )

                let waitResult = state.waitForReconfigurationOrRetryTimeout(timeout: retryTimeout)
                guard waitResult.shouldContinue else {
                    return
                }

                if !waitResult.timedOut {
                    initializationBackoff.reset()
                }
                continue
            }

            initializationBackoff.reset()

            let locationID = device.pointerDevice.locationID ?? 0
            let slot = monitorTarget.slot
            let transport = monitorTarget.transport
            let featureIndex = monitorTarget.featureIndex
            let allControls = monitorTarget.controls
            let targetIdentity = monitorTarget.identity
            let targetName = targetIdentity?.name ?? device.productName ?? device.name
            let baselineStore = device.logitechHardwareBaselineStore
            let baselineTarget = device.logitechHardwareTargetKey(receiverSlot: transport.receiverSlot)
            let unkeyedTarget = EphemeralControlsTargetKey(
                locationID: locationID,
                slot: monitorTarget.slot,
                kind: monitorTarget.identity?.kind,
                productID: monitorTarget.identity?.productID
            )
            let unkeyedClaim = unkeyedRestoreStore.claim(for: unkeyedTarget)
            let unkeyedOwnership = unkeyedClaim.ownership
            var pendingUnkeyedReportingRestoreByControlID = unkeyedClaim.reporting
            state.setStoreBackedActiveTarget(baselineTarget != nil)

            state.setActiveNotificationEndpoint(monitorTarget.notificationEndpoint)
            monitorTarget.notificationEndpoint.enableNotifications { [state] in
                state.shouldContinueRunning
            }
            logAvailableControls(transport: transport, featureIndex: featureIndex, slot: slot, locationID: locationID)

            while shouldContinueRunning() {
                let controlSnapshot = monitorControlSnapshot(
                    availableControls: allControls,
                    identity: targetIdentity,
                    allowsIdentityFallback: monitorTarget.allowsIdentityFallback
                )
                let desiredControlIDs = controlSnapshot.desiredControlIDs
                let isRecording = controlSnapshot.isRecording
                let recordingSessionID = controlSnapshot.recordingSessionID
                let monitoredControls = state.isRestoringPendingForTeardown
                    ? []
                    : isRecording
                    ? allControls
                    : allControls.filter { desiredControlIDs.contains($0.controlID) }
                let monitoredControlIDs = Set(monitoredControls.map(\.controlID))
                let reservedVirtualButtonNumber =
                    LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.reservedVirtualButtonNumber

                if baselineTarget == nil, shouldAllowTeardownIO() {
                    let retired = pendingUnkeyedReportingRestoreByControlID.filter {
                        !monitoredControlIDs.contains($0.key)
                    }
                    let failed = restoreReportingState(
                        retired,
                        using: transport,
                        featureIndex: featureIndex,
                        locationID: locationID,
                        slot: slot,
                        reason: "restore unkeyed no-longer-monitored reporting"
                    )
                    for controlID in Set(retired.keys).subtracting(failed.keys) {
                        pendingUnkeyedReportingRestoreByControlID.removeValue(forKey: controlID)
                    }
                    guard unkeyedRestoreStore.replace(
                        pendingUnkeyedReportingRestoreByControlID,
                        for: unkeyedTarget,
                        expectedOwnership: unkeyedOwnership
                    ) else {
                        continue targetLoop
                    }
                }

                restoreStoredReportingNotIn(
                    monitoredControlIDs,
                    store: baselineStore,
                    target: baselineTarget,
                    using: transport,
                    featureIndex: featureIndex,
                    locationID: locationID,
                    slot: slot
                )

                if monitoredControls.isEmpty {
                    if !hasPendingBaseline(store: baselineStore, target: baselineTarget),
                       pendingUnkeyedReportingRestoreByControlID.isEmpty {
                        return
                    }
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

                    let waitResult = hasPendingBaseline(store: baselineStore, target: baselineTarget)
                        || !pendingUnkeyedReportingRestoreByControlID.isEmpty
                        ? state.waitForReconfigurationOrRetryTimeout(timeout: Constants.notificationTimeout)
                        : state.waitForReconfigurationOrStop(timeout: Constants.notificationTimeout)
                    guard waitResult.shouldContinue else {
                        retryStoredReportingRestoration(
                            store: baselineStore,
                            target: baselineTarget,
                            using: transport,
                            featureIndex: featureIndex,
                            locationID: locationID,
                            slot: slot
                        )
                        if baselineTarget == nil {
                            retryUnkeyedReportingRestoration(
                                &pendingUnkeyedReportingRestoreByControlID,
                                store: unkeyedRestoreStore,
                                target: unkeyedTarget,
                                expectedOwnership: unkeyedOwnership,
                                using: transport,
                                featureIndex: featureIndex,
                                locationID: locationID,
                                slot: slot
                            )
                        }
                        return
                    }

                    if waitResult.forced {
                        continue targetLoop
                    }

                    continue
                }

                var capturedReporting = captureOriginalReporting(
                    for: monitoredControls,
                    store: baselineStore,
                    target: baselineTarget,
                    using: transport,
                    featureIndex: featureIndex
                )
                if baselineTarget == nil {
                    for control in monitoredControls {
                        if let pending = pendingUnkeyedReportingRestoreByControlID[control.controlID] {
                            capturedReporting.reporting[control.controlID] = pending
                        }
                    }
                }
                let originalReportingByControlID = capturedReporting.reporting
                // Never divert a control whose original reporting could not be
                // read. Without that snapshot we could not safely restore it
                // during disable or target teardown.
                let controlsWithKnownOriginalReporting = monitoredControls.filter {
                    originalReportingByControlID[$0.controlID] != nil
                }
                monitorTarget.notificationEndpoint.discardHIDPPNotifications { response in
                    Self.isDivertedButtonsNotification(
                        response,
                        featureIndex: featureIndex,
                        deviceIndices: monitorTarget.notificationDeviceIndices
                    )
                }
                let activeControlIDs = controlsWithKnownOriginalReporting.compactMap { control -> UInt16? in
                    guard setDivertedWithRetry(
                        true,
                        for: control.controlID,
                        using: transport,
                        featureIndex: featureIndex
                    )
                    else {
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
                    let failedRestore = shouldAllowTeardownIO()
                        ? restoreReportingState(
                            originalReportingByControlID,
                            using: transport,
                            featureIndex: featureIndex,
                            locationID: locationID,
                            slot: slot,
                            reason: "rollback failed control diversion"
                        )
                        : originalReportingByControlID
                    consumeRestoredBaselines(
                        capturedReporting.claims,
                        excluding: Set(failedRestore.keys),
                        store: baselineStore
                    )
                    if baselineTarget == nil {
                        for controlID in Set(originalReportingByControlID.keys).subtracting(failedRestore.keys) {
                            pendingUnkeyedReportingRestoreByControlID.removeValue(forKey: controlID)
                        }
                        pendingUnkeyedReportingRestoreByControlID.merge(failedRestore) { _, new in new }
                        guard unkeyedRestoreStore.replace(
                            pendingUnkeyedReportingRestoreByControlID,
                            for: unkeyedTarget,
                            expectedOwnership: unkeyedOwnership
                        ) else {
                            continue targetLoop
                        }
                    }
                    finishVirtualButtonRecordingPreparationIfNeeded(sessionID: recordingSessionID)
                    os_log(
                        "Failed to enable any Logitech control diversion: locationID=%{public}d slot=%{public}u device=%{public}@",
                        log: Self.log,
                        type: .error,
                        locationID,
                        slot,
                        targetName
                    )

                    let waitResult = hasPendingBaseline(store: baselineStore, target: baselineTarget)
                        || !pendingUnkeyedReportingRestoreByControlID.isEmpty
                        ? state.waitForReconfigurationOrRetryTimeout(timeout: Constants.notificationTimeout)
                        : state.waitForReconfigurationOrStop(timeout: Constants.notificationTimeout)
                    guard waitResult.shouldContinue else {
                        retryStoredReportingRestoration(
                            store: baselineStore,
                            target: baselineTarget,
                            using: transport,
                            featureIndex: featureIndex,
                            locationID: locationID,
                            slot: slot
                        )
                        if baselineTarget == nil {
                            retryUnkeyedReportingRestoration(
                                &pendingUnkeyedReportingRestoreByControlID,
                                store: unkeyedRestoreStore,
                                target: unkeyedTarget,
                                expectedOwnership: unkeyedOwnership,
                                using: transport,
                                featureIndex: featureIndex,
                                locationID: locationID,
                                slot: slot
                            )
                        }
                        return
                    }

                    if waitResult.forced {
                        continue targetLoop
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
                    cancelPressedControlInteractions(
                        pressedControls,
                        productID: targetIdentity?.productID,
                        serialNumber: targetIdentity?.serialNumber,
                        allowsIdentityFallback: monitorTarget.allowsIdentityFallback,
                        isRecording: isRecording,
                        recordingSessionID: recordingSessionID
                    )
                    releaseButtonIfNeeded()

                    var failedRestoreByControlID = shouldAllowTeardownIO()
                        ? restoreReportingState(
                            originalReportingByControlID,
                            using: transport,
                            featureIndex: featureIndex,
                            locationID: locationID,
                            slot: slot,
                            reason: "restore original reporting"
                        )
                        : originalReportingByControlID
                    if !shouldContinueRunning(), shouldAllowTeardownIO(), !failedRestoreByControlID.isEmpty {
                        _ = LogitechHardwareRestoreRetry.perform(
                            operation: {
                                failedRestoreByControlID = self.restoreReportingState(
                                    failedRestoreByControlID,
                                    using: transport,
                                    featureIndex: featureIndex,
                                    locationID: locationID,
                                    slot: slot,
                                    reason: "retry terminal reporting restore"
                                )
                                return failedRestoreByControlID.isEmpty
                            },
                            wait: Thread.sleep(forTimeInterval:)
                        )
                    }
                    consumeRestoredBaselines(
                        capturedReporting.claims,
                        excluding: Set(failedRestoreByControlID.keys),
                        store: baselineStore
                    )
                    if baselineTarget == nil {
                        for controlID in Set(originalReportingByControlID.keys)
                            .subtracting(failedRestoreByControlID.keys) {
                            pendingUnkeyedReportingRestoreByControlID.removeValue(forKey: controlID)
                        }
                        pendingUnkeyedReportingRestoreByControlID.merge(failedRestoreByControlID) { _, new in new }
                        retryUnkeyedReportingRestoration(
                            &pendingUnkeyedReportingRestoreByControlID,
                            store: unkeyedRestoreStore,
                            target: unkeyedTarget,
                            expectedOwnership: unkeyedOwnership,
                            using: transport,
                            featureIndex: featureIndex,
                            locationID: locationID,
                            slot: slot
                        )
                    }
                    if !shouldContinueRunning(), shouldAllowTeardownIO() {
                        retryStoredReportingRestoration(
                            store: baselineStore,
                            target: baselineTarget,
                            using: transport,
                            featureIndex: featureIndex,
                            locationID: locationID,
                            slot: slot
                        )
                    }
                }

                while shouldContinueRunning() {
                    let reconfigResult = state.consumeReconfigurationRequest(
                        deferringWhileControlsArePressed: !pressedControls.isEmpty
                    )
                    if reconfigResult.needed {
                        if reconfigResult.forced {
                            os_log(
                                "Restart Logitech control monitor (forced, e.g. device reconnect): locationID=%{public}d slot=%{public}u device=%{public}@",
                                log: Self.log,
                                type: .info,
                                locationID,
                                slot,
                                targetName
                            )
                            continue targetLoop
                        }

                        let newControlSnapshot = monitorControlSnapshot(
                            availableControls: allControls,
                            identity: targetIdentity,
                            allowsIdentityFallback: monitorTarget.allowsIdentityFallback
                        )

                        if newControlSnapshot.desiredControlIDs != desiredControlIDs
                            || newControlSnapshot.isRecording != isRecording
                            || newControlSnapshot.recordingSessionID != recordingSessionID {
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
                    }

                    guard let report = monitorTarget.notificationEndpoint.waitForHIDPPNotification(
                        timeout: Constants.notificationTimeout,
                        matching: { response in
                            Self.isDivertedButtonsNotification(
                                response,
                                featureIndex: featureIndex,
                                deviceIndices: monitorTarget.notificationDeviceIndices
                            )
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

                        notifyDeviceActive(reason: "Received Logitech reprogrammable control event")

                        let modifierFlags = ModifierState.shared.currentFlags
                        let controlIdentity = LogitechControlIdentity(
                            controlID: Int(controlID),
                            productID: targetIdentity?.productID,
                            serialNumber: targetIdentity?.serialNumber
                        )

                        if isRecording {
                            if let recordingSessionID {
                                DispatchQueue.main.async {
                                    guard SettingsState.shared
                                        .isCurrentButtonMappingRecordingSession(recordingSessionID) else {
                                        return
                                    }

                                    SettingsState.shared.recordedButtonMappingEvent = .init(
                                        recordingSessionID: recordingSessionID,
                                        button: .logitechControl(controlIdentity),
                                        scroll: nil,
                                        modifierFlags: modifierFlags,
                                        isPressed: isPressed
                                    )
                                }
                            }
                            continue
                        }

                        let eventContext = eventContextSnapshot()

                        let logitechContext = LogitechEventContext(
                            device: device,
                            pid: eventContext.pid,
                            display: eventContext.display,
                            mouseLocation: eventContext.mouseLocation,
                            controlIdentity: controlIdentity,
                            allowsIdentityFallback: monitorTarget.allowsIdentityFallback,
                            isPressed: isPressed,
                            modifierFlags: modifierFlags
                        )

                        let handlingResult = EventThread.shared.performAndWait {
                            EventTransformerManager.shared.handleLogitechControlEvent(logitechContext)
                        } ?? .notHandled

                        let fallbackAction = state.syntheticFallbackAction(
                            for: controlIdentity,
                            isPressed: isPressed,
                            handlingResult: handlingResult
                        )

                        guard fallbackAction != .suppress else {
                            continue
                        }

                        os_log(
                            "Posting Logitech synthetic fallback: locationID=%{public}d slot=%{public}u device=%{public}@ cid=0x%{public}04X action=%{public}@ identityFallback=%{public}@",
                            log: Self.log,
                            type: .info,
                            locationID,
                            slot,
                            targetName,
                            controlID,
                            String(describing: fallbackAction),
                            monitorTarget.allowsIdentityFallback ? "true" : "false"
                        )

                        switch fallbackAction {
                        case .suppress:
                            break
                        case .postCurrentEvent:
                            postSyntheticButton(
                                button: reservedVirtualButtonNumber,
                                down: isPressed
                            )
                        case .postClick:
                            postSyntheticClick(button: reservedVirtualButtonNumber)
                        }
                    }
                }
            }
        }
    }

    private func monitorControlSnapshot(
        availableControls: [ControlInfo],
        identity: ReceiverLogicalDeviceIdentity?,
        allowsIdentityFallback: Bool
    ) -> (desiredControlIDs: Set<UInt16>, isRecording: Bool, recordingSessionID: UUID?) {
        readMainThreadSnapshotFromWorker {
            let isRecording = SettingsState.shared.recording
            let recordingSessionID = SettingsState.shared.buttonMappingRecordingSessionID
            let mouseLocation = CGEvent(source: nil)?.location ?? .zero
            let pid = mouseLocation.topmostWindowOwnerPid
                ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
            let scheme = ConfigurationState.shared.configuration.matchScheme(
                withDevice: device,
                withPid: pid,
                withDisplay: ScreenManager.shared.currentScreenNameSnapshot
            )
            return (
                desiredControlIDs: desiredDivertedControlIDs(
                    availableControls: availableControls,
                    identity: identity,
                    allowsIdentityFallback: allowsIdentityFallback,
                    isRecording: isRecording,
                    scheme: scheme
                ),
                isRecording: isRecording,
                recordingSessionID: recordingSessionID
            )
        }
    }

    private func eventContextSnapshot() -> (mouseLocation: CGPoint, pid: pid_t?, display: String?) {
        readMainThreadSnapshotFromWorker {
            let mouseLocation = CGEvent(source: nil)?.location ?? .zero
            let pid = mouseLocation.topmostWindowOwnerPid
                ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
            return (mouseLocation, pid, ScreenManager.shared.currentScreenNameSnapshot)
        }
    }

    private func readMainThreadSnapshotFromWorker<T>(_ body: () -> T) -> T {
        DispatchQueue.main.sync(execute: body)
    }

    private func notifyDeviceActive(reason: String) {
        DispatchQueue.main.async { [weak self] in
            self?.device.markActive(reason: reason)
        }
    }

    private func makeWorkerThread() -> Thread {
        let thread = Thread { [weak self] in
            self?.workerMain()
        }
        thread.name = "linearmouse.logitech-controls.\(device.id)"
        return thread
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

    private func findMonitoredControls(using transport: HIDPPTransport, featureIndex: UInt8) -> [ControlInfo] {
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

        if let route = device.logitechReceiverRouteSnapshot {
            return buildMonitorTarget(
                slot: route.slot,
                identity: route.identity,
                using: receiverChannel
            )
        }

        guard let discovery = device.logitechReceiverDiscoverySnapshot,
              !discovery.identities.isEmpty
        else {
            return nil
        }

        let targets = discovery.identities.compactMap { identity in
            buildMonitorTarget(
                slot: identity.slot,
                identity: identity,
                using: receiverChannel
            )
        }
        guard targets.count == 1 else {
            return nil
        }

        return targets[0]
    }

    private func buildDirectMonitorTarget() -> MonitorTarget? {
        guard let transport = HIDPPTransport(
            device: device.pointerDevice,
            deviceIndex: nil,
            shouldContinue: { [weak self] in self?.shouldAllowTeardownIO() == true }
        ),
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
            allowsIdentityFallback: true,
            notificationDeviceIndices: LogitechHIDPPDeviceMetadataProvider.Constants.directReplyIndices,
            transport: transport,
            featureIndex: featureIndex,
            controls: controls,
            notificationEndpoint: directNotificationEndpoint()
        )
    }

    private func directNotificationEndpoint() -> HIDPPNotificationEndpoint {
        let endpoint = HIDPPNotificationEndpoint()
        let reportObservationToken = device.pointerDevice.observeReport { _, report in
            endpoint.handleInputReport(report)
        }

        state.setDirectDeviceReportObservationToken(reportObservationToken)?.cancel()

        return endpoint
    }

    private func buildMonitorTarget(
        slot: UInt8,
        identity: ReceiverLogicalDeviceIdentity?,
        using receiverChannel: LogitechReceiverChannel
    ) -> MonitorTarget? {
        guard let transport = HIDPPTransport(
            device: receiverChannel,
            deviceIndex: slot,
            shouldContinue: { [weak self] in self?.shouldAllowTeardownIO() == true }
        ),
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
            allowsIdentityFallback: false,
            notificationDeviceIndices: Set([slot]),
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
            .$buttonMappingRecordingSession
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

    func requestReconfiguration() {
        state.requestReconfiguration()
    }

    func requestForcedReconfiguration() {
        state.requestReconfiguration(forced: true)
    }

    private func desiredDivertedControlIDs(
        availableControls: [ControlInfo],
        identity: ReceiverLogicalDeviceIdentity?,
        allowsIdentityFallback: Bool,
        isRecording: Bool,
        scheme: Scheme
    ) -> Set<UInt16> {
        if isRecording {
            return Set(availableControls.map(\.controlID))
        }

        let directMappings: [UInt16] = (scheme.buttons.mappings ?? []).flatMap { mapping in
            let mappedControls: [LogitechControlIdentity]
            if let trigger = mapping.trigger {
                mappedControls = trigger.statefulButtons.compactMap(\.logitechControl)
            } else {
                mappedControls = [mapping.button?.logitechControl].compactMap(\.self)
            }

            return mappedControls.compactMap { logiButton -> UInt16? in
                guard Self.matches(
                    logiButton: logiButton,
                    identity: identity,
                    allowsIdentityFallback: allowsIdentityFallback
                ) else {
                    return nil
                }
                return logiButton.controlIDValue
            }
        }

        let autoScrollControlID: UInt16? = {
            guard scheme.buttons.autoScroll.enabled ?? false,
                  let logiButton = scheme.buttons.autoScroll.trigger?.button?.logitechControl,
                  Self.matches(
                      logiButton: logiButton,
                      identity: identity,
                      allowsIdentityFallback: allowsIdentityFallback
                  ) else {
                return nil
            }
            return logiButton.controlIDValue
        }()

        let gestureControlID: UInt16? = {
            guard scheme.buttons.gesture.enabled ?? false,
                  let logiButton = scheme.buttons.gesture.trigger?.button?.logitechControl,
                  Self.matches(
                      logiButton: logiButton,
                      identity: identity,
                      allowsIdentityFallback: allowsIdentityFallback
                  ) else {
                return nil
            }
            return logiButton.controlIDValue
        }()

        return Set(directMappings + [autoScrollControlID, gestureControlID].compactMap(\.self))
            .intersection(availableControls.map(\.controlID))
    }

    private static func matches(
        logiButton: LogitechControlIdentity,
        identity: ReceiverLogicalDeviceIdentity?,
        allowsIdentityFallback: Bool = false
    ) -> Bool {
        LogitechControlIdentity(
            controlID: logiButton.controlID,
            productID: identity?.productID,
            serialNumber: identity?.serialNumber
        )
        .matches(logiButton, allowingIdentityFallback: allowsIdentityFallback)
    }

    private func fetchControls(using transport: HIDPPTransport, featureIndex: UInt8) -> [ControlInfo] {
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
        using transport: HIDPPTransport,
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
        using transport: HIDPPTransport,
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

    private func captureOriginalReporting(
        for controls: [ControlInfo],
        store: LogitechHardwareBaselineStore?,
        target: LogitechHardwareTargetKey?,
        using transport: HIDPPTransport,
        featureIndex: UInt8
    ) -> (
        reporting: [UInt16: ReportingInfo],
        claims: [UInt16: LogitechHardwareBaselineStore.ControlsClaim]
    ) {
        controls.reduce(into: (reporting: [UInt16: ReportingInfo](), claims: [
            UInt16: LogitechHardwareBaselineStore.ControlsClaim
        ]())) { result, control in
            if let store,
               let target,
               let claim = store.controlsBaseline(for: target, controlID: control.controlID) {
                result.reporting[control.controlID] = .init(baseline: claim.baseline)
                result.claims[control.controlID] = claim
                return
            }

            guard let reportingInfo = readReportingInfo(
                for: control.controlID,
                using: transport,
                featureIndex: featureIndex
            ) else {
                return
            }

            if let store, let target {
                let claim = store.captureControlsBaseline(
                    reportingInfo.baseline,
                    controlID: control.controlID,
                    for: target
                )
                result.reporting[control.controlID] = .init(baseline: claim.baseline)
                result.claims[control.controlID] = claim
            } else {
                result.reporting[control.controlID] = reportingInfo
            }
        }
    }

    private func restoreStoredReportingNotIn(
        _ activeControlIDs: Set<UInt16>,
        store: LogitechHardwareBaselineStore?,
        target: LogitechHardwareTargetKey?,
        using transport: HIDPPTransport,
        featureIndex: UInt8,
        locationID: Int,
        slot: UInt8
    ) {
        guard shouldAllowTeardownIO(),
              let store,
              let target
        else {
            return
        }
        let claims = store.pendingControlsBaselines(for: target)
            .filter { !activeControlIDs.contains($0.controlID) }
        guard !claims.isEmpty else {
            return
        }
        let reporting = Dictionary(uniqueKeysWithValues: claims.map {
            ($0.controlID, ReportingInfo(baseline: $0.baseline))
        })
        let failed = restoreReportingState(
            reporting,
            using: transport,
            featureIndex: featureIndex,
            locationID: locationID,
            slot: slot,
            reason: "restore no-longer-monitored reporting"
        )
        consumeRestoredBaselines(
            Dictionary(uniqueKeysWithValues: claims.map { ($0.controlID, $0) }),
            excluding: Set(failed.keys),
            store: store
        )
    }

    private func hasPendingBaseline(
        store: LogitechHardwareBaselineStore?,
        target: LogitechHardwareTargetKey?
    ) -> Bool {
        guard let store, let target else {
            return false
        }
        return !store.pendingControlsBaselines(for: target).isEmpty
    }

    private func retryStoredReportingRestoration(
        store: LogitechHardwareBaselineStore?,
        target: LogitechHardwareTargetKey?,
        using transport: HIDPPTransport,
        featureIndex: UInt8,
        locationID: Int,
        slot: UInt8
    ) {
        guard shouldAllowTeardownIO(), let store, let target else {
            return
        }
        let claims = store.pendingControlsBaselines(for: target)
        guard !claims.isEmpty else {
            return
        }
        var remaining = Dictionary(uniqueKeysWithValues: claims.map {
            ($0.controlID, ReportingInfo(baseline: $0.baseline))
        })
        _ = LogitechHardwareRestoreRetry.perform(
            operation: {
                remaining = self.restoreReportingState(
                    remaining,
                    using: transport,
                    featureIndex: featureIndex,
                    locationID: locationID,
                    slot: slot,
                    reason: "retry terminal stored reporting restore"
                )
                return remaining.isEmpty
            },
            wait: Thread.sleep(forTimeInterval:)
        )
        consumeRestoredBaselines(
            Dictionary(uniqueKeysWithValues: claims.map { ($0.controlID, $0) }),
            excluding: Set(remaining.keys),
            store: store
        )
    }

    private func retryUnkeyedReportingRestoration(
        _ pending: inout [UInt16: ReportingInfo],
        store: UnkeyedControlsRestoreStore,
        target: EphemeralControlsTargetKey,
        expectedOwnership: UnkeyedControlsRestoreStore.EntryOwnership,
        using transport: HIDPPTransport,
        featureIndex: UInt8,
        locationID: Int,
        slot: UInt8
    ) {
        guard shouldAllowTeardownIO(), !pending.isEmpty else {
            _ = store.replace(pending, for: target, expectedOwnership: expectedOwnership)
            return
        }

        _ = LogitechHardwareRestoreRetry.perform(
            operation: {
                pending = self.restoreReportingState(
                    pending,
                    using: transport,
                    featureIndex: featureIndex,
                    locationID: locationID,
                    slot: slot,
                    reason: "retry unkeyed reporting restore"
                )
                return pending.isEmpty
            },
            wait: Thread.sleep(forTimeInterval:)
        )
        _ = store.replace(pending, for: target, expectedOwnership: expectedOwnership)
    }

    private func consumeRestoredBaselines(
        _ claims: [UInt16: LogitechHardwareBaselineStore.ControlsClaim],
        excluding failedControlIDs: Set<UInt16>,
        store: LogitechHardwareBaselineStore?
    ) {
        guard let store else {
            return
        }
        for (controlID, claim) in claims where !failedControlIDs.contains(controlID) {
            _ = store.consumeControlsBaseline(claim.handle)
        }
    }

    private func setDiverted(
        _ enabled: Bool,
        for controlID: UInt16,
        using transport: HIDPPTransport,
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

            // Read back the reporting state to verify diversion actually took effect
            guard let verifyReporting = readReportingInfo(
                for: controlID, using: transport, featureIndex: featureIndex
            ) else {
                os_log(
                    "Logitech setCidReporting verification failed (read-back error): cid=0x%{public}04X",
                    log: Self.log, type: .error, controlID
                )
                return false
            }
            let actuallyDiverted = verifyReporting.flags.contains(.diverted)
            guard actuallyDiverted == enabled else {
                os_log(
                    "Logitech setCidReporting verification mismatch: cid=0x%{public}04X wanted=%{public}@ actual=%{public}@",
                    log: Self.log, type: .error, controlID,
                    enabled ? "diverted" : "native",
                    actuallyDiverted ? "diverted" : "native"
                )
                return false
            }
        }

        return true
    }

    private func setDivertedWithRetry(
        _ enabled: Bool,
        for controlID: UInt16,
        using transport: HIDPPTransport,
        featureIndex: UInt8,
        maxAttempts: Int = 3,
        retryDelay: TimeInterval = 0.05
    ) -> Bool {
        guard maxAttempts >= 1 else {
            return false
        }
        for attempt in 1 ... maxAttempts {
            if setDiverted(enabled, for: controlID, using: transport, featureIndex: featureIndex) {
                return true
            }

            guard attempt < maxAttempts, shouldContinueRunning() else {
                break
            }

            os_log(
                "Logitech setCidReporting retry %{public}d/%{public}d: cid=0x%{public}04X",
                log: Self.log, type: .info,
                attempt, maxAttempts, controlID
            )
            Thread.sleep(forTimeInterval: retryDelay)
        }
        return false
    }

    private func restoreReportingState(
        _ reportingByControlID: [UInt16: ReportingInfo],
        using transport: HIDPPTransport,
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
        state.shouldContinueRunning
    }

    /// The monitor loop stops as soon as it is disabled, but its active target
    /// must still be allowed to restore the reporting state in its defer block.
    /// This remains true only while that worker owns the target transport.
    private func shouldAllowTeardownIO() -> Bool {
        state.shouldAllowTeardownIO
    }

    private func postSyntheticButton(button: Int, down: Bool) {
        let shouldPost = state.updatePressedButton(button, down: down)

        guard shouldPost else {
            return
        }

        SyntheticMouseButtonEventEmitter.post(button: button, down: down)
    }

    private func postSyntheticClick(button: Int) {
        postSyntheticButton(button: button, down: true)
        postSyntheticButton(button: button, down: false)
    }

    private func releaseButtonIfNeeded() {
        let buttonsToRelease = state.takePressedButtons()

        for button in buttonsToRelease {
            SyntheticMouseButtonEventEmitter.post(button: button, down: false)
        }
    }

    private func cancelPressedControlInteractions(
        _ controlIDs: Set<UInt16>,
        productID: Int?,
        serialNumber: String?,
        allowsIdentityFallback: Bool,
        isRecording: Bool,
        recordingSessionID: UUID?
    ) {
        guard !controlIDs.isEmpty else {
            return
        }

        let modifierFlags = ModifierState.shared.currentFlags
        let identities = controlIDs.sorted().map {
            LogitechControlIdentity(
                controlID: Int($0),
                productID: productID,
                serialNumber: serialNumber
            )
        }

        if isRecording {
            guard let recordingSessionID else {
                return
            }
            for identity in identities {
                DispatchQueue.main.async {
                    guard SettingsState.shared.isCurrentButtonMappingRecordingSession(recordingSessionID) else {
                        return
                    }

                    SettingsState.shared.recordedButtonMappingEvent = .init(
                        recordingSessionID: recordingSessionID,
                        button: .logitechControl(identity),
                        scroll: nil,
                        modifierFlags: modifierFlags,
                        isPressed: false
                    )
                }
            }
            return
        }

        let eventContext = eventContextSnapshot()
        for identity in identities {
            let context = LogitechEventContext(
                device: device,
                pid: eventContext.pid,
                display: eventContext.display,
                mouseLocation: eventContext.mouseLocation,
                controlIdentity: identity,
                allowsIdentityFallback: allowsIdentityFallback,
                isPressed: false,
                modifierFlags: modifierFlags
            )
            _ = EventThread.shared.performAndWait {
                EventTransformerManager.shared.cancelLogitechControlInteraction(context)
            }
        }
    }

    static func isDivertedButtonsNotification(
        _ report: [UInt8],
        featureIndex: UInt8,
        deviceIndices: Set<UInt8>
    ) -> Bool {
        guard LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification(report) == nil,
              report.count >= 4,
              [LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID,
               LogitechHIDPPDeviceMetadataProvider.Constants.longReportID].contains(report[0]),
              deviceIndices.contains(report[1]),
              report[2] == featureIndex,
              report[3] & 0x0F == 0
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
        transport: HIDPPTransport,
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

enum LogitechSyntheticFallbackAction: Equatable {
    case suppress
    case postCurrentEvent
    case postClick
}

struct LogitechSyntheticFallbackCoordinator {
    private var deferredControls = Set<LogitechControlIdentity>()

    mutating func action(
        for controlIdentity: LogitechControlIdentity,
        isPressed: Bool,
        handlingResult: LogitechControlEventHandlingResult
    ) -> LogitechSyntheticFallbackAction {
        if isPressed {
            switch handlingResult {
            case .handledDeferringSyntheticFallback:
                deferredControls.insert(controlIdentity)
                return .suppress
            case .handled:
                deferredControls.remove(controlIdentity)
                return .suppress
            case .handledAllowingSyntheticFallback, .notHandled:
                deferredControls.remove(controlIdentity)
                return .postCurrentEvent
            }
        }

        let wasDeferred = deferredControls.remove(controlIdentity) != nil

        if handlingResult.suppressesSyntheticFallback {
            return .suppress
        }

        return wasDeferred ? .postClick : .postCurrentEvent
    }

    mutating func reset() {
        deferredControls.removeAll()
    }
}

struct LogitechMonitorReconfigurationRequest {
    private var needed = false
    private var forced = false

    mutating func request(forced: Bool = false) {
        needed = true
        self.forced = self.forced || forced
    }

    mutating func consume(
        deferringWhileControlsArePressed: Bool
    ) -> (needed: Bool, forced: Bool) {
        guard needed else {
            return (false, false)
        }

        if deferringWhileControlsArePressed, !forced {
            return (false, false)
        }

        let result = (needed: true, forced: forced)
        reset()
        return result
    }

    mutating func reset() {
        needed = false
        forced = false
    }
}

final class LogitechReprogrammableControlsMonitorState {
    final class RestartBarrier {}

    private struct SleepResumeRequest {
        let restartBarrier: RestartBarrier
        let action: () -> Void
    }

    private typealias WorkerResources = (Thread?, HIDPPNotificationHandling?, ObservationToken?)

    private let queue = DispatchQueue(label: "linearmouse.logitech-controls.state")
    private let reconfigurationSemaphore = DispatchSemaphore(value: 0)

    private var isEnabled = false
    private var workerThread: Thread?
    /// Teardown I/O belongs to one worker target lifetime. Once invalidated it
    /// can only become valid again when that worker has fully stopped and a
    /// replacement worker is created.
    private var workerTargetIsValid = false
    private weak var activeNotificationEndpoint: HIDPPNotificationHandling?
    private var directDeviceReportObservationToken: ObservationToken?
    private var reconfigurationRequest = LogitechMonitorReconfigurationRequest()
    private var pressedButtons = Set<Int>()
    private var syntheticFallbackCoordinator = LogitechSyntheticFallbackCoordinator()
    private var stopCompletions = [() -> Void]()
    /// A completion-backed stop is a terminal teardown for the current worker.
    /// Do not let a demand/configuration enable revive it before its caller has
    /// received the completion and started a new lifecycle explicitly.
    private var restartBarrier: RestartBarrier?
    private var allowsTeardownIO = false
    /// The outer lifecycle request owns teardown I/O admission. Its concrete
    /// token and absolute deadline are checked at every HID++ send boundary.
    private var teardownAuthorization: CancellationToken?
    private var teardownDeadline: Date?
    /// A terminal restore can outlive normal monitor demand. While set, the
    /// worker skips diversion and exits only after its pending baseline drains.
    private var restoresPendingForTeardown = false
    /// Revoking an active ordinary target requires exactly one replacement
    /// restore-only worker. This concrete transition flag is consumed by the
    /// retiring worker, so the replacement's natural exit cannot restart it.
    private var restoreWorkerReplacementRequired = false
    private var hasEstablishedActiveTarget = false
    private var hasStoreBackedActiveTargetValue = false
    /// A wake can race the restore-only worker. Keep only one demand
    /// reconciliation and release it with the exact worker restart barrier.
    private var sleepResumeRequest: SleepResumeRequest?

    var shouldContinueRunning: Bool {
        queue.sync { isEnabled } && !Thread.current.isCancelled
    }

    var shouldAllowTeardownIO: Bool {
        queue.sync {
            workerThread != nil
                && workerTargetIsValid
                && allowsTeardownIO
                && Self.teardownIsAuthorized(
                    teardownAuthorization,
                    deadline: teardownDeadline
                )
        }
    }

    var isRestoringPendingForTeardown: Bool {
        queue.sync { restoresPendingForTeardown }
    }

    var hasActiveUnkeyedTarget: Bool {
        queue.sync {
            workerThread != nil
                && workerTargetIsValid
                && hasEstablishedActiveTarget
                && !hasStoreBackedActiveTargetValue
        }
    }

    func enable(makeWorkerThread: () -> Thread) {
        let thread = queue.sync { () -> Thread? in
            guard !isEnabled, restartBarrier == nil else {
                return nil
            }

            isEnabled = true
            teardownAuthorization = nil
            teardownDeadline = nil
            guard workerThread == nil else {
                allowsTeardownIO = workerTargetIsValid
                return nil
            }

            let thread = makeWorkerThread()
            workerThread = thread
            workerTargetIsValid = true
            allowsTeardownIO = true
            return thread
        }

        thread?.start()
    }

    func resumeAfterSleep(_ action: @escaping () -> Void) {
        let (shouldRunNow, resourcesToStop) = queue.sync { () -> (Bool, WorkerResources) in
            if let restartBarrier {
                if sleepResumeRequest?.restartBarrier !== restartBarrier {
                    sleepResumeRequest = .init(
                        restartBarrier: restartBarrier,
                        action: action
                    )
                }

                // A fast wake no longer needs to finish returning this target
                // to native reporting. Cancel only this monitor's restore;
                // receiver monitors that are still awaiting a verified route
                // do not call resume and can complete their native restore.
                guard restoresPendingForTeardown else {
                    return (false, (nil, nil, nil))
                }
                let resources = (
                    workerThread,
                    activeNotificationEndpoint,
                    directDeviceReportObservationToken
                )
                isEnabled = false
                workerTargetIsValid = false
                allowsTeardownIO = false
                teardownAuthorization = nil
                teardownDeadline = nil
                restoresPendingForTeardown = false
                restoreWorkerReplacementRequired = false
                reconfigurationRequest.reset()
                activeNotificationEndpoint = nil
                directDeviceReportObservationToken = nil
                return (false, resources)
            }

            // The exact barrier may have been released while its completion
            // callbacks are still running. Coalesce another wake with that
            // already-authorized delivery instead of running it twice.
            if sleepResumeRequest != nil {
                return (false, (nil, nil, nil))
            }
            return (true, (nil, nil, nil))
        }

        reconfigurationSemaphore.signal()
        resourcesToStop.1?.wake()
        resourcesToStop.0?.cancel()
        resourcesToStop.2?.cancel()

        guard shouldRunNow else {
            return
        }
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }

    func cancelResumeAfterSleep() {
        queue.sync {
            sleepResumeRequest = nil
        }
    }

    func disable() {
        disable(
            allowingTeardownIO: true
        )
    }

    /// Final teardown has no safe target for HID++ I/O.
    func abandon() {
        disable(
            allowingTeardownIO: false,
            overridingPendingRestore: true
        )
        queue.sync {
            restoresPendingForTeardown = false
            teardownAuthorization = nil
            teardownDeadline = nil
            sleepResumeRequest = nil
        }
    }

    /// Permanently revokes teardown I/O for the current worker target. The
    /// invalidation closure runs in the same state transaction, before the old
    /// worker can observe cancellation or a replacement worker can be created.
    func invalidateTarget(invalidateOwnership: () -> Void) {
        let resources = queue.sync { () -> WorkerResources in
            let resources = (workerThread, activeNotificationEndpoint, directDeviceReportObservationToken)
            workerTargetIsValid = false
            allowsTeardownIO = false
            teardownAuthorization = nil
            teardownDeadline = nil
            reconfigurationRequest.reset()
            activeNotificationEndpoint = nil
            directDeviceReportObservationToken = nil
            invalidateOwnership()
            return resources
        }

        reconfigurationSemaphore.signal()
        resources.1?.wake()
        resources.0?.cancel()
        resources.2?.cancel()
    }

    /// Atomically upgrades a sleeping worker to a teardown-capable,
    /// restore-only worker and attaches its completion. If the worker has
    /// already stopped, a worker is created only when a baseline is still
    /// pending. A worker that never established a target has changed no
    /// reporting state, so it is cancelled instead of spending the terminal
    /// budget retrying target discovery.
    func restorePendingForTeardown(
        _ requiresRestoreWorker: Bool,
        authorization: CancellationToken? = nil,
        deadline: Date? = nil,
        makeWorkerThread: () -> Thread,
        completion: @escaping () -> Void
    ) {
        let (thread, resourcesToStop, completions) = queue.sync {
            () -> (Thread?, WorkerResources, [() -> Void]) in
            if restoresPendingForTeardown {
                teardownAuthorization = authorization
                teardownDeadline = deadline
                stopCompletions.append(completion)
                return (nil, (nil, nil, nil), [])
            }

            if !requiresRestoreWorker,
               let workerThread,
               !hasEstablishedActiveTarget {
                let resources: WorkerResources = (
                    workerThread,
                    activeNotificationEndpoint,
                    directDeviceReportObservationToken
                )
                stopCompletions.append(completion)
                restartBarrier = restartBarrier ?? RestartBarrier()
                isEnabled = false
                allowsTeardownIO = false
                teardownAuthorization = nil
                teardownDeadline = nil
                reconfigurationRequest.reset()
                activeNotificationEndpoint = nil
                directDeviceReportObservationToken = nil
                return (nil, resources, [])
            }

            guard workerThread != nil || requiresRestoreWorker else {
                return (nil, (nil, nil, nil), [completion])
            }

            stopCompletions.append(completion)
            restartBarrier = RestartBarrier()
            restoresPendingForTeardown = true
            isEnabled = true
            allowsTeardownIO = workerThread == nil || workerTargetIsValid
            teardownAuthorization = authorization
            teardownDeadline = deadline
            // Route an active notification loop through its existing forced
            // restart path. The next outer iteration then observes the
            // restore-only state and drains baselines without diversion.
            reconfigurationRequest.request(forced: true)

            if let workerThread {
                // The old worker may already be inside ordinary diversion.
                // Revoke that concrete target before cancellation; only the
                // replacement restore-only worker may use teardown admission.
                let resources: WorkerResources = (
                    workerThread,
                    activeNotificationEndpoint,
                    directDeviceReportObservationToken
                )
                workerTargetIsValid = false
                allowsTeardownIO = false
                restoreWorkerReplacementRequired = true
                activeNotificationEndpoint = nil
                directDeviceReportObservationToken = nil
                return (nil, resources, [])
            }

            let thread = makeWorkerThread()
            workerThread = thread
            workerTargetIsValid = true
            allowsTeardownIO = true
            return (thread, (nil, nil, nil), [])
        }

        reconfigurationSemaphore.signal()
        (resourcesToStop.1 ?? queue.sync { activeNotificationEndpoint })?.wake()
        resourcesToStop.0?.cancel()
        resourcesToStop.2?.cancel()
        thread?.start()
        dispatchStopCompletions(completions)
    }

    private func disable(
        allowingTeardownIO: Bool = true,
        overridingPendingRestore: Bool = false
    ) {
        let (resources, completions) = queue.sync { () -> (WorkerResources, [() -> Void]) in
            let resources = (workerThread, activeNotificationEndpoint, directDeviceReportObservationToken)
            if overridingPendingRestore {
                sleepResumeRequest = nil
            }
            // Restore is the strongest teardown policy. A later ordinary or
            // abandon may override it, but an ordinary disable cannot cancel
            // or weaken the in-flight restore operation.
            if restoresPendingForTeardown, !overridingPendingRestore {
                return ((nil, nil, nil), [])
            }

            isEnabled = false
            allowsTeardownIO = workerTargetIsValid && allowingTeardownIO
            teardownAuthorization = nil
            teardownDeadline = nil
            reconfigurationRequest.reset()
            activeNotificationEndpoint = nil
            directDeviceReportObservationToken = nil
            guard workerThread == nil else {
                return (resources, [])
            }

            workerTargetIsValid = false
            let completions = stopCompletions
            stopCompletions.removeAll()
            restartBarrier = nil
            return (resources, completions)
        }

        reconfigurationSemaphore.signal()
        resources.1?.wake()
        resources.0?.cancel()
        resources.2?.cancel()
        dispatchStopCompletions(completions)
    }

    func workerDidStop(restartIfEnabled: Bool, makeWorkerThread: () -> Thread) {
        let (thread, token, completions, barrierToRelease) = queue.sync {
            () -> (Thread?, ObservationToken?, [() -> Void], RestartBarrier?) in
            let replacementRequired = restoreWorkerReplacementRequired
            restoreWorkerReplacementRequired = false
            workerThread = nil
            workerTargetIsValid = false
            hasEstablishedActiveTarget = false
            hasStoreBackedActiveTargetValue = false
            activeNotificationEndpoint = nil
            let reportObservationToken = directDeviceReportObservationToken
            directDeviceReportObservationToken = nil

            // A sleep worker is cancelled and cannot be revived in place. A
            // pending teardown restore is the sole exception to the normal
            // completion barrier: replace that retiring worker with a fresh
            // restore-only worker, then keep the barrier until it drains.
            guard isEnabled,
                  restartIfEnabled || replacementRequired,
                  restartBarrier == nil || restoresPendingForTeardown,
                  Self.teardownIsAuthorized(
                      teardownAuthorization,
                      deadline: teardownDeadline
                  )
            else {
                isEnabled = false
                allowsTeardownIO = false
                teardownAuthorization = nil
                teardownDeadline = nil
                reconfigurationRequest.reset()
                restoresPendingForTeardown = false
                let completions = stopCompletions
                stopCompletions.removeAll()
                let barrierToRelease = completions.isEmpty ? nil : restartBarrier
                if barrierToRelease == nil {
                    restartBarrier = nil
                }
                return (
                    nil,
                    reportObservationToken,
                    completions,
                    barrierToRelease
                )
            }

            reconfigurationRequest.reset()
            let nextThread = makeWorkerThread()
            workerThread = nextThread
            workerTargetIsValid = true
            allowsTeardownIO = true
            return (nextThread, reportObservationToken, [], nil)
        }

        token?.cancel()
        thread?.start()
        dispatchStopCompletions(
            completions,
            releasing: barrierToRelease
        )
    }

    private static func teardownIsAuthorized(
        _ authorization: CancellationToken?,
        deadline: Date?
    ) -> Bool {
        (authorization?.shouldContinue ?? true)
            && deadline.map { Date() < $0 } != false
    }

    func requestReconfiguration(forced: Bool = false) {
        let request = queue.sync { () -> (accepted: Bool, endpoint: HIDPPNotificationHandling?) in
            guard isEnabled else {
                return (false, nil)
            }

            reconfigurationRequest.request(forced: forced)
            return (true, activeNotificationEndpoint)
        }
        guard request.accepted else {
            return
        }

        reconfigurationSemaphore.signal()
        request.endpoint?.wake()
    }

    func consumeReconfigurationRequest(
        deferringWhileControlsArePressed: Bool = false
    ) -> (needed: Bool, forced: Bool) {
        queue.sync {
            reconfigurationRequest.consume(
                deferringWhileControlsArePressed: deferringWhileControlsArePressed
            )
        }
    }

    func waitForReconfigurationOrStop(
        timeout: TimeInterval
    ) -> (shouldContinue: Bool, forced: Bool, timedOut: Bool) {
        let result = waitForReconfigurationOrStop(timeout: timeout, returnsOnTimeout: false)
        return (result.shouldContinue, result.forced, result.timedOut)
    }

    func waitForReconfigurationOrRetryTimeout(
        timeout: TimeInterval
    ) -> (shouldContinue: Bool, forced: Bool, timedOut: Bool) {
        let result = waitForReconfigurationOrStop(timeout: timeout, returnsOnTimeout: true)
        return (result.shouldContinue, result.forced, result.timedOut)
    }

    private func waitForReconfigurationOrStop(timeout: TimeInterval, returnsOnTimeout: Bool)
        -> (shouldContinue: Bool, forced: Bool, timedOut: Bool) {
        while shouldContinueRunning {
            let request = consumeReconfigurationRequest()
            if request.needed {
                return (true, request.forced, false)
            }

            let waitResult = reconfigurationSemaphore.wait(timeout: .now() + timeout)
            if returnsOnTimeout, waitResult == .timedOut {
                return (true, false, true)
            }
        }

        return (false, false, false)
    }

    fileprivate func setActiveNotificationEndpoint(_ endpoint: HIDPPNotificationHandling?) {
        queue.sync {
            guard isEnabled, workerTargetIsValid else {
                return
            }

            activeNotificationEndpoint = endpoint
        }
    }

    func setStoreBackedActiveTarget(_ value: Bool) {
        queue.sync {
            guard workerThread != nil, workerTargetIsValid else {
                return
            }
            hasEstablishedActiveTarget = true
            hasStoreBackedActiveTargetValue = value
        }
    }

    func setDirectDeviceReportObservationToken(_ token: ObservationToken) -> ObservationToken? {
        queue.sync {
            guard isEnabled, workerTargetIsValid else {
                return token
            }

            let previousToken = directDeviceReportObservationToken
            directDeviceReportObservationToken = token
            return previousToken
        }
    }

    func updatePressedButton(_ button: Int, down: Bool) -> Bool {
        queue.sync { down ? pressedButtons.insert(button).inserted : pressedButtons.remove(button) != nil }
    }

    func syntheticFallbackAction(
        for controlIdentity: LogitechControlIdentity,
        isPressed: Bool,
        handlingResult: LogitechControlEventHandlingResult
    ) -> LogitechSyntheticFallbackAction {
        queue.sync {
            syntheticFallbackCoordinator.action(
                for: controlIdentity,
                isPressed: isPressed,
                handlingResult: handlingResult
            )
        }
    }

    func takePressedButtons() -> Set<Int> {
        queue.sync {
            defer {
                pressedButtons.removeAll()
                syntheticFallbackCoordinator.reset()
            }
            return pressedButtons
        }
    }

    private func dispatchStopCompletions(
        _ completions: [() -> Void],
        releasing expectedRestartBarrier: RestartBarrier? = nil
    ) {
        guard !completions.isEmpty else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            var releasedRestartBarrier: RestartBarrier?
            if let expectedRestartBarrier {
                self?.queue.sync {
                    guard self?.restartBarrier === expectedRestartBarrier else {
                        return
                    }
                    self?.restartBarrier = nil
                    releasedRestartBarrier = expectedRestartBarrier
                }
            }
            completions.forEach { $0() }

            guard let releasedRestartBarrier else {
                return
            }
            let resumeAfterSleepAction = self?.queue.sync { () -> (() -> Void)? in
                guard self?.sleepResumeRequest?.restartBarrier === releasedRestartBarrier else {
                    return nil
                }
                defer { self?.sleepResumeRequest = nil }
                return self?.sleepResumeRequest?.action
            }
            resumeAfterSleepAction?()
        }
    }
}

private protocol HIDPPNotificationHandling: AnyObject {
    func enableNotifications(until shouldContinue: @escaping () -> Bool)
    func wake()
    func discardHIDPPNotifications(matching: @escaping ([UInt8]) -> Bool)
    func waitForHIDPPNotification(
        timeout: TimeInterval,
        matching: @escaping ([UInt8]) -> Bool,
        until shouldContinue: (() -> Bool)?
    ) -> [UInt8]?
}

/// Retains unsolicited HID++ notifications across consumer gaps. Its condition
/// wake is coalesced, so historical reports cannot build up a counting-
/// semaphore burst when a later matcher has no matching report.
final class HIDPPNotificationBuffer {
    private let maximumBufferedReports: Int
    private let condition = NSCondition()
    private let onWait: (() -> Void)?
    private var bufferedReports = [[UInt8]]()
    private var interruptPending = false

    init(maximumBufferedReports: Int = 64, onWait: (() -> Void)? = nil) {
        self.maximumBufferedReports = maximumBufferedReports
        self.onWait = onWait
    }

    var bufferedReportCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return bufferedReports.count
    }

    func appendIfUnsolicited(_ report: Data) {
        appendIfUnsolicited([UInt8](report))
    }

    func appendIfUnsolicited(_ report: [UInt8]) {
        guard HIDPPUnsolicitedNotification.matches(report) else {
            return
        }

        condition.lock()
        bufferedReports.append(report)
        if bufferedReports.count > maximumBufferedReports {
            bufferedReports.removeFirst(bufferedReports.count - maximumBufferedReports)
        }
        condition.broadcast()
        condition.unlock()
    }

    func wake() {
        condition.lock()
        interruptPending = true
        condition.broadcast()
        condition.unlock()
    }

    func discard(matching: @escaping ([UInt8]) -> Bool) {
        condition.lock()
        bufferedReports.removeAll(where: matching)
        condition.broadcast()
        condition.unlock()
    }

    func wait(
        timeout: TimeInterval,
        matching: @escaping ([UInt8]) -> Bool,
        until shouldContinue: (() -> Bool)? = nil
    ) -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        var shouldCallOnWait = true

        condition.lock()
        while true {
            // Explicit interrupts represent lifecycle/reconfiguration control
            // flow and therefore take priority over buffered input reports.
            if interruptPending {
                interruptPending = false
                condition.unlock()
                return nil
            }

            if let index = bufferedReports.firstIndex(where: matching) {
                let report = bufferedReports.remove(at: index)
                condition.unlock()
                return report
            }

            condition.unlock()
            let continues = shouldContinue?() ?? true
            condition.lock()
            guard continues else {
                condition.unlock()
                return nil
            }

            // Recheck state changed while the external continuation predicate
            // ran without this condition lock.
            if interruptPending || bufferedReports.contains(where: matching) {
                continue
            }

            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                condition.unlock()
                return nil
            }

            if shouldCallOnWait {
                shouldCallOnWait = false
                condition.unlock()
                onWait?()
                condition.lock()
                // An append, interrupt, or cancellation can occur while the
                // diagnostic hook runs without the condition lock.
                continue
            }

            _ = condition.wait(until: deadline)
        }
    }
}

private enum HIDPPUnsolicitedNotification {
    static func matches(_ report: [UInt8]) -> Bool {
        guard report.count >= LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength,
              [LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID,
               LogitechHIDPPDeviceMetadataProvider.Constants.longReportID].contains(report[0])
        else {
            return false
        }

        if LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification(report) != nil {
            return true
        }

        // HID++ 1.0 receiver command replies use register sub-IDs. HID++ 2.0
        // notifications use software ID 0, whereas host command replies use 8.
        guard ![0x80, 0x81, 0x83, 0x8F].contains(report[2]) else {
            return false
        }
        return report[3] & 0x0F == 0
    }
}

final class HIDPPNotificationEndpoint: HIDPPNotificationHandling {
    private static let maxBufferedReports = 64

    private let buffer = HIDPPNotificationBuffer(maximumBufferedReports: maxBufferedReports)

    func enableNotifications(until _: @escaping () -> Bool) {}

    func wake() {
        buffer.wake()
    }

    func discardHIDPPNotifications(matching: @escaping ([UInt8]) -> Bool) {
        buffer.discard(matching: matching)
    }

    func handleInputReport(_ report: Data) {
        buffer.appendIfUnsolicited(report)
    }

    func waitForHIDPPNotification(
        timeout: TimeInterval,
        matching: @escaping ([UInt8]) -> Bool,
        until shouldContinue: (() -> Bool)? = nil
    ) -> [UInt8]? {
        buffer.wait(timeout: timeout, matching: matching, until: shouldContinue)
    }
}

extension LogitechReceiverChannel: HIDPPNotificationHandling {
    func enableNotifications(until shouldContinue: @escaping () -> Bool) {
        enableWirelessNotifications(until: shouldContinue)
    }

    func discardHIDPPNotifications(matching: @escaping ([UInt8]) -> Bool) {
        notificationBuffer.discard(matching: matching)
    }
}

private extension UInt16 {
    var bytes: [UInt8] {
        [UInt8(self >> 8), UInt8(self & 0xFF)]
    }
}
