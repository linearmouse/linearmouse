// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import PointerKit
import XCTest

final class LogitechHIDPPDeviceMetadataProviderTests: XCTestCase {
    func testLegacyReceiverSlotProbeRejectsAmbiguousIdentity() {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB034,
            product: "MX Master 3S",
            serialNumber: "ABC123",
            transport: PointerDeviceTransportName.usb,
            primaryUsagePage: kHIDPage_GenericDesktop,
            primaryUsage: kHIDUsage_GD_Mouse
        )

        let candidate = provider.receiverSlotCandidate(for: device, slots: [
            slot(slot: 1, name: "MX Master 3S", serialNumber: "ABC123", productID: 0xB034),
            slot(slot: 2, name: "MX Master 3S", serialNumber: "ABC123", productID: 0xB034)
        ])

        XCTAssertNil(candidate)
    }

    func testLegacyReceiverSlotProbeKeepsUniqueCompatibilityKindFallback() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: nil,
            product: "Unknown Mouse",
            transport: PointerDeviceTransportName.usb,
            primaryUsagePage: kHIDPage_GenericDesktop,
            primaryUsage: kHIDUsage_GD_Mouse
        )

        let candidate = try XCTUnwrap(provider.receiverSlotCandidate(for: device, slots: [
            slot(slot: 1, kind: 0x02),
            slot(slot: 2, kind: 0x01)
        ]))

        XCTAssertEqual(candidate.slot, 1)
    }

    func testKnownPartialInventoryRejectsSingletonFallback() {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let device = mouseDevice()

        let candidate = provider.receiverSlotCandidate(
            for: device,
            slots: [slot(slot: 1, name: "Mouse")],
            connectionSnapshots: [1: .init(isConnected: true, kind: 0x02)],
            expectedConnectedDeviceCount: 2,
            inventoryAvailable: true
        )

        XCTAssertNil(candidate)
    }

    func testKnownCompleteInventoryAllowsSingleActiveCandidate() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let device = mouseDevice()

        let candidate = try XCTUnwrap(provider.receiverSlotCandidate(
            for: device,
            slots: [slot(slot: 1, name: "Mouse")],
            connectionSnapshots: [1: .init(isConnected: true, kind: 0x02)],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true
        ))

        XCTAssertEqual(candidate.slot, 1)
    }

    func testKnownEmptyInventoryHasNoCandidate() {
        let provider = LogitechHIDPPDeviceMetadataProvider()

        XCTAssertNil(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: [slot(slot: 1, name: "Mouse")],
            connectionSnapshots: [:],
            expectedConnectedDeviceCount: 0,
            inventoryAvailable: true
        ))
    }

    func testKnownPartialInventoryAllowsExactActiveSerialMatch() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: nil,
            product: "Mouse",
            serialNumber: "ABC123",
            transport: PointerDeviceTransportName.usb,
            primaryUsagePage: kHIDPage_GenericDesktop,
            primaryUsage: kHIDUsage_GD_Mouse
        )

        let candidate = try XCTUnwrap(provider.receiverSlotCandidate(
            for: device,
            slots: [slot(slot: 1, name: "Mouse", serialNumber: "ABC123")],
            connectionSnapshots: [1: .init(isConnected: true, kind: 0x02)],
            expectedConnectedDeviceCount: 2,
            inventoryAvailable: true
        ))

        XCTAssertEqual(candidate.slot, 1)
    }

    func testUnknownCountKeepsLegacyCompatibilityFallback() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()

        let candidate = try XCTUnwrap(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: [slot(slot: 1, name: "Mouse")],
            connectionSnapshots: [:],
            expectedConnectedDeviceCount: nil,
            inventoryAvailable: false
        ))

        XCTAssertEqual(candidate.slot, 1)
    }

    func testMouseContextRejectsSingleKnownKeyboardCandidate() {
        let provider = LogitechHIDPPDeviceMetadataProvider()

        XCTAssertNil(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: [slot(slot: 1, kind: ReceiverLogicalDeviceKind.keyboard.rawValue)],
            connectionSnapshots: [1: .init(isConnected: true, kind: 0x01)],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true
        ))
    }

    func testKnownKeyboardSnapshotRejectsStaleMouseCandidate() {
        let provider = LogitechHIDPPDeviceMetadataProvider()

        XCTAssertNil(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: [slot(slot: 1, kind: ReceiverLogicalDeviceKind.mouse.rawValue, name: "Mouse")],
            connectionSnapshots: [1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.keyboard.rawValue)],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true
        ))
    }

    func testKnownMouseSnapshotRejectsStaleKeyboardCandidate() {
        let provider = LogitechHIDPPDeviceMetadataProvider()

        XCTAssertNil(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: [slot(slot: 1, kind: ReceiverLogicalDeviceKind.keyboard.rawValue, name: "Keyboard")],
            connectionSnapshots: [1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true
        ))
    }

    func testKnownKeyboardSnapshotDoesNotBlockMouseRouteWhenCandidateIsStale() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()

        let candidate = try XCTUnwrap(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: [
                slot(slot: 1, kind: ReceiverLogicalDeviceKind.mouse.rawValue, name: "Mouse"),
                slot(slot: 2, kind: ReceiverLogicalDeviceKind.mouse.rawValue, name: "Stale Mouse")
            ],
            connectionSnapshots: [
                1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue),
                2: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.keyboard.rawValue)
            ],
            expectedConnectedDeviceCount: 2,
            inventoryAvailable: true
        ))

        XCTAssertEqual(candidate.slot, 1)
    }

    func testKnownCountKindResolutionAcceptsZeroMarkerAndRejectsUnsupportedKind() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let slots = [slot(slot: 1, kind: ReceiverLogicalDeviceKind.mouse.rawValue, name: "Mouse")]

        let zeroMarker = try XCTUnwrap(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: slots,
            connectionSnapshots: [1: .init(isConnected: true, kind: 0)],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true
        ))
        XCTAssertEqual(zeroMarker.slot, 1)

        XCTAssertNil(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: slots,
            connectionSnapshots: [1: .init(isConnected: true, kind: 0x06)],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true
        ))
    }

    func testKnownCountKindResolutionAcceptsNilSnapshotWithKnownCandidate() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()

        let candidate = try XCTUnwrap(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: [slot(slot: 1, kind: ReceiverLogicalDeviceKind.mouse.rawValue, name: "Mouse")],
            connectionSnapshots: [1: .init(isConnected: true, kind: nil)],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true
        ))

        XCTAssertEqual(candidate.slot, 1)
    }

    func testCompleteMouseAndKeyboardInventoryRoutesOnlyMouseCandidate() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()

        let candidate = try XCTUnwrap(provider.receiverSlotCandidate(
            for: mouseDevice(),
            slots: [
                slot(slot: 1, kind: ReceiverLogicalDeviceKind.mouse.rawValue, name: "Mouse"),
                slot(slot: 2, kind: ReceiverLogicalDeviceKind.keyboard.rawValue, name: "Keyboard")
            ],
            connectionSnapshots: [
                1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue),
                2: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.keyboard.rawValue)
            ],
            expectedConnectedDeviceCount: 2,
            inventoryAvailable: true
        ))

        XCTAssertEqual(candidate.slot, 1)
    }

    func testMouseContextRejectsExactSerialOnKeyboardSnapshot() {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: nil,
            product: "Mouse",
            serialNumber: "ABC123",
            transport: PointerDeviceTransportName.usb,
            primaryUsagePage: kHIDPage_GenericDesktop,
            primaryUsage: kHIDUsage_GD_Mouse
        )

        XCTAssertNil(provider.receiverSlotCandidate(
            for: device,
            slots: [slot(
                slot: 1,
                kind: ReceiverLogicalDeviceKind.keyboard.rawValue,
                serialNumber: "ABC123"
            )],
            connectionSnapshots: [1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.keyboard.rawValue)],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true
        ))
    }

    func testPendingUnavailableChannelRequestsReopen() {
        XCTAssertEqual(
            ReceiverPendingDiscoveryDisposition.resolve(
                inventoryAvailable: false,
                channelReachable: false
            ),
            .reopenChannel
        )
        XCTAssertEqual(
            ReceiverPendingDiscoveryDisposition.resolve(
                inventoryAvailable: false,
                channelReachable: true
            ),
            .retryCurrentChannel
        )
    }

    func testReadyCountChangeEntersPendingOnlyWhenKnownCountChanges() {
        XCTAssertEqual(ReceiverReadyCountDisposition.resolve(previousCount: 2, currentCount: 2), .stayReady)
        XCTAssertEqual(ReceiverReadyCountDisposition.resolve(previousCount: 2, currentCount: 1), .enterPending)
        XCTAssertEqual(ReceiverReadyCountDisposition.resolve(previousCount: 2, currentCount: nil), .stayReady)
    }

    func testConnectionSnapshotCollectorRetainsReconnectTransition() {
        var collector = LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshotCollector(
            expectedConnectedDeviceCount: nil
        )
        collector.record(slot: 1, snapshot: .init(isConnected: false, kind: 0x02))
        collector.record(slot: 1, snapshot: .init(isConnected: true, kind: 0x02))
        collector.record(slot: 2, snapshot: .init(isConnected: true, kind: 0x02))

        XCTAssertEqual(collector.batch.snapshots[1], .init(isConnected: true, kind: 0x02))
        XCTAssertEqual(collector.batch.reconnectedSlots, Set([1]))
    }

    func testBoltOnDemandDiscoveryRejectsPartialSingletonAndAllowsCompleteInventory() throws {
        let provider = LogitechHIDPPDeviceMetadataProvider()
        let identity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 1,
            slot: 1,
            kind: .mouse,
            name: "Mouse",
            serialNumber: nil,
            productID: nil,
            batteryLevel: nil
        )
        let partial = LogitechHIDPPDeviceMetadataProvider.ReceiverPointingDeviceDiscovery(
            identities: [identity],
            connectionSnapshots: [1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)],
            liveReachableSlots: [1],
            expectedConnectedDeviceCount: 2,
            inventoryAvailable: true,
            observedSlotKinds: [1: ReceiverLogicalDeviceKind.mouse.rawValue]
        )

        XCTAssertNil(provider.receiverSlot(for: mouseDevice(), discovery: partial))

        let complete = LogitechHIDPPDeviceMetadataProvider.ReceiverPointingDeviceDiscovery(
            identities: [identity],
            connectionSnapshots: [1: .init(isConnected: true, kind: ReceiverLogicalDeviceKind.mouse.rawValue)],
            liveReachableSlots: [1],
            expectedConnectedDeviceCount: 1,
            inventoryAvailable: true,
            observedSlotKinds: [1: ReceiverLogicalDeviceKind.mouse.rawValue]
        )

        XCTAssertEqual(try XCTUnwrap(provider.receiverSlot(for: mouseDevice(), discovery: complete)), 1)
    }

    func testCancelledCommittedCallbackTransactionDrainsItsResponse() {
        var response: Data?
        var waitCount = 0

        let result: Data? = HIDPPCommittedTransaction.settle(
            until: Date().addingTimeInterval(1),
            shouldDeliverResult: { false },
            isTransportValid: { true },
            wait: { _ in
                waitCount += 1
                response = Data([0x11, 0xFF, 0x22, 0x18])
            },
            response: { response }
        )

        XCTAssertNil(result)
        XCTAssertEqual(waitCount, 1)
    }

    func testCancelledCommittedGetReportTransactionDrainsItsResponse() {
        var getReportResponse: Data?
        var pollCount = 0

        let result: Data? = HIDPPCommittedTransaction.settle(
            until: Date().addingTimeInterval(1),
            shouldDeliverResult: { false },
            isTransportValid: { true },
            wait: { _ in
                pollCount += 1
                getReportResponse = Data([0x11, 0xFF, 0x22, 0x18])
            },
            response: { getReportResponse }
        )

        XCTAssertNil(result)
        XCTAssertEqual(pollCount, 1)
    }

    func testNotificationBufferRetainsConnectionEventsAcrossWaiterGapInOrder() {
        let buffer = HIDPPNotificationBuffer()
        let disconnect = [UInt8]([0x10, 0x01, 0x41, 0x00, 0x42, 0x00, 0x00])
        let connect = [UInt8]([0x10, 0x02, 0x41, 0x00, 0x02, 0x00, 0x00])

        buffer.appendIfUnsolicited(disconnect)
        buffer.appendIfUnsolicited(connect)

        XCTAssertEqual(
            buffer.wait(timeout: 0) {
                LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification($0) != nil
            },
            disconnect
        )
        XCTAssertEqual(
            buffer.wait(timeout: 0) {
                LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification($0) != nil
            },
            connect
        )
    }

    func testNotificationEndpointRetainsControlsNotificationsButRejectsCommandReplies() {
        let buffer = HIDPPNotificationBuffer()
        let commandReply = Data([0x11, 0x02, 0x05, 0x08, 0x00, 0xC3, 0x00])
        let notification = Data([0x11, 0x02, 0x05, 0x00, 0x00, 0xC3, 0x00])

        buffer.appendIfUnsolicited(commandReply)
        XCTAssertEqual(buffer.bufferedReportCount, 0)
        buffer.appendIfUnsolicited(notification)
        XCTAssertEqual(buffer.bufferedReportCount, 1)

        let endpoint = HIDPPNotificationEndpoint()
        endpoint.handleInputReport(commandReply)
        endpoint.handleInputReport(notification)

        XCTAssertEqual(
            endpoint.waitForHIDPPNotification(
                timeout: 0,
                matching: { LogitechReprogrammableControlsMonitor.isDivertedButtonsNotification(
                    $0,
                    featureIndex: 0x05,
                    deviceIndices: [0x02]
                )
                },
                until: nil
            ),
            [UInt8](notification)
        )
    }

    func testNotificationBufferDiscardRemovesStaleEventsForEachControlsConfigurationCycle() {
        let buffer = HIDPPNotificationBuffer()
        let staleBeforeFirstCycle = [UInt8]([0x11, 0x02, 0x05, 0x00, 0x00, 0xC3, 0x00])
        let connection = [UInt8]([0x10, 0x02, 0x41, 0x00, 0x02, 0x00, 0x00])
        let residualFromFirstCycle = [UInt8]([0x11, 0x02, 0x05, 0x00, 0x00, 0xC4, 0x00])
        let freshPress = [UInt8]([0x11, 0x02, 0x05, 0x00, 0x00, 0xC5, 0x00])
        let matchesTargetControls: ([UInt8]) -> Bool = {
            LogitechReprogrammableControlsMonitor.isDivertedButtonsNotification(
                $0,
                featureIndex: 0x05,
                deviceIndices: [0x02]
            )
        }

        buffer.appendIfUnsolicited(staleBeforeFirstCycle)
        buffer.appendIfUnsolicited(connection)
        buffer.discard(matching: matchesTargetControls)

        XCTAssertNil(buffer.wait(timeout: 0, matching: matchesTargetControls))
        XCTAssertEqual(
            buffer.wait(timeout: 0) {
                LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification($0) != nil
            },
            connection
        )

        // A configuration change ends the first diversion loop with this
        // report still buffered. The next cycle must discard it before
        // diverting controls again.
        buffer.appendIfUnsolicited(residualFromFirstCycle)
        buffer.discard(matching: matchesTargetControls)
        XCTAssertNil(buffer.wait(timeout: 0, matching: matchesTargetControls))

        buffer.appendIfUnsolicited(freshPress)
        XCTAssertEqual(buffer.wait(timeout: 0, matching: matchesTargetControls), freshPress)
    }

    func testDivertedButtonsMatcherRejectsReceiverConnectionReportWithFeatureLikeSubID() {
        let connection = [UInt8]([0x10, 0x02, 0x41, 0x00, 0x02, 0x00, 0x00])

        XCTAssertFalse(
            LogitechReprogrammableControlsMonitor.isDivertedButtonsNotification(
                connection,
                featureIndex: 0x41,
                deviceIndices: [0x02]
            )
        )
    }

    func testConnectionSnapshotCollectorRetainsFollowupUntilQuietWait() {
        var collector = LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshotCollector(
            expectedConnectedDeviceCount: 1
        )
        collector.record(slot: 1, snapshot: .init(isConnected: true, kind: 0x02))

        // The caller may stop only when a subsequent wait is quiet. A buffered
        // disconnect received first replaces the earlier connect.
        XCTAssertTrue(collector.isCompleteAfterQuietWait)
        collector.record(slot: 1, snapshot: .init(isConnected: false, kind: 0x02))

        XCTAssertFalse(collector.isCompleteAfterQuietWait)
        XCTAssertEqual(collector.snapshots[1], .init(isConnected: false, kind: 0x02))
    }

    func testConnectionSnapshotCollectorCompletesAfterQuietWaitForConnectOnly() {
        var collector = LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshotCollector(
            expectedConnectedDeviceCount: 1
        )
        collector.record(slot: 1, snapshot: .init(isConnected: true, kind: 0x02))

        XCTAssertTrue(collector.isCompleteAfterQuietWait)
    }

    func testNotificationBufferCoalescesHistoricalWakeups() {
        let firstWait = expectation(description: "buffer waits once")
        let finished = expectation(description: "buffer wait cancels")
        let lock = NSLock()
        var waitCount = 0
        var shouldContinue = true
        let buffer = HIDPPNotificationBuffer(maximumBufferedReports: 2) {
            lock.withLock {
                waitCount += 1
            }
            firstWait.fulfill()
        }

        for slot in UInt8(1) ... UInt8(10) {
            buffer.appendIfUnsolicited([0x10, slot, 0x41, 0x00, 0x02, 0x00, 0x00])
        }

        DispatchQueue.global().async {
            _ = buffer.wait(
                timeout: 1,
                matching: { $0[2] == 0x05 },
                until: { lock.withLock { shouldContinue } }
            )
            finished.fulfill()
        }

        wait(for: [firstWait], timeout: 1)
        lock.withLock { shouldContinue = false }
        buffer.wake()
        wait(for: [finished], timeout: 1)
        XCTAssertEqual(lock.withLock { waitCount }, 1)
    }

    func testNotificationBufferWakeInterruptsCurrentWaitWhileContinuationRemainsTrue() {
        let waiting = expectation(description: "notification wait started")
        let finished = expectation(description: "notification wait interrupted")
        let lock = NSLock()
        var didReturnNil = false
        let buffer = HIDPPNotificationBuffer {
            waiting.fulfill()
        }

        DispatchQueue.global().async {
            let value = buffer.wait(
                timeout: 5,
                matching: { _ in false },
                until: { true }
            )
            lock.withLock { didReturnNil = value == nil }
            finished.fulfill()
        }

        wait(for: [waiting], timeout: 1)
        buffer.wake()
        wait(for: [finished], timeout: 1)
        XCTAssertTrue(lock.withLock { didReturnNil })
    }

    func testNotificationBufferConsumesPreWaitWakeExactlyOnce() {
        let secondWaitStarted = expectation(description: "second wait started")
        let secondWaitFinished = expectation(description: "second wait received report")
        let lock = NSLock()
        var waitCount = 0
        let report = [UInt8]([0x10, 0x01, 0x41, 0x00, 0x02, 0x00, 0x00])
        let buffer = HIDPPNotificationBuffer {
            lock.withLock { waitCount += 1 }
            secondWaitStarted.fulfill()
        }

        buffer.wake()
        XCTAssertNil(buffer.wait(timeout: 5, matching: { _ in true }, until: { true }))
        XCTAssertEqual(lock.withLock { waitCount }, 0)

        DispatchQueue.global().async {
            XCTAssertEqual(
                buffer.wait(timeout: 5, matching: { _ in true }, until: { true }),
                report
            )
            secondWaitFinished.fulfill()
        }

        wait(for: [secondWaitStarted], timeout: 1)
        buffer.appendIfUnsolicited(report)
        wait(for: [secondWaitFinished], timeout: 1)
        XCTAssertEqual(lock.withLock { waitCount }, 1)
    }

    func testNotificationBufferInterruptTakesPriorityWithoutDiscardingBufferedReport() {
        let buffer = HIDPPNotificationBuffer()
        let report = [UInt8]([0x10, 0x01, 0x41, 0x00, 0x02, 0x00, 0x00])

        buffer.appendIfUnsolicited(report)
        buffer.wake()

        XCTAssertNil(buffer.wait(timeout: 0, matching: { _ in true }, until: { true }))
        XCTAssertEqual(buffer.wait(timeout: 0, matching: { _ in true }, until: { true }), report)
    }

    func testNotificationBufferPreservesOrderingAroundNonmatchingReports() {
        let buffer = HIDPPNotificationBuffer()
        let connection = [UInt8]([0x10, 0x01, 0x41, 0x00, 0x02, 0x00, 0x00])
        let firstControl = [UInt8]([0x11, 0x02, 0x05, 0x00, 0x00, 0xC3, 0x00])
        let secondControl = [UInt8]([0x11, 0x02, 0x05, 0x00, 0x00, 0xC4, 0x00])
        let matchesControls: ([UInt8]) -> Bool = { $0[2] == 0x05 }

        buffer.appendIfUnsolicited(connection)
        buffer.appendIfUnsolicited(firstControl)
        buffer.appendIfUnsolicited(secondControl)

        XCTAssertEqual(buffer.wait(timeout: 0, matching: matchesControls), firstControl)
        XCTAssertEqual(buffer.wait(timeout: 0, matching: matchesControls), secondControl)
        XCTAssertEqual(buffer.wait(timeout: 0) { _ in true }, connection)
    }

    func testCommittedGetReportTransactionsUseIndependentTimedYields() {
        var firstResponse: Data?
        var secondResponse: Data?
        var firstPollCount = 0
        var secondPollCount = 0

        let firstResult: Data? = HIDPPCommittedTransaction.settle(
            until: Date().addingTimeInterval(1),
            shouldDeliverResult: { false },
            isTransportValid: { true },
            wait: { _ in
                firstPollCount += 1
                firstResponse = Data([0x01])
            },
            response: { firstResponse }
        )
        let secondResult: Data? = HIDPPCommittedTransaction.settle(
            until: Date().addingTimeInterval(1),
            shouldDeliverResult: { false },
            isTransportValid: { true },
            wait: { _ in
                secondPollCount += 1
                secondResponse = Data([0x02])
            },
            response: { secondResponse }
        )

        XCTAssertNil(firstResult)
        XCTAssertNil(secondResult)
        XCTAssertEqual(firstPollCount, 1)
        XCTAssertEqual(secondPollCount, 1)
    }

    func testReceiverNotificationOwnershipRejectsMissingSerialSentinels() {
        let vendorID: Int? = 0x046D
        let target: (String?) -> ReceiverNotificationOwnershipTarget? = {
            ReceiverNotificationOwnershipTarget.stableReceiver(
                vendorID: vendorID,
                serialNumber: $0
            )
        }

        XCTAssertNil(target("00000000"))
        XCTAssertNil(target("FF:FF:FF:FF"))
        guard case let .receiver(resolvedVendorID, serialNumber)? = target(" ab-cd:12 ") else {
            XCTFail("Expected a canonical stable receiver identity")
            return
        }
        XCTAssertEqual(resolvedVendorID, 0x046D)
        XCTAssertEqual(serialNumber, "ABCD12")
    }

    func testReceiverNotificationOwnershipCapturesOnlyBitsItAddsAndKeepsFirstEntry() throws {
        let store = ReceiverNotificationOwnershipStore()
        let target = try XCTUnwrap(ReceiverNotificationOwnershipTarget.receiver(
            vendorID: 0x046D,
            serialNumber: " receiver-a "
        ))
        let wireless: UInt32 = 0x000100
        let softwarePresent: UInt32 = 0x000800
        var flags = wireless // Pre-existing: LinearMouse must not own it.

        XCTAssertTrue(store.enable(
            wireless | softwarePresent,
            for: target,
            read: { flags },
            write: {
                flags = $0
                return true
            }
        ))
        let first = try XCTUnwrap(store.claim(for: target))
        XCTAssertEqual(first.ownedBits, softwarePresent)

        // If the pre-existing bit later disappears and LinearMouse adds it, it
        // joins the existing ownership entry rather than replacing that entry.
        flags &= ~wireless
        XCTAssertTrue(store.enable(
            wireless | softwarePresent,
            for: target,
            read: { flags },
            write: {
                flags = $0
                return true
            }
        ))
        let second = try XCTUnwrap(store.claim(for: target))
        XCTAssertEqual(second.ownedBits, wireless | softwarePresent)
        XCTAssertTrue(first.handle.ownsSameEntry(as: second.handle))

        // Consuming the older snapshot must leave bits acquired later pending.
        XCTAssertTrue(store.consumeRestoredBits(first.handle))
        XCTAssertEqual(store.claim(for: target)?.ownedBits, wireless)
    }

    func testReceiverNotificationRestorePreservesUnrelatedLaterBits() throws {
        let store = ReceiverNotificationOwnershipStore()
        let target = try XCTUnwrap(ReceiverNotificationOwnershipTarget.receiver(
            vendorID: 0x046D,
            serialNumber: "RECEIVER-A"
        ))
        let owned: UInt32 = 0x000100
        let unrelated: UInt32 = 0x400000
        var flags: UInt32 = 0

        XCTAssertTrue(store.enable(
            owned,
            for: target,
            read: { flags },
            write: {
                flags = $0
                return true
            }
        ))
        flags |= unrelated

        XCTAssertTrue(store.restoreOwnedBits(
            for: target,
            read: { flags },
            write: {
                flags = $0
                return true
            }
        ))
        XCTAssertEqual(flags, unrelated)
        XCTAssertNil(store.claim(for: target))
    }

    func testTerminalAdmissionPreventsInFlightProducerFromReaddingNotificationBits() throws {
        let admission = ReceiverChannelTerminalAdmission()
        let store = ReceiverNotificationOwnershipStore()
        let target = try XCTUnwrap(ReceiverNotificationOwnershipTarget.receiver(
            vendorID: 0x046D,
            serialNumber: "RECEIVER-A"
        ))
        let originalOwnedBit: UInt32 = 0x000100
        let lateProducerBit: UInt32 = 0x000800
        var flags: UInt32 = 0

        XCTAssertTrue(store.enable(
            originalOwnedBit,
            for: target,
            read: { flags },
            write: {
                flags = $0
                return true
            },
            shouldContinue: { admission.allowsProducerMutation }
        ))

        let readStarted = DispatchSemaphore(value: 0)
        let allowReadToReturn = DispatchSemaphore(value: 0)
        let producerFinished = DispatchSemaphore(value: 0)
        let resultLock = NSLock()
        var lateProducerResult: Bool?
        DispatchQueue.global(qos: .utility)
            .async {
                let result = store.enable(
                    lateProducerBit,
                    for: target,
                    read: {
                        readStarted.signal()
                        allowReadToReturn.wait()
                        return flags
                    },
                    write: {
                        flags = $0
                        return true
                    },
                    shouldContinue: { admission.allowsProducerMutation }
                )
                resultLock.withLock { lateProducerResult = result }
                producerFinished.signal()
            }

        XCTAssertEqual(readStarted.wait(timeout: .now() + 1), .success)
        let ownership = ReceiverChannelTerminalOwnership()
        XCTAssertTrue(admission.begin(ownership: ownership))
        allowReadToReturn.signal()
        XCTAssertEqual(producerFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(resultLock.withLock { lateProducerResult }, false)

        XCTAssertTrue(store.restoreOwnedBits(
            for: target,
            read: { flags },
            write: {
                flags = $0
                return true
            },
            shouldContinue: { admission.isOwned(by: ownership) }
        ))
        XCTAssertEqual(flags, 0)
        XCTAssertNil(store.claim(for: target))
    }

    func testNotificationRestoreWaitsForInFlightEnableToCaptureOwnership() throws {
        let store = ReceiverNotificationOwnershipStore()
        let target = try XCTUnwrap(ReceiverNotificationOwnershipTarget.receiver(
            vendorID: 0x046D,
            serialNumber: "RECEIVER-A"
        ))
        let ownedBit: UInt32 = 0x000800
        let stateLock = NSLock()
        var flags: UInt32 = 0
        let writeCommitted = DispatchSemaphore(value: 0)
        let allowEnableToFinish = DispatchSemaphore(value: 0)
        let enableFinished = DispatchSemaphore(value: 0)
        let restoreStarted = DispatchSemaphore(value: 0)
        let restoreFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .utility).async {
            _ = store.enable(
                ownedBit,
                for: target,
                read: { stateLock.withLock { flags } },
                write: { value in
                    stateLock.withLock { flags = value }
                    writeCommitted.signal()
                    allowEnableToFinish.wait()
                    return true
                }
            )
            enableFinished.signal()
        }

        XCTAssertEqual(writeCommitted.wait(timeout: .now() + 1), .success)
        DispatchQueue.global(qos: .utility).async {
            restoreStarted.signal()
            _ = store.restoreOwnedBits(
                for: target,
                read: { stateLock.withLock { flags } },
                write: { value in
                    stateLock.withLock { flags = value }
                    return true
                }
            )
            restoreFinished.signal()
        }

        XCTAssertEqual(restoreStarted.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(restoreFinished.wait(timeout: .now() + 0.05), .timedOut)
        allowEnableToFinish.signal()
        XCTAssertEqual(enableFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(restoreFinished.wait(timeout: .now() + 1), .success)
        XCTAssertEqual(stateLock.withLock { flags }, 0)
        XCTAssertNil(store.claim(for: target))
    }

    func testNotificationRestoreCanCancelWhileAnotherMutationOwnsTheLock() throws {
        let store = ReceiverNotificationOwnershipStore()
        let target = try XCTUnwrap(ReceiverNotificationOwnershipTarget.receiver(
            vendorID: 0x046D,
            serialNumber: "RECEIVER-A"
        ))
        let writeStarted = DispatchSemaphore(value: 0)
        let releaseWrite = DispatchSemaphore(value: 0)
        let enableFinished = DispatchSemaphore(value: 0)
        let restoreFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global(qos: .utility).async {
            _ = store.enable(
                0x000800,
                for: target,
                read: { 0 },
                write: { _ in
                    writeStarted.signal()
                    releaseWrite.wait()
                    return true
                }
            )
            enableFinished.signal()
        }
        XCTAssertEqual(writeStarted.wait(timeout: .now() + 1), .success)

        let checkLock = NSLock()
        var continuationChecks = 0
        DispatchQueue.global(qos: .utility).async {
            _ = store.restoreOwnedBits(
                for: target,
                read: { 0x000800 },
                write: { _ in true },
                shouldContinue: {
                    checkLock.withLock {
                        continuationChecks += 1
                        return continuationChecks == 1
                    }
                }
            )
            restoreFinished.signal()
        }

        XCTAssertEqual(restoreFinished.wait(timeout: .now() + 0.2), .success)
        releaseWrite.signal()
        XCTAssertEqual(enableFinished.wait(timeout: .now() + 1), .success)
    }

    func testTerminalAdmissionUsesExactOwnership() {
        let admission = ReceiverChannelTerminalAdmission()
        let ownership = ReceiverChannelTerminalOwnership()
        let unrelatedOwnership = ReceiverChannelTerminalOwnership()

        XCTAssertTrue(admission.begin(ownership: ownership))
        XCTAssertFalse(admission.allowsProducerMutation)
        XCTAssertTrue(admission.isOwned(by: ownership))
        XCTAssertFalse(admission.isOwned(by: unrelatedOwnership))
        XCTAssertFalse(admission.begin(ownership: unrelatedOwnership))
    }

    func testTerminalFinishClosesOnceAndCompletesEveryCallerExactlyOnce() {
        let finishState = ReceiverChannelTerminalFinishState { $0() }
        var firstCompletionCount = 0
        var joinedCompletionCount = 0
        var lateCompletionCount = 0

        XCTAssertTrue(finishState.begin { firstCompletionCount += 1 })
        XCTAssertFalse(finishState.allowsRestore)
        XCTAssertFalse(finishState.begin { joinedCompletionCount += 1 })

        finishState.complete()
        finishState.complete()

        XCTAssertEqual(firstCompletionCount, 1)
        XCTAssertEqual(joinedCompletionCount, 1)
        XCTAssertFalse(finishState.begin { lateCompletionCount += 1 })
        XCTAssertEqual(lateCompletionCount, 1)
    }

    func testTerminalResourceRejectsLateOpenAfterFinishBegins() {
        final class Resource {}

        let initial = Resource()
        let late = Resource()
        let state = ReceiverChannelTerminalResource(initial)

        XCTAssertIdentical(state.current, initial)
        XCTAssertFalse(state.accept(late))
        XCTAssertIdentical(state.takeForFinish(), initial)
        XCTAssertNil(state.current)
        XCTAssertFalse(state.accept(late))
        XCTAssertNil(state.takeForFinish())
    }

    func testTerminalResourcePublishesAcceptedOpenBeforeFinishCanTakeIt() {
        final class Resource {}

        let opened = Resource()
        let state = ReceiverChannelTerminalResource<Resource>(nil)

        XCTAssertTrue(state.accept(opened))
        XCTAssertIdentical(state.takeForFinish(), opened)
    }

    func testStaleChannelCloseCannotReleaseReplacementClosingOwnership() {
        var registry = ReceiverChannelOwnershipRegistry<ReceiverChannelClosingOwnership>()
        let first = ReceiverChannelClosingOwnership()
        let replacement = ReceiverChannelClosingOwnership()
        let unrelated = ReceiverChannelClosingOwnership()
        let locationID = 123

        XCTAssertTrue(registry.begin(locationID: locationID, ownership: first))
        XCTAssertFalse(registry.begin(locationID: locationID, ownership: replacement))
        XCTAssertFalse(registry.release(locationID: locationID, ownership: unrelated))
        XCTAssertTrue(registry.isClaimed(locationID: locationID))
        XCTAssertTrue(registry.release(locationID: locationID, ownership: first))

        XCTAssertTrue(registry.begin(locationID: locationID, ownership: replacement))
        XCTAssertFalse(registry.release(locationID: locationID, ownership: first))
        XCTAssertTrue(registry.isClaimed(locationID: locationID))
        XCTAssertTrue(registry.release(locationID: locationID, ownership: replacement))
        XCTAssertFalse(registry.isClaimed(locationID: locationID))
    }

    func testUnidentifiedReceiverNotificationOwnershipSurvivesChannelRebuildInSameContext() {
        let contextSession = ReceiverNotificationOwnershipSession()
        let target = ReceiverNotificationOwnershipTarget.session(contextSession.identity)
        var flags: UInt32 = 0

        XCTAssertTrue(contextSession.store.enable(
            0x000100,
            for: target,
            read: { flags },
            write: {
                flags = $0
                return true
            }
        ))

        // Channel A retires while its bounded restore can no longer continue.
        // The context-owned session must keep the claim for channel B.
        XCTAssertFalse(contextSession.store.restoreOwnedBits(
            for: target,
            read: { flags },
            write: { _ in
                XCTFail("A cancelled retirement must not write")
                return true
            },
            shouldContinue: { false }
        ))
        XCTAssertEqual(contextSession.store.claim(for: target)?.ownedBits, 0x000100)

        // Channel B receives the same concrete session from ReceiverContext.
        XCTAssertTrue(contextSession.store.restoreOwnedBits(
            for: target,
            read: { flags },
            write: {
                flags = $0
                return true
            }
        ))
        XCTAssertEqual(flags, 0)
    }

    func testUnidentifiedReceiverNotificationOwnershipDoesNotCrossContexts() {
        let firstContext = ReceiverNotificationOwnershipSession()
        let firstTarget = ReceiverNotificationOwnershipTarget.session(firstContext.identity)
        var flags: UInt32 = 0

        XCTAssertTrue(firstContext.store.enable(
            0x000100,
            for: firstTarget,
            read: { flags },
            write: {
                flags = $0
                return true
            }
        ))

        let replacementContext = ReceiverNotificationOwnershipSession()
        let replacementTarget = ReceiverNotificationOwnershipTarget.session(replacementContext.identity)
        var replacementReadCount = 0
        var replacementWriteCount = 0
        XCTAssertTrue(replacementContext.store.restoreOwnedBits(
            for: replacementTarget,
            read: {
                replacementReadCount += 1
                return flags
            },
            write: { _ in
                replacementWriteCount += 1
                return true
            }
        ))
        XCTAssertEqual(replacementReadCount, 0)
        XCTAssertEqual(replacementWriteCount, 0)
        XCTAssertEqual(firstContext.store.claim(for: firstTarget)?.ownedBits, 0x000100)
    }

    func testNotificationSessionRegistrationAdoptsExistingChannelSession() {
        let registry = ReceiverNotificationOwnershipSessionRegistry()
        let existingChannelSession = ReceiverNotificationOwnershipSession()
        let proposedContextSession = ReceiverNotificationOwnershipSession()

        let registration = registry.register(
            locationID: 1,
            proposed: proposedContextSession,
            existingChannelSession: existingChannelSession
        )
        let resolution = registry.resolveForOpen(
            locationID: 1,
            proposed: ReceiverNotificationOwnershipSession()
        )

        XCTAssertIdentical(registration.session, existingChannelSession)
        XCTAssertIdentical(resolution.session, existingChannelSession)
        XCTAssertTrue(registry.permitsAdoption(locationID: 1, resolution: resolution))
    }

    func testNotificationSessionRegistrationJoinsExternalOpenPreparedBeforeContext() {
        let registry = ReceiverNotificationOwnershipSessionRegistry()
        let externalResolution = registry.resolveForOpen(
            locationID: 1,
            proposed: ReceiverNotificationOwnershipSession()
        )
        let contextSession = ReceiverNotificationOwnershipSession()

        let registration = registry.register(
            locationID: 1,
            proposed: contextSession,
            existingChannelSession: nil
        )
        let contextResolution = registry.resolveForOpen(
            locationID: 1,
            proposed: ReceiverNotificationOwnershipSession()
        )

        XCTAssertIdentical(registration.session, externalResolution.session)
        XCTAssertTrue(registry.permitsAdoption(locationID: 1, resolution: externalResolution))
        XCTAssertTrue(registry.permitsAdoption(locationID: 1, resolution: contextResolution))
        XCTAssertIdentical(contextResolution.session, externalResolution.session)
    }

    func testNotificationSessionRegistrationUnregistersOnlyExactContext() {
        let registry = ReceiverNotificationOwnershipSessionRegistry()
        let contextSession = ReceiverNotificationOwnershipSession()
        let unrelatedSession = ReceiverNotificationOwnershipSession()
        let registration = registry.register(
            locationID: 1,
            proposed: contextSession,
            existingChannelSession: nil
        )
        let registeredResolution = registry.resolveForOpen(
            locationID: 1,
            proposed: ReceiverNotificationOwnershipSession()
        )
        let unrelatedRegistration = ReceiverNotificationOwnershipSessionRegistry.Registration(
            session: unrelatedSession
        )

        registry.unregister(locationID: 1, registration: unrelatedRegistration)
        XCTAssertTrue(registry.permitsAdoption(locationID: 1, resolution: registeredResolution))

        registry.unregister(locationID: 1, registration: registration)
        XCTAssertFalse(registry.permitsAdoption(locationID: 1, resolution: registeredResolution))

        let freshResolution = registry.resolveForOpen(
            locationID: 1,
            proposed: unrelatedSession
        )
        XCTAssertTrue(registry.permitsAdoption(locationID: 1, resolution: freshResolution))
    }

    func testReceiverNotificationEnableWriteFailureDoesNotCaptureOwnership() throws {
        let store = ReceiverNotificationOwnershipStore()
        let target = try XCTUnwrap(ReceiverNotificationOwnershipTarget.receiver(
            vendorID: 0x046D,
            serialNumber: "RECEIVER-A"
        ))
        var writeCount = 0

        XCTAssertFalse(store.enable(
            0x000100,
            for: target,
            read: { 0 },
            write: { _ in
                writeCount += 1
                return false
            }
        ))
        XCTAssertEqual(writeCount, 1)
        XCTAssertNil(store.claim(for: target))
    }

    func testReceiverNotificationEnableClaimsCommittedWriteWhenReplyIsLost() throws {
        let store = ReceiverNotificationOwnershipStore()
        let target = try XCTUnwrap(ReceiverNotificationOwnershipTarget.receiver(
            vendorID: 0x046D,
            serialNumber: "RECEIVER-A"
        ))
        let preexisting: UInt32 = 0x000100
        let added: UInt32 = 0x000800
        var flags = preexisting
        var writeCount = 0

        XCTAssertTrue(store.enable(
            preexisting | added,
            for: target,
            read: { flags },
            write: { value in
                writeCount += 1
                flags = value
                return false // The receiver committed it, but its reply was lost.
            }
        ))

        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(store.claim(for: target)?.ownedBits, added)
    }

    func testReceiverNotificationCommitIsOwnedBeforeTerminalAdmissionCancelsAckWait() throws {
        let store = ReceiverNotificationOwnershipStore()
        let target = try XCTUnwrap(ReceiverNotificationOwnershipTarget.receiver(
            vendorID: 0x046D,
            serialNumber: "RECEIVER-A"
        ))
        var producerAdmitted = true

        XCTAssertFalse(store.enable(
            0x000100,
            for: target,
            read: { 0 },
            committingWrite: { _, didCommit in
                didCommit() // IOHIDDeviceSetReport returned success.
                producerAdmitted = false // Terminal admission closes before ACK.
                return false
            },
            shouldContinue: { producerAdmitted }
        ))

        XCTAssertEqual(store.claim(for: target)?.ownedBits, 0x000100)
    }

    func testReceiverNotificationRestoreFailureRetainsOwnership() throws {
        let store = ReceiverNotificationOwnershipStore()
        let target = try XCTUnwrap(ReceiverNotificationOwnershipTarget.receiver(
            vendorID: 0x046D,
            serialNumber: "RECEIVER-A"
        ))
        var flags: UInt32 = 0
        XCTAssertTrue(store.enable(
            0x000100,
            for: target,
            read: { flags },
            write: {
                flags = $0
                return true
            }
        ))
        let claim = try XCTUnwrap(store.claim(for: target))

        XCTAssertFalse(store.restoreOwnedBits(
            for: target,
            read: { flags },
            write: { _ in false }
        ))
        XCTAssertEqual(store.claim(for: target), claim)
    }

    func testReceiverNotificationRestoreUsesReadbackWhenReplyIsLost() throws {
        let store = ReceiverNotificationOwnershipStore()
        let target = try XCTUnwrap(ReceiverNotificationOwnershipTarget.receiver(
            vendorID: 0x046D,
            serialNumber: "RECEIVER-A"
        ))
        let ownedBit: UInt32 = 0x000800
        var flags: UInt32 = 0

        XCTAssertTrue(store.enable(
            ownedBit,
            for: target,
            read: { flags },
            write: {
                flags = $0
                return true
            }
        ))

        XCTAssertTrue(store.restoreOwnedBits(
            for: target,
            read: { flags },
            write: {
                flags = $0
                return false // The write committed, but its reply was lost.
            }
        ))

        XCTAssertEqual(flags, 0)
        XCTAssertNil(store.claim(for: target))
    }

    func testReceiverNotificationOwnershipRejectsReplacementAndStaleHandle() throws {
        let store = ReceiverNotificationOwnershipStore()
        let original = try XCTUnwrap(ReceiverNotificationOwnershipTarget.receiver(
            vendorID: 0x046D,
            serialNumber: "RECEIVER-A"
        ))
        let replacement = try XCTUnwrap(ReceiverNotificationOwnershipTarget.receiver(
            vendorID: 0x046D,
            serialNumber: "RECEIVER-B"
        ))
        var flags: UInt32 = 0

        XCTAssertTrue(store.enable(
            0x000100,
            for: original,
            read: { flags },
            write: {
                flags = $0
                return true
            }
        ))
        let stale = try XCTUnwrap(store.claim(for: original))
        XCTAssertFalse(stale.handle.belongs(to: replacement))
        XCTAssertNil(store.claim(for: replacement))

        XCTAssertTrue(store.restoreOwnedBits(
            for: original,
            read: { flags },
            write: {
                flags = $0
                return true
            }
        ))
        XCTAssertTrue(store.enable(
            0x000100,
            for: original,
            read: { flags },
            write: {
                flags = $0
                return true
            }
        ))
        let current = try XCTUnwrap(store.claim(for: original))
        XCTAssertFalse(stale.handle.ownsSameEntry(as: current.handle))
        XCTAssertFalse(store.consumeRestoredBits(stale.handle))
        XCTAssertEqual(store.claim(for: original), current)
    }

    func testReceiverNotificationRestoreRejectsStaleChannelAndRetainsOwnership() {
        let store = ReceiverNotificationOwnershipStore()
        let session = ReceiverNotificationSessionIdentity()
        let target = ReceiverNotificationOwnershipTarget.session(session)
        var flags: UInt32 = 0
        XCTAssertTrue(store.enable(
            0x000100,
            for: target,
            read: { flags },
            write: {
                flags = $0
                return true
            }
        ))
        var readCount = 0
        var writeCount = 0

        XCTAssertFalse(store.restoreOwnedBits(
            for: target,
            read: {
                readCount += 1
                return flags
            },
            write: { _ in
                writeCount += 1
                return true
            },
            shouldContinue: { false }
        ))
        XCTAssertEqual(readCount, 0)
        XCTAssertEqual(writeCount, 0)
        XCTAssertNotNil(store.claim(for: target))
    }

    func testOrdinaryRetirementBudgetCancelsRemainingRestoreIOAndRetainsOwnership() {
        let start = Date(timeIntervalSince1970: 1000)
        let budget = ReceiverChannelRetirementBudget(now: start)
        let store = ReceiverNotificationOwnershipStore()
        let target = ReceiverNotificationOwnershipTarget.session(ReceiverNotificationSessionIdentity())
        var now = start
        var flags: UInt32 = 0
        XCTAssertTrue(store.enable(
            0x000100,
            for: target,
            read: { flags },
            write: {
                flags = $0
                return true
            }
        ))
        var writeCount = 0

        XCTAssertFalse(store.restoreOwnedBits(
            for: target,
            read: {
                now = budget.deadline
                return flags
            },
            write: { _ in
                writeCount += 1
                return true
            },
            shouldContinue: {
                budget.shouldContinue(now: now, transportIsActive: true)
            }
        ))

        XCTAssertEqual(writeCount, 0)
        XCTAssertNotNil(store.claim(for: target))
        XCTAssertFalse(budget.shouldContinue(now: start, transportIsActive: false))
        XCTAssertEqual(budget.deadline.timeIntervalSince(start), 0.25, accuracy: 0.001)
    }

    func testReceiverNotificationNoOwnershipRestoresWithoutIO() {
        let store = ReceiverNotificationOwnershipStore()
        let target = ReceiverNotificationOwnershipTarget.session(ReceiverNotificationSessionIdentity())
        var readCount = 0
        var writeCount = 0

        XCTAssertTrue(store.restoreOwnedBits(
            for: target,
            read: {
                readCount += 1
                return 0
            },
            write: { _ in
                writeCount += 1
                return true
            }
        ))
        XCTAssertEqual(readCount, 0)
        XCTAssertEqual(writeCount, 0)
    }

    private func slot(
        slot: UInt8,
        kind: UInt8 = 0x02,
        name: String? = nil,
        serialNumber: String? = nil,
        productID: Int? = nil
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverSlotMatchCandidate {
        .init(
            slot: slot,
            kind: kind,
            name: name,
            serialNumber: serialNumber,
            productID: productID,
            batteryLevel: nil,
            hasLiveMetadata: name != nil || serialNumber != nil || productID != nil
        )
    }

    private func mouseDevice() -> MockVendorSpecificDeviceContext {
        MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: nil,
            product: "Mouse",
            transport: PointerDeviceTransportName.usb,
            primaryUsagePage: kHIDPage_GenericDesktop,
            primaryUsage: kHIDUsage_GD_Mouse
        )
    }
}
