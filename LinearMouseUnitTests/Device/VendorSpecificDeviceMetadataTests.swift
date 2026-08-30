// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
@testable import LinearMouse
import PointerKit
import XCTest

final class VendorSpecificDeviceMetadataTests: XCTestCase {
    private final class TestSharedChannel {}
    private final class TestReceiverOwner {}
    private final class TestReceiverCandidate {
        var isValid = true
    }

    func testMatcherMatchesVendorAndTransport() {
        let matcher = VendorSpecificDeviceMatcher(
            vendorID: 0x046D,
            productIDs: [0xB015],
            transports: [PointerDeviceTransportName.bluetoothLowEnergy]
        )

        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: PointerDeviceTransportName.bluetoothLowEnergy
        )

        XCTAssertTrue(matcher.matches(device: device))
    }

    func testMatcherRejectsUnknownTransport() {
        let matcher = VendorSpecificDeviceMatcher(
            vendorID: 0x046D,
            productIDs: nil,
            transports: [PointerDeviceTransportName.usb]
        )

        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: PointerDeviceTransportName.bluetoothLowEnergy
        )

        XCTAssertFalse(matcher.matches(device: device))
    }

    func testLogitechProviderMatchesBluetoothLowEnergyDeviceShape() {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: PointerDeviceTransportName.bluetoothLowEnergy,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )

        XCTAssertTrue(provider.matches(device: device))
    }

    func testLogitechProviderMatchesUsbLogitechDeviceShape() {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            transport: PointerDeviceTransportName.usb,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )

        XCTAssertTrue(provider.matches(device: device))
    }

    func testLogitechReceiverMonitoringAllowsSupportedUnifyingReceiverProductIDs() {
        XCTAssertTrue(
            LogitechHIDPPDeviceMetadataProvider.supportsReceiverMonitoring(
                vendorID: 0x046D,
                productID: 0xC52B,
                transport: PointerDeviceTransportName.usb
            )
        )
        XCTAssertTrue(
            LogitechHIDPPDeviceMetadataProvider.supportsReceiverMonitoring(
                vendorID: 0x046D,
                productID: 0xC532,
                transport: PointerDeviceTransportName.usb
            )
        )
    }

    func testLogitechReceiverMonitoringAllowsSupportedBoltReceiverProductIDs() {
        XCTAssertTrue(
            LogitechHIDPPDeviceMetadataProvider.supportsReceiverMonitoring(
                vendorID: 0x046D,
                productID: 0xC548,
                transport: PointerDeviceTransportName.usb
            )
        )
        XCTAssertFalse(
            LogitechHIDPPDeviceMetadataProvider.supportsClassicReceiverMonitoring(
                vendorID: 0x046D,
                productID: 0xC548,
                transport: PointerDeviceTransportName.usb
            )
        )
    }

    func testLogitechReceiverMonitoringAllowsSupportedLightspeedReceiverProductIDs() {
        let productIDs = [
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

        for productID in productIDs {
            XCTAssertTrue(
                LogitechHIDPPDeviceMetadataProvider.supportsReceiverMonitoring(
                    vendorID: 0x046D,
                    productID: productID,
                    transport: PointerDeviceTransportName.usb
                )
            )
            XCTAssertEqual(
                LogitechHIDPPDeviceMetadataProvider.receiverProtocolFamily(
                    vendorID: 0x046D,
                    productID: productID,
                    transport: PointerDeviceTransportName.usb
                ),
                .lightspeed
            )
            XCTAssertFalse(
                LogitechHIDPPDeviceMetadataProvider.supportsClassicReceiverMonitoring(
                    vendorID: 0x046D,
                    productID: productID,
                    transport: PointerDeviceTransportName.usb
                )
            )
        }
    }

    func testLogitechReceiverMonitoringRejectsReceiversWithoutImplementedProtocolSupport() {
        XCTAssertFalse(
            LogitechHIDPPDeviceMetadataProvider.supportsReceiverMonitoring(
                vendorID: 0x046D,
                productID: 0xC52F,
                transport: PointerDeviceTransportName.usb
            )
        )
        XCTAssertFalse(
            LogitechHIDPPDeviceMetadataProvider.supportsReceiverMonitoring(
                vendorID: 0x046D,
                productID: 0xC52B,
                transport: PointerDeviceTransportName.bluetoothLowEnergy
            )
        )
    }

    func testLogitechKnownReceiverDetectionIncludesNanoReceivers() {
        XCTAssertTrue(
            LogitechHIDPPDeviceMetadataProvider.isKnownReceiver(
                vendorID: 0x046D,
                productID: 0xC52F
            )
        )
        XCTAssertTrue(
            LogitechHIDPPDeviceMetadataProvider.isKnownReceiver(
                vendorID: 0x046D,
                productID: 0xC548
            )
        )
        XCTAssertFalse(
            LogitechHIDPPDeviceMetadataProvider.isKnownReceiver(
                vendorID: 0x046D,
                productID: 0xB015
            )
        )
    }

    func testConnectedLogitechInventoryDoesNotQueryBluetoothLowEnergyDevices() {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            product: "Logi M650",
            name: "Logi M650",
            transport: PointerDeviceTransportName.bluetoothLowEnergy,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )

        let devices = ConnectedLogitechDeviceInventory.devices(from: [device])

        XCTAssertTrue(devices.isEmpty)
        XCTAssertEqual(device.outputReportRequestCount, 0)
    }

    func testConnectedLogitechInventoryDoesNotQueryKnownUsbReceivers() {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xC52F,
            product: "Logitech USB Device",
            name: "Logitech USB Device",
            transport: PointerDeviceTransportName.usb,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )

        let devices = ConnectedLogitechDeviceInventory.devices(from: [device])

        XCTAssertTrue(devices.isEmpty)
        XCTAssertEqual(device.outputReportRequestCount, 0)
    }

    func testConnectedLogitechInventoryDoesNotIssueHIDIOAfterDeadline() {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            product: "Logitech USB Device",
            name: "Logitech USB Device",
            transport: PointerDeviceTransportName.usb,
            locationID: 1,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )

        let devices = ConnectedLogitechDeviceInventory.devices(
            from: [device],
            deadline: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(devices.isEmpty)
        XCTAssertEqual(device.outputReportRequestCount, 0)
        XCTAssertEqual(device.outputReportRequestOnceCount, 0)
    }

    func testConnectedLogitechInventoryDoesNotIssueHIDIOAfterCancellation() {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB015,
            product: "Logitech USB Device",
            name: "Logitech USB Device",
            transport: PointerDeviceTransportName.usb,
            locationID: 1,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )

        let devices = ConnectedLogitechDeviceInventory.devices(from: [device]) { false }

        XCTAssertTrue(devices.isEmpty)
        XCTAssertEqual(device.outputReportRequestCount, 0)
        XCTAssertEqual(device.outputReportRequestOnceCount, 0)
    }

    func testLogitechControlsMonitorUsesReceiverAllowlistForUsbDevices() {
        XCTAssertTrue(
            LogitechReprogrammableControlsMonitor.supports(
                vendorID: 0x046D,
                productID: 0xC52B,
                transport: PointerDeviceTransportName.usb
            )
        )
        XCTAssertFalse(
            LogitechReprogrammableControlsMonitor.supports(
                vendorID: 0x046D,
                productID: 0xC539,
                transport: PointerDeviceTransportName.usb
            )
        )
        XCTAssertTrue(
            LogitechReprogrammableControlsMonitor.supports(
                vendorID: 0x046D,
                productID: 0xC548,
                transport: PointerDeviceTransportName.usb
            )
        )
        XCTAssertFalse(
            LogitechReprogrammableControlsMonitor.supports(
                vendorID: 0x046D,
                productID: 0xB015,
                transport: PointerDeviceTransportName.usb
            )
        )
        XCTAssertTrue(
            LogitechReprogrammableControlsMonitor.supports(
                vendorID: 0x046D,
                productID: 0xB015,
                transport: PointerDeviceTransportName.bluetoothLowEnergy
            )
        )
        XCTAssertFalse(
            LogitechReprogrammableControlsMonitor.supports(
                vendorID: 0x3554,
                productID: 0xC52B,
                transport: PointerDeviceTransportName.usb
            )
        )
    }

    func testBoltReceiverPairingInfoParserUsesBoltRegisterLayout() {
        let response: [UInt8] = [
            0x11, 0xFF, 0x83, 0xB5, 0x52, 0x02, 0x3E, 0xB0, 0xEF, 0x0F,
            0x42, 0x5B, 0x02, 0x01, 0x80, 0x14, 0x01, 0x00, 0x00, 0x00
        ]

        XCTAssertEqual(LogitechReceiverChannel.parseBoltReceiverKind(response), 0x02)
        XCTAssertEqual(LogitechReceiverChannel.parseBoltReceiverProductID(response), 0xB03E)
        XCTAssertEqual(LogitechReceiverChannel.parseBoltReceiverSerialNumber(response), "EF0F425B")
    }

    func testClassicReceiverSerialParserUsesR1ThroughR4WithoutCollidingOnReportTypes() {
        let first: [UInt8] = [
            0x11, 0xFF, 0x83, 0xB5, 0x30,
            0x12, 0x34, 0x56, 0x78, // r1...r4: serial
            0xAB, 0xCD, 0x00, 0x00
        ]
        var second = first
        second[5] = 0x13

        XCTAssertEqual(LogitechReceiverChannel.parseReceiverSerialNumber(first), "12345678")
        XCTAssertEqual(LogitechReceiverChannel.parseReceiverSerialNumber(second), "13345678")
        XCTAssertNotEqual(
            LogitechReceiverChannel.parseReceiverSerialNumber(first),
            LogitechReceiverChannel.parseReceiverSerialNumber(second)
        )
    }

    func testReceiverSerialParsersRejectMissingIdentitySentinels() {
        let classicPrefix: [UInt8] = [0x11, 0xFF, 0x83, 0xB5, 0x30]
        XCTAssertNil(LogitechReceiverChannel.parseReceiverSerialNumber(
            classicPrefix + [0x00, 0x00, 0x00, 0x00, 0xAA]
        ))
        XCTAssertNil(LogitechReceiverChannel.parseReceiverSerialNumber(
            classicPrefix + [0xFF, 0xFF, 0xFF, 0xFF, 0xAA]
        ))

        let boltPrefix: [UInt8] = [0x11, 0xFF, 0x83, 0xB5, 0x52, 0x02, 0x3E, 0xB0]
        XCTAssertNil(LogitechReceiverChannel.parseBoltReceiverSerialNumber(
            boltPrefix + [0x00, 0x00, 0x00, 0x00]
        ))
        XCTAssertNil(LogitechReceiverChannel.parseBoltReceiverSerialNumber(
            boltPrefix + [0xFF, 0xFF, 0xFF, 0xFF]
        ))
    }

    func testBoltReceiverNameParserUsesAvailableNameFragment() {
        let response: [UInt8] = [
            0x11, 0xFF, 0x83, 0xB5, 0x62, 0x01, 0x0E, 0x4D, 0x58, 0x20,
            0x45, 0x72, 0x67, 0x6F, 0x20, 0x53, 0x20, 0x50, 0x6C, 0x75
        ]

        XCTAssertEqual(LogitechReceiverChannel.parseBoltReceiverName(response), "MX Ergo S Plu")
    }

    func testBoltReceiverParsersRejectShortResponses() {
        XCTAssertNil(LogitechReceiverChannel.parseBoltReceiverKind([0x11, 0xFF, 0x83]))
        XCTAssertNil(LogitechReceiverChannel.parseBoltReceiverProductID([0x11, 0xFF, 0x83]))
        XCTAssertNil(LogitechReceiverChannel.parseBoltReceiverSerialNumber([0x11, 0xFF, 0x83]))
        XCTAssertNil(LogitechReceiverChannel.parseBoltReceiverName([0x11, 0xFF, 0x83]))
    }

    func testBoltReceiverDiscoveryEnablesNotificationsAndTriggersOneInitialSnapshot() throws {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xC548,
            transport: PointerDeviceTransportName.usb,
            locationID: 1
        )
        device.queuedHIDPPNotifications = [
            [0x10, 0x01, 0x41, 0x00, ReceiverLogicalDeviceKind.mouse.rawValue, 0x00, 0x00]
        ]
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            guard bytes.count >= 4 else {
                return nil
            }

            switch (bytes[2], bytes[3]) {
            case (0x83, 0xFB):
                return Data([0x10, 0xFF, 0x83, 0xFB, 0x00, 0x00, 0x00])
            case (0x81, 0x02):
                return Data([0x10, 0xFF, 0x81, 0x02, 0x00, 0x01, 0x00])
            case (0x80, 0x02):
                return Data([0x10, 0xFF, 0x80, 0x02, 0x02, 0x00, 0x00])
            default:
                return nil
            }
        }

        let discovery = try XCTUnwrap(device.discoverBoltSlots())
        XCTAssertTrue(discovery.slots.isEmpty)
        XCTAssertEqual(discovery.expectedConnectedDeviceCount, 1)
        XCTAssertTrue(discovery.inventoryAvailable)
        XCTAssertEqual(
            discovery.connectionSnapshots[1],
            .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        )
        XCTAssertEqual(device.wirelessNotificationEnableCount, 1)
        XCTAssertEqual(
            device.sentReports
                .filter { report in
                    let bytes = [UInt8](report)
                    return bytes.count >= 5
                        && bytes[2] == 0x80
                        && bytes[3] == 0x02
                        && bytes[4] == 0x02
                }
                .count,
            1
        )
    }

    func testBoltReceiverConnectionWaitRetriesNotificationEnableWithoutTriggeringSnapshot() {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xC548,
            transport: PointerDeviceTransportName.usb,
            locationID: 1
        )
        device.queuedHIDPPNotifications = [
            [0x10, 0x01, 0x41, 0x00, 0x02, 0x00, 0x00]
        ]

        let snapshots = device.waitForBoltConnectionSnapshots(timeout: 0.1)
        let secondSnapshots = device.waitForBoltConnectionSnapshots(timeout: 0)

        XCTAssertEqual(snapshots.snapshots[1], .init(isConnected: true, kind: 0x02))
        XCTAssertTrue(secondSnapshots.snapshots.isEmpty)
        XCTAssertEqual(device.wirelessNotificationEnableCount, 2)
        XCTAssertEqual(device.outputReportRequestCount, 0)
        XCTAssertTrue(device.sentReports.isEmpty)
    }

    func testLogitechControlsMonitorNeedsMatchingDirectBluetoothLowEnergyConfiguration() {
        var mapping = Scheme.Buttons.Mapping()
        mapping.button = .logitechControl(.init(controlID: 0x00D0, productID: 0xB015, serialNumber: "ABC"))
        var buttons = Scheme.Buttons()
        buttons.mappings = [mapping]
        var configuration = Configuration()
        configuration.schemes = [Scheme(buttons: buttons)]

        let matchingIdentity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 1,
            slot: 0,
            kind: .mouse,
            name: "M720",
            serialNumber: "abc",
            productID: 0xB015,
            batteryLevel: nil
        )
        let otherIdentity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 2,
            slot: 0,
            kind: .mouse,
            name: "M650",
            serialNumber: "DEF",
            productID: 0xB02A,
            batteryLevel: nil
        )

        XCTAssertTrue(
            LogitechReprogrammableControlsMonitor.isNeeded(
                configuration: configuration,
                identity: matchingIdentity
            )
        )
        XCTAssertFalse(
            LogitechReprogrammableControlsMonitor.isNeeded(
                configuration: configuration,
                identity: otherIdentity
            )
        )
    }

    func testLogitechControlsMonitorFindsControlsInStructuredTriggers() {
        let control = LogitechControlIdentity(controlID: 0x00D0, productID: 0xB015, serialNumber: "ABC")
        let mapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .wheel(.up), whileHeld: [.logitechControl(control)]),
            action: .arg0(.none)
        )
        let configuration = Configuration(schemes: [
            Scheme(buttons: .init(mappings: [mapping]))
        ])
        let identity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 1,
            slot: 0,
            kind: .mouse,
            name: "M720",
            serialNumber: "abc",
            productID: 0xB015,
            batteryLevel: nil
        )

        XCTAssertTrue(LogitechReprogrammableControlsMonitor.isNeeded(
            configuration: configuration,
            identity: identity
        ))
    }

    func testLogitechControlsMonitorCanFallbackToProductWhenDirectBluetoothSerialIsMissing() {
        var mapping = Scheme.Buttons.Mapping()
        mapping.button = .logitechControl(.init(controlID: 0x00D0, productID: 0xB015, serialNumber: "ABC"))
        var buttons = Scheme.Buttons()
        buttons.mappings = [mapping]
        var configuration = Configuration()
        configuration.schemes = [Scheme(buttons: buttons)]

        let identityWithoutSerial = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 1,
            slot: 0,
            kind: .mouse,
            name: "M720",
            serialNumber: nil,
            productID: 0xB015,
            batteryLevel: nil
        )
        let identityWithoutProduct = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 1,
            slot: 0,
            kind: .mouse,
            name: "M720",
            serialNumber: nil,
            productID: nil,
            batteryLevel: nil
        )

        XCTAssertFalse(
            LogitechReprogrammableControlsMonitor.isNeeded(
                configuration: configuration,
                identity: identityWithoutSerial
            )
        )
        XCTAssertTrue(
            LogitechReprogrammableControlsMonitor.isNeeded(
                configuration: configuration,
                identity: identityWithoutSerial,
                allowsIdentityFallback: true
            )
        )
        XCTAssertFalse(
            LogitechReprogrammableControlsMonitor.isNeeded(
                configuration: configuration,
                identity: identityWithoutProduct,
                allowsIdentityFallback: true
            )
        )
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

    func testReceiverReconnectPublicationRequiresRouteLossOnlyForPointingReconnects() throws {
        let mouse = receiverIdentity(slot: 1, name: "Mouse A")
        let pointing = [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot](
            uniqueKeysWithValues: [(1, .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue))]
        )
        let keyboard = [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot](
            uniqueKeysWithValues: [(2, .init(isConnected: true, kind: ReceiverLogicalDeviceKind.keyboard.rawValue))]
        )

        XCTAssertTrue(ReceiverReconnectPublication.requiresRouteLoss(
            reconnectedSlots: [1], snapshots: pointing, currentIdentities: []
        ))
        XCTAssertFalse(ReceiverReconnectPublication.requiresRouteLoss(
            reconnectedSlots: [], snapshots: pointing, currentIdentities: [mouse]
        ))
        XCTAssertFalse(ReceiverReconnectPublication.requiresRouteLoss(
            reconnectedSlots: [2], snapshots: keyboard, currentIdentities: []
        ))
        XCTAssertTrue(ReceiverReconnectPublication.requiresRouteLoss(
            reconnectedSlots: [1], snapshots: [1: .init(isConnected: true, kind: nil)], currentIdentities: [mouse]
        ))
        XCTAssertTrue(try ReceiverReconnectPublication.requiresRouteLoss(
            reconnectedSlots: [1, 2], snapshots: [1: XCTUnwrap(pointing[1]), 2: XCTUnwrap(keyboard[2])],
            currentIdentities: []
        ))
    }

    func testStoppedWorkerCannotInvalidateChannelAfterSlowLightspeedProbe() {
        var running = true
        var invalidatedChannel = false

        let probe = ReceiverWorkerPostCallAdmission.admit {
            running = false
            return false
        } whileRunning: {
            running
        }
        if let probe, !probe.value {
            invalidatedChannel = true
        }

        XCTAssertNil(probe)
        XCTAssertFalse(invalidatedChannel)
    }

    func testStoppedWorkerCannotPublishOrInvalidateAfterSlowPendingDiscovery() {
        var running = true
        var mutatedReceiverState = false

        let discovery = ReceiverWorkerPostCallAdmission.admit {
            running = false
            return LogitechHIDPPDeviceMetadataProvider.ReceiverPointingDeviceDiscovery(
                identities: [],
                connectionSnapshots: [:],
                liveReachableSlots: [],
                inventoryAvailable: false
            )
        } whileRunning: {
            running
        }
        if let discovery, !discovery.value.inventoryAvailable {
            mutatedReceiverState = true
        }

        XCTAssertNil(discovery)
        XCTAssertFalse(mutatedReceiverState)
    }

    func testDetachedOldChannelCannotClaimReplacementOwnership() {
        let oldChannel = TestSharedChannel()
        let newChannel = TestSharedChannel()
        var currentChannel: TestSharedChannel? = oldChannel

        XCTAssertTrue(SharedChannelOwnership.detach(oldChannel, from: &currentChannel))
        currentChannel = newChannel
        XCTAssertFalse(SharedChannelOwnership.detach(oldChannel, from: &currentChannel))
        XCTAssertIdentical(currentChannel, newChannel)
    }

    func testStoppedReceiverWorkerCannotAdoptOpenedChannel() {
        let channel = TestSharedChannel()
        var currentChannel: TestSharedChannel?

        XCTAssertFalse(ReceiverWorkerChannelAdoption.adopt(
            channel,
            whileRunning: false,
            currentChannel: &currentChannel
        ))
        XCTAssertNil(currentChannel)
    }

    func testRunningReceiverWorkerOnlyAdoptsIntoEmptyChannelSlot() {
        let existingChannel = TestSharedChannel()
        let replacementChannel = TestSharedChannel()
        var currentChannel: TestSharedChannel?

        XCTAssertTrue(ReceiverWorkerChannelAdoption.adopt(
            existingChannel,
            whileRunning: true,
            currentChannel: &currentChannel
        ))
        XCTAssertIdentical(currentChannel, existingChannel)
        XCTAssertFalse(ReceiverWorkerChannelAdoption.adopt(
            replacementChannel,
            whileRunning: true,
            currentChannel: &currentChannel
        ))
        XCTAssertIdentical(currentChannel, existingChannel)
    }

    func testReceiverHandoffIgnoresDuplicateStartWhileActive() {
        var handoff = ReceiverMonitorHandoff<TestReceiverOwner, TestReceiverCandidate>()
        let owner = TestReceiverOwner()
        let first = TestReceiverCandidate()
        let duplicate = TestReceiverCandidate()

        XCTAssertTrue(handoff.requestStart(first))
        XCTAssertTrue(handoff.activate(owner, for: first))
        XCTAssertFalse(handoff.requestStart(duplicate))
        XCTAssertIdentical(handoff.activeOwner, owner)
    }

    func testReceiverHandoffDefersStartUntilOwnerDidStop() {
        var handoff = ReceiverMonitorHandoff<TestReceiverOwner, TestReceiverCandidate>()
        let oldOwner = TestReceiverOwner()
        let newOwner = TestReceiverOwner()
        let oldCandidate = TestReceiverCandidate()
        let pending = TestReceiverCandidate()
        var startCount = 0

        XCTAssertTrue(handoff.requestStart(oldCandidate))
        XCTAssertTrue(handoff.activate(oldOwner, for: oldCandidate))
        XCTAssertIdentical(handoff.requestStop(for: oldCandidate), oldOwner)
        XCTAssertFalse(handoff.requestStart(pending))
        XCTAssertNil(handoff.activeOwner)

        let admitted = handoff.didStop(oldOwner) { $0.isValid }
        XCTAssertIdentical(admitted, pending)
        if let admitted, handoff.requestStart(admitted) {
            startCount += 1
            XCTAssertTrue(handoff.activate(newOwner, for: admitted))
        }

        XCTAssertEqual(startCount, 1)
        XCTAssertIdentical(handoff.activeOwner, newOwner)
    }

    func testReceiverHandoffClearsPendingWhenNewLifecycleStops() {
        var handoff = ReceiverMonitorHandoff<TestReceiverOwner, TestReceiverCandidate>()
        let oldOwner = TestReceiverOwner()
        let oldCandidate = TestReceiverCandidate()
        let pending = TestReceiverCandidate()

        XCTAssertTrue(handoff.requestStart(oldCandidate))
        XCTAssertTrue(handoff.activate(oldOwner, for: oldCandidate))
        XCTAssertIdentical(handoff.requestStop(for: oldCandidate), oldOwner)
        XCTAssertFalse(handoff.requestStart(pending))
        XCTAssertNil(handoff.requestStop(for: pending))
        XCTAssertNil(handoff.didStop(oldOwner) { $0.isValid })
        XCTAssertTrue(handoff.isEmpty)
    }

    func testReceiverHandoffTerminalStopClearsPendingAndReturnsOwnerOnce() {
        var handoff = ReceiverMonitorHandoff<TestReceiverOwner, TestReceiverCandidate>()
        let owner = TestReceiverOwner()
        let active = TestReceiverCandidate()
        let pending = TestReceiverCandidate()

        XCTAssertTrue(handoff.requestStart(active))
        XCTAssertTrue(handoff.activate(owner, for: active))
        XCTAssertIdentical(handoff.requestStop(for: active), owner)
        XCTAssertIdentical(handoff.currentOwner, owner)
        XCTAssertFalse(handoff.requestStart(pending))

        // The producer is already stopping, so terminal stop only discards
        // its queued replacement and never asks the caller to stop it twice.
        XCTAssertNil(handoff.requestTerminalStop())
        XCTAssertNil(handoff.didStop(owner) { $0.isValid })
        XCTAssertTrue(handoff.isEmpty)
        XCTAssertNil(handoff.currentOwner)
    }

    func testReceiverHandoffTerminalStopOwnsActiveProducer() {
        var handoff = ReceiverMonitorHandoff<TestReceiverOwner, TestReceiverCandidate>()
        let owner = TestReceiverOwner()
        let active = TestReceiverCandidate()

        XCTAssertTrue(handoff.requestStart(active))
        XCTAssertTrue(handoff.activate(owner, for: active))
        XCTAssertIdentical(handoff.currentOwner, owner)
        XCTAssertIdentical(handoff.requestTerminalStop(), owner)
        XCTAssertNil(handoff.requestTerminalStop())
        XCTAssertNil(handoff.didStop(owner) { $0.isValid })
        XCTAssertTrue(handoff.isEmpty)
    }

    func testReceiverHandoffSelectsLiveCandidateFromSharedLocation() {
        var handoff = ReceiverMonitorHandoff<TestReceiverOwner, TestReceiverCandidate>()
        let oldOwner = TestReceiverOwner()
        let oldCandidate = TestReceiverCandidate()
        let removedCandidate = TestReceiverCandidate()
        let liveCandidate = TestReceiverCandidate()

        XCTAssertTrue(handoff.requestStart(oldCandidate))
        XCTAssertTrue(handoff.activate(oldOwner, for: oldCandidate))
        XCTAssertIdentical(handoff.requestStop(for: oldCandidate), oldOwner)
        XCTAssertFalse(handoff.requestStart(removedCandidate))
        XCTAssertFalse(handoff.requestStart(liveCandidate))
        removedCandidate.isValid = false

        XCTAssertIdentical(
            handoff.didStop(oldOwner) { $0.isValid },
            liveCandidate
        )
    }

    func testReceiverHandoffIgnoresStaleDidStopAfterReplacementStarts() {
        var handoff = ReceiverMonitorHandoff<TestReceiverOwner, TestReceiverCandidate>()
        let oldOwner = TestReceiverOwner()
        let newOwner = TestReceiverOwner()
        let oldCandidate = TestReceiverCandidate()
        let newCandidate = TestReceiverCandidate()

        XCTAssertTrue(handoff.requestStart(oldCandidate))
        XCTAssertTrue(handoff.activate(oldOwner, for: oldCandidate))
        XCTAssertIdentical(handoff.requestStop(for: oldCandidate), oldOwner)
        XCTAssertFalse(handoff.requestStart(newCandidate))
        XCTAssertIdentical(handoff.didStop(oldOwner) { $0.isValid }, newCandidate)
        XCTAssertTrue(handoff.requestStart(newCandidate))
        XCTAssertTrue(handoff.activate(newOwner, for: newCandidate))

        XCTAssertNil(handoff.didStop(oldOwner) { $0.isValid })
        XCTAssertIdentical(handoff.activeOwner, newOwner)
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
                [0x10, 0x02, 0x05, 0x00, 0x00, 0xC3, 0x00],
                featureIndex: 0x05,
                deviceIndices: Set([0x02])
            )
        )
    }

    func testLogitechDivertedButtonsNotificationAcceptsDirectBluetoothIndices() {
        for deviceIndex in LogitechHIDPPDeviceMetadataProvider.Constants.directReplyIndices {
            XCTAssertTrue(
                LogitechReprogrammableControlsMonitor.isDivertedButtonsNotification(
                    [0x10, deviceIndex, 0x05, 0x00, 0x00, 0xD0, 0x00],
                    featureIndex: 0x05,
                    deviceIndices: LogitechHIDPPDeviceMetadataProvider.Constants.directReplyIndices
                )
            )
        }
    }

    func testLogitechDivertedButtonsNotificationParsesPressedControls() {
        XCTAssertEqual(
            LogitechReprogrammableControlsMonitor.parseDivertedButtonsNotification([
                0x10,
                0x02,
                0x05,
                0x00,
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
                [0x10, 0x03, 0x05, 0x00, 0x00, 0xC3, 0x00],
                featureIndex: 0x05,
                deviceIndices: Set([0x02])
            )
        )
    }

    func testLogitechDivertedButtonsNotificationRejectsCommandResponse() {
        XCTAssertFalse(
            LogitechReprogrammableControlsMonitor.isDivertedButtonsNotification(
                [0x10, 0x02, 0x05, 0x08, 0x00, 0xC3, 0x00],
                featureIndex: 0x05,
                deviceIndices: Set([0x02])
            )
        )
    }

    func testLogitechGestureButtonControlIDsIncludeM720ThumbButton() {
        XCTAssertTrue(LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.gestureButtonControlIDs.contains(0x00D0))
    }

    func testLogitechGestureButtonTaskIDsIncludeM720GestureTasks() {
        XCTAssertTrue(LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.gestureButtonTaskIDs.contains(0x00AD))
        XCTAssertTrue(LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.gestureButtonTaskIDs.contains(0x00A9))
    }

    func testLogitechVirtualControlsUseReservedVirtualButtonNumber() {
        XCTAssertEqual(
            LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.reservedVirtualButtonNumber,
            0x1000
        )
    }

    func testLogitechSyntheticFallbackDefersGestureClickUntilRelease() {
        var coordinator = LogitechSyntheticFallbackCoordinator()
        let controlIdentity = LogitechControlIdentity(controlID: 0x00D0, productID: 0xB015, serialNumber: "ABC")

        XCTAssertEqual(
            coordinator.action(
                for: controlIdentity,
                isPressed: true,
                handlingResult: .handledDeferringSyntheticFallback
            ),
            .suppress
        )
        XCTAssertEqual(
            coordinator.action(for: controlIdentity, isPressed: false, handlingResult: .notHandled),
            .postClick
        )
    }

    func testLogitechSyntheticFallbackPostsDeferredClickAfterHandledFallbackRelease() {
        var coordinator = LogitechSyntheticFallbackCoordinator()
        let controlIdentity = LogitechControlIdentity(controlID: 0x00D0, productID: 0xB015, serialNumber: "ABC")

        _ = coordinator.action(
            for: controlIdentity,
            isPressed: true,
            handlingResult: .handledDeferringSyntheticFallback
        )

        XCTAssertEqual(
            coordinator.action(
                for: controlIdentity,
                isPressed: false,
                handlingResult: .handledAllowingSyntheticFallback
            ),
            .postClick
        )
    }

    func testLogitechSyntheticFallbackCancelsDeferredClickWhenGestureHandlesRelease() {
        var coordinator = LogitechSyntheticFallbackCoordinator()
        let controlIdentity = LogitechControlIdentity(controlID: 0x00D0, productID: 0xB015, serialNumber: "ABC")

        _ = coordinator.action(
            for: controlIdentity,
            isPressed: true,
            handlingResult: .handledDeferringSyntheticFallback
        )

        XCTAssertEqual(
            coordinator.action(for: controlIdentity, isPressed: false, handlingResult: .handled),
            .suppress
        )
    }

    func testLogitechSyntheticFallbackSeparatesDeferredClicksByIdentity() {
        var coordinator = LogitechSyntheticFallbackCoordinator()
        let firstControl = LogitechControlIdentity(controlID: 0x00D0, productID: 0xB015, serialNumber: "ABC")
        let secondControl = LogitechControlIdentity(controlID: 0x00D0, productID: 0xB015, serialNumber: "DEF")

        _ = coordinator.action(
            for: firstControl,
            isPressed: true,
            handlingResult: .handledDeferringSyntheticFallback
        )

        XCTAssertEqual(
            coordinator.action(for: secondControl, isPressed: true, handlingResult: .notHandled),
            .postCurrentEvent
        )
        XCTAssertEqual(
            coordinator.action(for: secondControl, isPressed: false, handlingResult: .notHandled),
            .postCurrentEvent
        )
        XCTAssertEqual(
            coordinator.action(for: firstControl, isPressed: false, handlingResult: .notHandled),
            .postClick
        )
    }

    func testLogitechMonitorDefersReconfigurationUntilControlsAreReleased() {
        var request = LogitechMonitorReconfigurationRequest()
        request.request()

        let whilePressed = request.consume(deferringWhileControlsArePressed: true)
        XCTAssertFalse(whilePressed.needed)
        XCTAssertFalse(whilePressed.forced)

        let afterRelease = request.consume(deferringWhileControlsArePressed: false)
        XCTAssertTrue(afterRelease.needed)
        XCTAssertFalse(afterRelease.forced)

        XCTAssertFalse(request.consume(deferringWhileControlsArePressed: false).needed)
    }

    func testLogitechMonitorDoesNotDeferForcedReconfiguration() {
        var request = LogitechMonitorReconfigurationRequest()
        request.request(forced: true)

        let result = request.consume(deferringWhileControlsArePressed: true)
        XCTAssertTrue(result.needed)
        XCTAssertTrue(result.forced)
    }

    func testLogitechControlIdentityProvidesFriendlyUserVisibleName() {
        XCTAssertEqual(
            LogitechControlIdentity(controlID: 0x00D0, productID: nil, serialNumber: nil)
                .userVisibleName,
            "Logitech Control 0x00D0"
        )
        XCTAssertEqual(
            LogitechControlIdentity(controlID: 0x1234, productID: nil, serialNumber: nil)
                .userVisibleName,
            "Logitech Control 0x1234"
        )
    }

    func testLogitechControlIdentityFallbackOnlyUsesProductWhenSerialIsMissing() {
        let configured = LogitechControlIdentity(controlID: 0x00D0, productID: 0xB015, serialNumber: "ABC")

        XCTAssertTrue(
            LogitechControlIdentity(controlID: 0x00D0, productID: 0xB015, serialNumber: nil)
                .matches(configured, allowingIdentityFallback: true)
        )
        XCTAssertFalse(
            LogitechControlIdentity(controlID: 0x00D0, productID: 0xB02A, serialNumber: nil)
                .matches(configured, allowingIdentityFallback: true)
        )
        XCTAssertFalse(
            LogitechControlIdentity(controlID: 0x00D0, productID: nil, serialNumber: nil)
                .matches(configured, allowingIdentityFallback: true)
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

    func testReceiverSlotStateStoreClearsIdentityOnReconnectAndAllowsRefresh() {
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

        // After disconnect→connect transition, identity is cleared for refresh
        store.mergeConnectionSnapshots([
            1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ])
        XCTAssertTrue(store.needsIdentityRefresh(slot: 1))
        XCTAssertEqual(store.currentPublishedIdentities(), [])

        // After refresh, identity is restored
        store.updateSlotIdentity(identity)
        XCTAssertFalse(store.needsIdentityRefresh(slot: 1))
        XCTAssertEqual(store.currentPublishedIdentities(), [identity])
    }

    func testReceiverSlotStateStoreKeepsDiscoveryPendingAfterReconnectIdentityRefreshFails() {
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

        // The immediate slot read failed, so the pending discovery path must
        // retry rather than treating the remaining receiver state as ready.
        XCTAssertTrue(store.hasUnresolvedConnectedSlot)
        XCTAssertTrue(store.currentPublishedIdentities().isEmpty)

        store.mergeDiscovery(.init(identities: [identity], connectionSnapshots: [
            1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ], liveReachableSlots: [1]))

        XCTAssertFalse(store.hasUnresolvedConnectedSlot)
        XCTAssertEqual(store.currentPublishedIdentities(), [identity])
    }

    func testReceiverSlotStateStoreDoesNotRequireIdentityForConnectedKeyboard() {
        var store = ReceiverSlotStateStore()
        let mouse = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 0x1234,
            slot: 2,
            kind: .mouse,
            name: "Mouse A",
            serialNumber: "AAAA",
            productID: 0x1234,
            batteryLevel: 60
        )

        store.mergeDiscovery(.init(identities: [mouse], connectionSnapshots: [
            1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.keyboard.rawValue),
            2: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ], liveReachableSlots: [2]))

        XCTAssertFalse(store.hasUnresolvedConnectedSlot)
        XCTAssertEqual(store.currentPublishedIdentities(), [mouse])
    }

    func testReceiverSlotStateStoreUsesPriorPointingIdentityWhenReconnectKindIsUnknown() {
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
            1: .init(isConnected: false, kind: nil)
        ], liveReachableSlots: []))
        store.mergeConnectionSnapshots([
            1: .init(isConnected: true, kind: nil)
        ])

        XCTAssertTrue(store.hasUnresolvedConnectedSlot)

        store.updateSlotIdentity(identity)

        XCTAssertFalse(store.hasUnresolvedConnectedSlot)
    }

    func testReceiverSlotStateStoreKeepsRepeatedConnectedPointingIdentityResolved() {
        var store = ReceiverSlotStateStore()
        let identity = receiverIdentity(slot: 1, name: "Mouse A")

        store.mergeDiscovery(.init(identities: [identity], connectionSnapshots: [
            1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ], liveReachableSlots: [1]))
        store.mergeConnectionSnapshots([
            1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ])

        XCTAssertFalse(store.hasUnresolvedConnectedSlot)
        XCTAssertEqual(store.currentPublishedIdentities(), [identity])
    }

    func testReceiverSlotStateStoreClearsIdentityForCoalescedReconnectBatch() {
        var store = ReceiverSlotStateStore()
        let identity = receiverIdentity(slot: 1, name: "Mouse A")

        store.mergeDiscovery(.init(identities: [identity], connectionSnapshots: [
            1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ], liveReachableSlots: [1]))
        store.mergeConnectionSnapshots(
            [1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)],
            reconnectedSlots: [1]
        )

        XCTAssertTrue(store.hasUnresolvedConnectedSlot)
        XCTAssertTrue(store.currentPublishedIdentities().isEmpty)
    }

    func testReceiverSlotStateStoreTreatsUnsupportedEventKindAsUnresolved() {
        var store = ReceiverSlotStateStore()
        let identity = receiverIdentity(slot: 1, name: "Mouse A")

        store.mergeDiscovery(.init(identities: [identity], connectionSnapshots: [
            1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ], liveReachableSlots: [1]))
        store.mergeConnectionSnapshots([1: .init(isConnected: true, kind: 0x06)])

        XCTAssertTrue(store.hasUnresolvedConnectedSlot)
        XCTAssertTrue(store.currentPublishedIdentities().isEmpty)
    }

    func testReceiverSlotStateStoreUsesExistingIdentityForUnknownEventMarkerAndClearsPresenter() {
        var store = ReceiverSlotStateStore()
        let identity = receiverIdentity(slot: 1, name: "Mouse A")

        store.mergeDiscovery(.init(identities: [identity], connectionSnapshots: [
            1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ], liveReachableSlots: [1]))
        store.mergeConnectionSnapshots([1: .init(isConnected: true, kind: 0)])
        XCTAssertFalse(store.hasUnresolvedConnectedSlot)
        XCTAssertEqual(store.currentPublishedIdentities(), [identity])

        store.mergeConnectionSnapshots([
            1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.presenter.rawValue)
        ])
        XCTAssertFalse(store.hasUnresolvedConnectedSlot)
        XCTAssertTrue(store.currentPublishedIdentities().isEmpty)
    }

    func testReceiverSlotStateStoreTreatsNewUnknownConnectedSlotAsUnresolved() {
        var store = ReceiverSlotStateStore()

        store.mergeConnectionSnapshots([
            1: .init(isConnected: true, kind: nil)
        ])

        XCTAssertTrue(store.hasUnresolvedConnectedSlot)
    }

    func testReceiverConnectionEventPublicationSuppressesPartialIdentitiesWhenUnresolved() {
        let identity = receiverIdentity(slot: 1, name: "Mouse A")

        XCTAssertEqual(
            ReceiverConnectionEventPublication.identities(
                afterEvent: [identity],
                hasUnresolvedConnectedSlot: true
            ),
            []
        )
    }

    func testReceiverSlotStateStoreRetriesPartialDiscoveryMissingConnectedPointingSlot() {
        var store = ReceiverSlotStateStore()
        let mouseA = receiverIdentity(slot: 1, name: "Mouse A")
        let mouseB = receiverIdentity(slot: 2, name: "Mouse B")

        store.mergeDiscovery(.init(identities: [mouseA, mouseB], connectionSnapshots: [
            1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue),
            2: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ], liveReachableSlots: [1, 2], expectedConnectedDeviceCount: 2, observedSlotKinds: [
            1: ReceiverLogicalDeviceKind.mouse.rawValue,
            2: ReceiverLogicalDeviceKind.mouse.rawValue
        ]))

        // Slot A's metadata read was transiently absent while B succeeded.
        let partial = store.mergeDiscovery(.init(identities: [mouseB], connectionSnapshots: [
            1: .init(isConnected: true, kind: nil),
            2: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ], liveReachableSlots: [2], expectedConnectedDeviceCount: 2, observedSlotKinds: [
            2: ReceiverLogicalDeviceKind.mouse.rawValue
        ]))

        XCTAssertFalse(partial.inventoryComplete)
        XCTAssertFalse(store.hasUnresolvedConnectedSlot)
        XCTAssertEqual(store.currentPublishedIdentities(), [mouseB])

        let recovered = store.mergeDiscovery(.init(identities: [mouseA, mouseB], connectionSnapshots: [
            1: .init(isConnected: true, kind: nil),
            2: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ], liveReachableSlots: [1, 2], expectedConnectedDeviceCount: 2, observedSlotKinds: [
            1: ReceiverLogicalDeviceKind.mouse.rawValue,
            2: ReceiverLogicalDeviceKind.mouse.rawValue
        ]))

        XCTAssertTrue(recovered.inventoryComplete)
        XCTAssertFalse(store.hasUnresolvedConnectedSlot)
        XCTAssertEqual(store.currentPublishedIdentities(), [mouseA, mouseB])
    }

    func testReceiverSlotStateStoreDoesNotRetryPartialDiscoveryWhenMissingSlotIsKeyboard() {
        var store = ReceiverSlotStateStore()
        let mouse = receiverIdentity(slot: 1, name: "Mouse A")

        store.mergeDiscovery(.init(identities: [mouse], connectionSnapshots: [
            1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ], liveReachableSlots: [1]))
        store.mergeDiscovery(.init(
            identities: [],
            connectionSnapshots: [1: .init(isConnected: true, kind: nil)],
            liveReachableSlots: [],
            observedSlotKinds: [1: ReceiverLogicalDeviceKind.keyboard.rawValue]
        ))

        XCTAssertFalse(store.hasUnresolvedConnectedSlot)
        XCTAssertTrue(store.currentPublishedIdentities().isEmpty)
    }

    func testReceiverSlotStateStoreRetriesPartialDiscoveryWithoutSnapshotWhenPreviouslyConnected() {
        var store = ReceiverSlotStateStore()
        let mouse = receiverIdentity(slot: 1, name: "Mouse A")

        store.mergeDiscovery(.init(identities: [mouse], connectionSnapshots: [
            1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ], liveReachableSlots: [1]))
        let result = store.mergeDiscovery(.init(
            identities: [],
            connectionSnapshots: [:],
            liveReachableSlots: [],
            expectedConnectedDeviceCount: nil
        ))

        XCTAssertFalse(result.inventoryComplete)
    }

    func testReceiverSlotStateStoreRetriesObservedConnectedPointingSlotWithoutIdentity() {
        var store = ReceiverSlotStateStore()
        let mouse = receiverIdentity(slot: 1, name: "Mouse A")

        store.mergeDiscovery(.init(identities: [mouse], connectionSnapshots: [
            1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
        ], liveReachableSlots: [1]))
        store.mergeDiscovery(.init(
            identities: [],
            connectionSnapshots: [1: .init(isConnected: true, kind: nil)],
            liveReachableSlots: [1],
            observedSlotKinds: [1: ReceiverLogicalDeviceKind.mouse.rawValue]
        ))

        XCTAssertTrue(store.hasUnresolvedConnectedSlot)
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
        store.mergeDiscovery(.init(
            identities: [reconnectedIdentity],
            connectionSnapshots: [:],
            liveReachableSlots: [1],
            expectedConnectedDeviceCount: 1,
            observedSlotKinds: [1: ReceiverLogicalDeviceKind.mouse.rawValue]
        ))

        XCTAssertEqual(store.currentPublishedIdentities(), [reconnectedIdentity])
    }

    func testReceiverSlotStateStoreTreatsPartialSingletonAsIncompleteUntilInventoryReturns() {
        var store = ReceiverSlotStateStore()
        let mouseA = receiverIdentity(slot: 1, name: "Mouse A")
        let mouseB = receiverIdentity(slot: 2, name: "Mouse B")

        let partial = store.mergeDiscovery(.init(
            identities: [mouseB],
            connectionSnapshots: [2: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)],
            liveReachableSlots: [2],
            expectedConnectedDeviceCount: 2,
            observedSlotKinds: [2: ReceiverLogicalDeviceKind.mouse.rawValue]
        ))

        XCTAssertFalse(partial.inventoryComplete)
        XCTAssertEqual(store.currentPublishedIdentities(), [mouseB])

        let complete = store.mergeDiscovery(.init(
            identities: [mouseA, mouseB],
            connectionSnapshots: [
                1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue),
                2: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)
            ],
            liveReachableSlots: [1, 2],
            expectedConnectedDeviceCount: 2,
            observedSlotKinds: [
                1: ReceiverLogicalDeviceKind.mouse.rawValue,
                2: ReceiverLogicalDeviceKind.mouse.rawValue
            ]
        ))

        XCTAssertTrue(complete.inventoryComplete)
        XCTAssertEqual(store.currentPublishedIdentities(), [mouseA, mouseB])
    }

    func testReceiverSlotStateStoreCompletesNonPointingAndEmptyInventories() {
        var store = ReceiverSlotStateStore()
        let mouse = receiverIdentity(slot: 1, name: "Mouse A")

        let keyboardAndMouse = store.mergeDiscovery(.init(
            identities: [mouse],
            connectionSnapshots: [
                1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue),
                2: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.keyboard.rawValue)
            ],
            liveReachableSlots: [1, 2],
            expectedConnectedDeviceCount: 2,
            observedSlotKinds: [
                1: ReceiverLogicalDeviceKind.mouse.rawValue,
                2: ReceiverLogicalDeviceKind.keyboard.rawValue
            ]
        ))
        XCTAssertTrue(keyboardAndMouse.inventoryComplete)

        let empty = store.mergeDiscovery(.init(
            identities: [],
            connectionSnapshots: [:],
            liveReachableSlots: [],
            expectedConnectedDeviceCount: 0
        ))
        XCTAssertTrue(empty.inventoryComplete)
        XCTAssertTrue(store.currentPublishedIdentities().isEmpty)
    }

    func testReceiverSlotStateStoreCompletesMouseWithPresenterAndHeadset() {
        var store = ReceiverSlotStateStore()
        let mouse = receiverIdentity(slot: 1, name: "Mouse A")

        let result = store.mergeDiscovery(.init(
            identities: [mouse],
            connectionSnapshots: [
                1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue),
                2: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.presenter.rawValue),
                3: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.headset.rawValue)
            ],
            liveReachableSlots: [1, 2, 3],
            expectedConnectedDeviceCount: 3,
            observedSlotKinds: [
                1: ReceiverLogicalDeviceKind.mouse.rawValue,
                2: ReceiverLogicalDeviceKind.presenter.rawValue,
                3: ReceiverLogicalDeviceKind.headset.rawValue
            ]
        ))

        XCTAssertTrue(result.inventoryComplete)
        XCTAssertEqual(store.currentPublishedIdentities(), [mouse])
    }

    func testReceiverSlotStateStoreRequiresKnownCountAndPointingIdentityForCompleteInventory() {
        var store = ReceiverSlotStateStore()

        let unknownCount = store.mergeDiscovery(.init(
            identities: [],
            connectionSnapshots: [1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)],
            liveReachableSlots: [1],
            expectedConnectedDeviceCount: nil,
            observedSlotKinds: [1: ReceiverLogicalDeviceKind.mouse.rawValue]
        ))
        XCTAssertFalse(unknownCount.inventoryComplete)

        let missingIdentity = store.mergeDiscovery(.init(
            identities: [],
            connectionSnapshots: [1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)],
            liveReachableSlots: [1],
            expectedConnectedDeviceCount: 1,
            observedSlotKinds: [1: ReceiverLogicalDeviceKind.mouse.rawValue]
        ))
        XCTAssertFalse(missingIdentity.inventoryComplete)
        XCTAssertTrue(store.hasUnresolvedConnectedSlot)
    }

    func testReceiverSlotStateStoreFallsBackToObservedKindWhenSnapshotKindIsUnknown() {
        var store = ReceiverSlotStateStore()
        let identity = receiverIdentity(slot: 1, name: "Mouse A")

        let result = store.mergeDiscovery(.init(
            identities: [identity],
            connectionSnapshots: [1: .init(isConnected: true, kind: 0)],
            liveReachableSlots: [1],
            expectedConnectedDeviceCount: 1,
            observedSlotKinds: [1: ReceiverLogicalDeviceKind.mouse.rawValue]
        ))

        XCTAssertTrue(result.inventoryComplete)
    }

    func testReceiverSlotStateStoreTreatsUnknownHIDPPKindAsIncomplete() {
        var store = ReceiverSlotStateStore()

        let result = store.mergeDiscovery(.init(
            identities: [],
            connectionSnapshots: [1: .init(isConnected: true, kind: 0x06)],
            liveReachableSlots: [1],
            expectedConnectedDeviceCount: 1,
            observedSlotKinds: [1: 0x06]
        ))

        XCTAssertFalse(result.inventoryComplete)
    }

    func testReceiverPointingIdentityKindRejectsConflictingLiveMouseAndPairingKeyboard() {
        XCTAssertNil(resolveReceiverPointingIdentityKind(
            snapshotRaw: ReceiverLogicalDeviceKind.mouse.rawValue,
            pairingRaw: ReceiverLogicalDeviceKind.keyboard.rawValue
        ))
    }

    func testReceiverPointingIdentityKindPrefersLiveKeyboardOverPairingMouse() {
        XCTAssertEqual(
            resolveReceiverPointingIdentityKind(
                snapshotRaw: ReceiverLogicalDeviceKind.keyboard.rawValue,
                pairingRaw: ReceiverLogicalDeviceKind.mouse.rawValue
            ),
            .keyboard
        )
    }

    func testReceiverPointingIdentityKindHandlesUnknownMarkerAndMissingSnapshot() {
        XCTAssertEqual(
            resolveReceiverPointingIdentityKind(
                snapshotRaw: 0,
                pairingRaw: ReceiverLogicalDeviceKind.mouse.rawValue
            ),
            .mouse
        )
        XCTAssertEqual(
            resolveReceiverPointingIdentityKind(
                snapshotRaw: nil,
                pairingRaw: ReceiverLogicalDeviceKind.mouse.rawValue
            ),
            .mouse
        )
        XCTAssertEqual(
            resolveReceiverPointingIdentityKind(
                snapshotRaw: ReceiverLogicalDeviceKind.mouse.rawValue,
                pairingRaw: 0
            ),
            .mouse
        )
    }

    func testReceiverSlotStateStoreDropsStaleMouseForResolvedKeyboardSnapshot() {
        var store = ReceiverSlotStateStore()
        let staleMouse = receiverIdentity(slot: 1, name: "Mouse A")

        let result = store.mergeDiscovery(.init(
            identities: [staleMouse],
            connectionSnapshots: [1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.keyboard.rawValue)],
            liveReachableSlots: [1],
            expectedConnectedDeviceCount: 1,
            observedSlotKinds: [1: ReceiverLogicalDeviceKind.keyboard.rawValue]
        ))

        XCTAssertTrue(result.inventoryComplete)
        XCTAssertTrue(store.currentPublishedIdentities().isEmpty)
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

    func testReceiverSlotStateStoreInvalidatingChannelClearsPublishedIdentity() {
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

        store.mergeDiscovery(.init(
            identities: [identity],
            connectionSnapshots: [1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)],
            liveReachableSlots: [1]
        ))
        XCTAssertEqual(store.currentPublishedIdentities(), [identity])

        store.invalidateChannel()

        XCTAssertTrue(store.currentPublishedIdentities().isEmpty)
        XCTAssertTrue(store.needsIdentityRefresh(slot: identity.slot))
    }

    func testConnectedBatteryDeviceDirectIdentityPrefersSerialNumber() {
        let identity = ConnectedBatteryDeviceInfo.directIdentity(
            vendorID: 0x046D,
            productID: 0x405E,
            serialNumber: "ABC123",
            locationID: 0x1000,
            transport: PointerDeviceTransportName.usb,
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
            transport: PointerDeviceTransportName.usb,
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

    private func receiverIdentity(slot: UInt8, name: String) -> ReceiverLogicalDeviceIdentity {
        ReceiverLogicalDeviceIdentity(
            receiverLocationID: 0x1234,
            slot: slot,
            kind: .mouse,
            name: name,
            serialNumber: nil,
            productID: nil,
            batteryLevel: nil
        )
    }
}
