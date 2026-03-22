// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
@testable import LinearMouse
import XCTest

final class VendorSpecificDeviceMetadataTests: XCTestCase {
    func testMatcherMatchesVendorAndTransport() {
        let matcher = VendorSpecificDeviceMatcher(
            vendorID: 0x046D,
            productIDs: [0xB015],
            transports: ["Bluetooth Low Energy"]
        )

        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: "Bluetooth Low Energy"
        )

        XCTAssertTrue(matcher.matches(device: device))
    }

    func testMatcherRejectsUnknownTransport() {
        let matcher = VendorSpecificDeviceMatcher(
            vendorID: 0x046D,
            productIDs: nil,
            transports: ["USB"]
        )

        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: "Bluetooth Low Energy"
        )

        XCTAssertFalse(matcher.matches(device: device))
    }

    func testLogitechProviderMatchesLogitechDeviceShape() {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: "Bluetooth Low Energy",
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )

        XCTAssertTrue(provider.matches(device: device))
    }

    func testReceiverLogicalDeviceIdentityUsesAllFieldsForEquality() {
        let lhs = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 0x1234,
            slot: 1,
            kind: .mouse,
            name: "Mouse A",
            serialNumber: "AAAA",
            productID: 0x1234,
            batteryLevel: 50
        )
        let rhs = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 0x1234,
            slot: 1,
            kind: .trackball,
            name: "Mouse B",
            serialNumber: "BBBB",
            productID: 0x5678,
            batteryLevel: 80
        )

        XCTAssertNotEqual(lhs, rhs)
    }

    func testReceiverLogicalDeviceIdentityCanDetectSameLogicalDevice() {
        let lhs = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 0x1234,
            slot: 1,
            kind: .mouse,
            name: "Mouse A",
            serialNumber: "AAAA",
            productID: 0x1234,
            batteryLevel: 50
        )
        let rhs = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 0x1234,
            slot: 1,
            kind: .trackball,
            name: "Mouse B",
            serialNumber: "BBBB",
            productID: 0x5678,
            batteryLevel: 80
        )

        XCTAssertTrue(lhs.isSameLogicalDevice(as: rhs))
    }

    func testParseReceiverConnectionNotificationTracksConnectState() {
        let notification = LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification([
            0x10, 0x02, 0x41, 0x00, 0x02, 0x00, 0x00
        ])

        XCTAssertEqual(notification?.slot, 2)
        XCTAssertEqual(notification?.snapshot, .init(isConnected: true, kind: 0x02))
    }

    func testParseConnectedDeviceCountReadsReceiverConnectionRegister() {
        XCTAssertEqual(
            LogitechHIDPPDeviceMetadataProvider.parseConnectedDeviceCount([0x10, 0xFF, 0x81, 0x02, 0x00, 0x01, 0x00]),
            1
        )
    }

    func testLogitechDivertedButtonsNotificationMatchesGestureButtonEvent() {
        XCTAssertTrue(
            LogitechReprogrammableControlsMonitor.isDivertedButtonsNotification(
                [0x10, 0x02, 0x05, 0x08, 0x00, 0xC3, 0x00],
                featureIndex: 0x05,
                slot: 0x02
            )
        )
    }

    func testLogitechDivertedButtonsNotificationParsesPressedControls() {
        XCTAssertEqual(
            LogitechReprogrammableControlsMonitor.parseDivertedButtonsNotification([
                0x10,
                0x02,
                0x05,
                0x08,
                0x00,
                0xC3,
                0x00,
                0xC4
            ]),
            Set([0x00C3, 0x00C4])
        )
    }

    func testLogitechDivertedButtonsNotificationRejectsWrongSlot() {
        XCTAssertFalse(
            LogitechReprogrammableControlsMonitor.isDivertedButtonsNotification(
                [0x10, 0x03, 0x05, 0x08, 0x00, 0xC3, 0x00],
                featureIndex: 0x05,
                slot: 0x02
            )
        )
    }

    func testPreferredReceiverIdentityChoosesSingleMouse() {
        let identities: [ReceiverLogicalDeviceIdentity] = [
            .init(
                receiverLocationID: 0x1234,
                slot: 1,
                kind: .keyboard,
                name: "Keyboard",
                serialNumber: nil,
                productID: nil,
                batteryLevel: nil
            ),
            .init(
                receiverLocationID: 0x1234,
                slot: 2,
                kind: .mouse,
                name: "M720",
                serialNumber: nil,
                productID: nil,
                batteryLevel: nil
            )
        ]

        XCTAssertEqual(LogitechReprogrammableControlsMonitor.preferredIdentity(from: identities)?.slot, 2)
    }

    func testPreferredReceiverIdentityReturnsNilForMultipleMice() {
        let identities: [ReceiverLogicalDeviceIdentity] = [
            .init(
                receiverLocationID: 0x1234,
                slot: 1,
                kind: .mouse,
                name: "M720",
                serialNumber: nil,
                productID: nil,
                batteryLevel: nil
            ),
            .init(
                receiverLocationID: 0x1234,
                slot: 2,
                kind: .mouse,
                name: "Anywhere",
                serialNumber: nil,
                productID: nil,
                batteryLevel: nil
            )
        ]

        XCTAssertNil(LogitechReprogrammableControlsMonitor.preferredIdentity(from: identities))
    }

    func testLogitechGestureButtonControlIDsIncludeM720ThumbButton() {
        XCTAssertTrue(LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.gestureButtonControlIDs.contains(0x00D0))
    }

    func testLogitechGestureButtonTaskIDsIncludeM720GestureTasks() {
        XCTAssertTrue(LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.gestureButtonTaskIDs.contains(0x00AD))
        XCTAssertTrue(LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.gestureButtonTaskIDs.contains(0x00A9))
    }

    func testSyntheticButtonNumbersAreStableByControlID() {
        let mapping = LogitechReprogrammableControlsMonitor.syntheticButtonNumbers(for: [0x00D7, 0x00D0, 0x00C3])

        XCTAssertEqual(mapping[0x00C3], 8)
        XCTAssertEqual(mapping[0x00D0], 9)
        XCTAssertEqual(mapping[0x00D7], 10)
    }

    func testSyntheticButtonNumberIgnoresEnumerationOrder() {
        let forward = LogitechReprogrammableControlsMonitor.syntheticButtonNumbers(for: [0x00D0, 0x00D7])
        let reverse = LogitechReprogrammableControlsMonitor.syntheticButtonNumbers(for: [0x00D7, 0x00D0])

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(
            LogitechReprogrammableControlsMonitor.syntheticButtonNumber(for: 0x00D0, among: [0x00D7, 0x00D0]),
            8
        )
        XCTAssertEqual(
            LogitechReprogrammableControlsMonitor.syntheticButtonNumber(for: 0x00D7, among: [0x00D7, 0x00D0]),
            9
        )
    }

    func testLogitechControlIdentityProvidesFriendlyUserVisibleName() {
        XCTAssertEqual(
            LogitechControlIdentity(controlID: 0x00D0, logicalDeviceProductID: nil, logicalDeviceSerialNumber: nil)
                .userVisibleName,
            "Logitech CID 0x00D0"
        )
        XCTAssertEqual(
            LogitechControlIdentity(controlID: 0x1234, logicalDeviceProductID: nil, logicalDeviceSerialNumber: nil)
                .userVisibleName,
            "Logitech CID 0x1234"
        )
    }

    func testReceiverSlotStateStoreDoesNotResurrectDisconnectedSlotFromPairingMetadata() {
        var store = ReceiverSlotStateStore()
        let identity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 0x1234,
            slot: 1,
            kind: .mouse,
            name: "Mouse A",
            serialNumber: "AAAA",
            productID: 0x1234,
            batteryLevel: 60
        )

        store.mergeDiscovery(.init(identities: [identity], connectionSnapshots: [
            1: .init(isConnected: false, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ], liveReachableSlots: []))
        store.mergeDiscovery(.init(identities: [identity], connectionSnapshots: [:], liveReachableSlots: []))

        XCTAssertTrue(store.currentPublishedIdentities().isEmpty)
    }

    func testReceiverSlotStateStoreRestoresSlotAfterReconnectSnapshot() {
        var store = ReceiverSlotStateStore()
        let identity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 0x1234,
            slot: 1,
            kind: .mouse,
            name: "Mouse A",
            serialNumber: "AAAA",
            productID: 0x1234,
            batteryLevel: 60
        )

        store.mergeDiscovery(.init(identities: [identity], connectionSnapshots: [
            1: .init(isConnected: false, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ], liveReachableSlots: []))
        store.mergeConnectionSnapshots([
            1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ])

        XCTAssertEqual(store.currentPublishedIdentities(), [identity])
    }

    func testReceiverSlotStateStoreTreatsFreshBatteryMetadataAsReconnectEvidence() {
        var store = ReceiverSlotStateStore()
        let disconnectedIdentity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 0x1234,
            slot: 1,
            kind: .mouse,
            name: "Mouse A",
            serialNumber: "AAAA",
            productID: 0x1234,
            batteryLevel: nil
        )
        let reconnectedIdentity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 0x1234,
            slot: 1,
            kind: .mouse,
            name: "Mouse A",
            serialNumber: "AAAA",
            productID: 0x1234,
            batteryLevel: 60
        )

        store.mergeDiscovery(.init(identities: [disconnectedIdentity], connectionSnapshots: [
            1: .init(isConnected: false, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ], liveReachableSlots: []))
        store.mergeDiscovery(.init(identities: [reconnectedIdentity], connectionSnapshots: [:], liveReachableSlots: []))

        XCTAssertEqual(store.currentPublishedIdentities(), [reconnectedIdentity])
    }

    func testReceiverSlotStateStoreTreatsLiveReachabilityAsReconnectEvidence() {
        var store = ReceiverSlotStateStore()
        let identity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 0x1234,
            slot: 1,
            kind: .mouse,
            name: "Mouse A",
            serialNumber: "AAAA",
            productID: 0x1234,
            batteryLevel: nil
        )

        store.mergeDiscovery(.init(
            identities: [identity],
            connectionSnapshots: [1: .init(isConnected: false, kind: ReceiverLogicalDeviceKind.mouse.rawValue)],
            liveReachableSlots: []
        ))
        store.mergeDiscovery(.init(
            identities: [identity],
            connectionSnapshots: [:],
            liveReachableSlots: [1]
        ))

        XCTAssertEqual(store.currentPublishedIdentities(), [identity])
    }

    func testReceiverSlotStateStoreDoesNotReconnectWithoutEvidence() {
        var store = ReceiverSlotStateStore()
        let identity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 0x1234,
            slot: 1,
            kind: .mouse,
            name: "Mouse A",
            serialNumber: "AAAA",
            productID: 0x1234,
            batteryLevel: nil
        )

        store.mergeDiscovery(.init(
            identities: [identity],
            connectionSnapshots: [1: .init(isConnected: false, kind: ReceiverLogicalDeviceKind.mouse.rawValue)],
            liveReachableSlots: []
        ))
        store.mergeDiscovery(.init(
            identities: [identity],
            connectionSnapshots: [:],
            liveReachableSlots: []
        ))

        XCTAssertTrue(store.currentPublishedIdentities().isEmpty)
    }

    func testConnectedBatteryDeviceDirectIdentityPrefersSerialNumber() {
        let identity = ConnectedBatteryDeviceInfo.directIdentity(
            vendorID: 0x046D,
            productID: 0x405E,
            serialNumber: "ABC123",
            locationID: 0x1000,
            transport: "USB",
            fallbackName: "Mouse"
        )

        XCTAssertEqual(identity, "serial|1133|16478|ABC123")
    }

    func testConnectedBatteryDeviceDirectIdentityFallsBackToLocation() {
        let identity = ConnectedBatteryDeviceInfo.directIdentity(
            vendorID: 0x046D,
            productID: 0x405E,
            serialNumber: nil,
            locationID: 0x2000,
            transport: "USB",
            fallbackName: "Mouse"
        )

        XCTAssertEqual(identity, "location|1133|16478|8192")
    }

    func testConnectedBatteryDeviceReceiverIdentityUsesReceiverAndSlot() {
        XCTAssertEqual(
            ConnectedBatteryDeviceInfo.receiverIdentity(receiverLocationID: 0x1234, slot: 2),
            "receiver|4660|2"
        )
    }

    func testVendorSpecificDeviceMetadataSupportsEquality() {
        XCTAssertEqual(
            VendorSpecificDeviceMetadata(name: "MX Master 3", batteryLevel: 50),
            VendorSpecificDeviceMetadata(name: "MX Master 3", batteryLevel: 50)
        )
        XCTAssertNotEqual(
            VendorSpecificDeviceMetadata(name: "MX Master 3", batteryLevel: 50),
            VendorSpecificDeviceMetadata(name: "MX Master 3", batteryLevel: 80)
        )
    }

    func testDeviceManagerDisplayNameUsesSinglePairedDeviceName() {
        let identities = [
            ReceiverLogicalDeviceIdentity(
                receiverLocationID: 1,
                slot: 1,
                kind: .mouse,
                name: "M720 Triathlon",
                serialNumber: nil,
                productID: nil,
                batteryLevel: 50
            )
        ]

        XCTAssertEqual(
            DeviceManager.displayName(baseName: "USB Receiver", pairedDevices: identities),
            "USB Receiver (M720 Triathlon)"
        )
    }

    func testDeviceManagerDisplayNameUsesDeviceCountForMultiplePairedDevices() {
        let identities = [
            ReceiverLogicalDeviceIdentity(
                receiverLocationID: 1,
                slot: 1,
                kind: .mouse,
                name: "Mouse A",
                serialNumber: nil,
                productID: nil,
                batteryLevel: 50
            ),
            ReceiverLogicalDeviceIdentity(
                receiverLocationID: 1,
                slot: 2,
                kind: .trackball,
                name: "Mouse B",
                serialNumber: nil,
                productID: nil,
                batteryLevel: 80
            )
        ]

        let expected = String(
            format: NSLocalizedString("%@ (%lld devices)", comment: ""),
            "USB Receiver",
            Int64(identities.count)
        )

        XCTAssertEqual(
            DeviceManager.displayName(baseName: "USB Receiver", pairedDevices: identities),
            expected
        )
    }
}

private struct MockVendorSpecificDeviceContext: VendorSpecificDeviceContext {
    var vendorID: Int?
    var productID: Int?
    var product: String?
    var name: String
    var serialNumber: String?
    var transport: String?
    var locationID: Int?
    var primaryUsagePage: Int?
    var primaryUsage: Int?
    var maxInputReportSize: Int?
    var maxOutputReportSize: Int?
    var maxFeatureReportSize: Int?

    init(
        vendorID: Int?,
        productID: Int?,
        product: String? = nil,
        name: String = "Mock Device",
        serialNumber: String? = nil,
        transport: String?,
        locationID: Int? = nil,
        primaryUsagePage: Int? = nil,
        primaryUsage: Int? = nil,
        maxInputReportSize: Int? = 20,
        maxOutputReportSize: Int? = 20,
        maxFeatureReportSize: Int? = 20
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.product = product
        self.name = name
        self.serialNumber = serialNumber
        self.transport = transport
        self.locationID = locationID
        self.primaryUsagePage = primaryUsagePage
        self.primaryUsage = primaryUsage
        self.maxInputReportSize = maxInputReportSize
        self.maxOutputReportSize = maxOutputReportSize
        self.maxFeatureReportSize = maxFeatureReportSize
    }

    func performSynchronousOutputReportRequest(
        _: Data,
        timeout _: TimeInterval,
        matching _: @escaping (Data) -> Bool
    ) -> Data? {
        nil
    }
}
