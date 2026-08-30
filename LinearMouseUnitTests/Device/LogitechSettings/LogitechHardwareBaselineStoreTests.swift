// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class LogitechHardwareBaselineStoreTests: XCTestCase {
    func testDPIFirstWriterWinsAndStaleOwnershipCannotConsumeReplacement() throws {
        let store = LogitechHardwareBaselineStore()
        let target = try directTarget(serial: "ABC123")

        let first = store.captureDPIBaseline(800, for: target)
        let duplicate = store.captureDPIBaseline(8000, for: target)

        XCTAssertEqual(first.baseline, .init(value: 800))
        XCTAssertEqual(duplicate.baseline, .init(value: 800))
        XCTAssertEqual(first.handle, duplicate.handle)
        XCTAssertTrue(first.handle.belongs(to: target))
        XCTAssertTrue(store.consumeDPIBaseline(first.handle))

        let replacement = store.captureDPIBaseline(1200, for: target)
        XCTAssertFalse(store.consumeDPIBaseline(first.handle))
        XCTAssertEqual(store.dpiBaseline(for: target)?.baseline, replacement.baseline)
    }

    func testDPIIsCapturedBeforeAWriteWhoseAcknowledgementIsLost() throws {
        let store = LogitechHardwareBaselineStore()
        let target = try directTarget(serial: "ABC123")
        var hardwareDPI = 800
        var captured = false

        XCTAssertTrue(LogitechDPIBaselineCapture.ensureCaptured(
            hasInitialState: { captured },
            readCurrentDPI: { hardwareDPI },
            record: { dpi in
                _ = store.captureDPIBaseline(dpi, for: target)
                captured = true
            }
        ))

        // The hardware accepts 8000, but the host loses the acknowledgement.
        hardwareDPI = 8000

        XCTAssertEqual(store.dpiBaseline(for: target)?.baseline, .init(value: 800))
    }

    func testDPIWriteIsRejectedWhenBaselineCannotBeRead() {
        var writes = 0

        let admitted = LogitechDPIBaselineCapture.ensureCaptured(
            hasInitialState: { false },
            readCurrentDPI: { nil },
            record: { _ in writes += 1 }
        )

        XCTAssertFalse(admitted)
        XCTAssertEqual(writes, 0)
    }

    func testDPIRestoreUsesReadbackWhenWriteAcknowledgementIsLost() {
        var hardwareDPI = 8000
        var writes = 0

        let restored = LogitechDPIRestoreOperation.perform(
            initialDPI: 800,
            shouldContinue: { true },
            readCurrentDPI: { hardwareDPI },
            writeDPI: { dpi in
                writes += 1
                hardwareDPI = dpi
                // The helper deliberately has no acknowledgement result.
            }
        )

        XCTAssertTrue(restored)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(hardwareDPI, 800)
    }

    func testFailedDPIReadbackDoesNotAuthorizeBaselineConsumption() throws {
        let store = LogitechHardwareBaselineStore()
        let target = try directTarget(serial: "ABC123")
        _ = store.captureDPIBaseline(800, for: target)
        var hardwareDPI = 8000

        let restored = LogitechDPIRestoreOperation.perform(
            initialDPI: 800,
            shouldContinue: { true },
            readCurrentDPI: { hardwareDPI },
            writeDPI: { _ in
                // Simulate a rejected write.
                hardwareDPI = 8000
            }
        )

        XCTAssertFalse(restored)
        XCTAssertEqual(store.dpiBaseline(for: target)?.baseline, .init(value: 800))
    }

    func testHiResFirstWriterWinsAndStaleOwnershipCannotConsumeReplacement() throws {
        let store = LogitechHardwareBaselineStore()
        let target = try directTarget(serial: "ABC123")

        let first = store.captureHiResBaseline(enabled: false, for: target)
        let duplicate = store.captureHiResBaseline(enabled: true, for: target)

        XCTAssertEqual(first.baseline, .init(enabled: false))
        XCTAssertEqual(duplicate.baseline, .init(enabled: false))
        XCTAssertEqual(first.handle, duplicate.handle)
        XCTAssertTrue(store.consumeHiResBaseline(first.handle))

        let replacement = store.captureHiResBaseline(enabled: true, for: target)
        XCTAssertFalse(store.consumeHiResBaseline(first.handle))
        XCTAssertEqual(store.hiResBaseline(for: target)?.baseline, .init(enabled: true))
        XCTAssertEqual(replacement.baseline, .init(enabled: true))
    }

    func testStableSerialClaimsBaselineAcrossDirectAndReceiverSessions() throws {
        let direct = try directTarget(serial: "abc123")
        let receiver = try XCTUnwrap(LogitechHardwareTargetKey.receiver(
            vendorID: 0x046D,
            receiverLocationID: 123,
            identity: receiverIdentity(serial: "ABC123", productID: 0xB034)
        ))
        let store = LogitechHardwareBaselineStore()

        XCTAssertEqual(direct, receiver)
        _ = store.captureHiResBaseline(enabled: false, for: direct)

        let rebuiltSession = LogitechDeviceSession(deviceID: 2)
        let claim = try XCTUnwrap(store.hiResBaseline(for: receiver))
        let lease = try XCTUnwrap(rebuiltSession.hiResWheelTargetLease(
            receiverSlot: nil
        ) { _, _ in receiver })
        XCTAssertTrue(rebuiltSession.seedInitialHiResWheelState(claim, for: lease))

        XCTAssertTrue(store.consumeHiResBaseline(claim.handle))
        XCTAssertNil(store.hiResBaseline(for: direct))
    }

    func testStableSerialDoesNotRequireTransportLocationNameOrProductMetadata() throws {
        let direct = try XCTUnwrap(LogitechHardwareTargetKey.direct(
            transport: nil,
            locationID: nil,
            vendorID: 0x046D,
            productID: nil,
            serialNumber: "abc123",
            name: nil
        ))
        let receiver = try XCTUnwrap(LogitechHardwareTargetKey.receiver(
            vendorID: 0x046D,
            receiverLocationID: nil,
            identity: .init(
                receiverLocationID: 0,
                slot: 1,
                kind: .mouse,
                name: "",
                serialNumber: "ABC123",
                productID: nil,
                batteryLevel: nil
            )
        ))

        XCTAssertEqual(direct, receiver)
    }

    func testDifferentStableSerialsNeverShareABaselineKey() throws {
        XCTAssertNotEqual(try directTarget(serial: "AAAA"), try directTarget(serial: "BBBB"))
    }

    func testReceiverWithoutStableSerialCannotClaimProcessBaseline() {
        let legacyIdentity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 123,
            slot: 2,
            kind: .mouse,
            name: "USB Receiver",
            serialNumber: nil,
            productID: 0xC52F,
            batteryLevel: nil
        )
        let target = LogitechHardwareTargetKey.receiver(
            vendorID: 0x046D,
            receiverLocationID: 123,
            identity: legacyIdentity
        )

        XCTAssertNil(target)
    }

    func testDirectDeviceWithoutStableSerialCannotClaimProcessBaseline() {
        let target = LogitechHardwareTargetKey.direct(
            transport: "Bluetooth Low Energy",
            locationID: 42,
            vendorID: 0x046D,
            productID: 0xB034,
            serialNumber: nil,
            name: "MX Master"
        )

        XCTAssertNil(target)
    }

    func testMissingSerialSentinelsCannotClaimProcessBaseline() {
        for serial in ["00000000", "FF:FF:FF:FF"] {
            XCTAssertNil(LogitechHardwareTargetKey.direct(
                transport: "Bluetooth Low Energy",
                locationID: 42,
                vendorID: 0x046D,
                productID: 0xB034,
                serialNumber: serial,
                name: "Mouse"
            ))
            XCTAssertNil(LogitechHardwareTargetKey.receiver(
                vendorID: 0x046D,
                receiverLocationID: 123,
                identity: receiverIdentity(serial: serial, productID: 0xB034)
            ))
        }
    }

    func testReceiverReplacementWithDifferentSerialCannotClaimBaseline() throws {
        let store = LogitechHardwareBaselineStore()
        let original = try XCTUnwrap(LogitechHardwareTargetKey.receiver(
            vendorID: 0x046D,
            receiverLocationID: 123,
            identity: receiverIdentity(serial: "AAAA", productID: 0xB034)
        ))
        let replacement = try XCTUnwrap(LogitechHardwareTargetKey.receiver(
            vendorID: 0x046D,
            receiverLocationID: 123,
            identity: receiverIdentity(serial: "BBBB", productID: 0xB034)
        ))

        _ = store.captureHiResBaseline(enabled: false, for: original)

        XCTAssertNil(store.hiResBaseline(for: replacement))
        XCTAssertNotNil(store.hiResBaseline(for: original))
    }

    func testRouteMismatchedSessionCannotSeedReceiverBaseline() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let current = route(serial: "AAAA")
        let replacement = route(serial: "BBBB")
        _ = session.updateDiscovery(.init(identities: [current.identity], route: current))
        let store = LogitechHardwareBaselineStore()
        let replacementTarget = try XCTUnwrap(LogitechHardwareTargetKey.receiver(
            vendorID: 0x046D,
            receiverLocationID: replacement.identity.receiverLocationID,
            identity: replacement.identity
        ))
        let claim = store.captureHiResBaseline(enabled: false, for: replacementTarget)
        let currentTarget = try XCTUnwrap(LogitechHardwareTargetKey.receiver(
            vendorID: 0x046D,
            receiverLocationID: current.identity.receiverLocationID,
            identity: current.identity
        ))
        let lease = try XCTUnwrap(session.hiResWheelTargetLease(
            receiverSlot: current.slot
        ) { _, _ in currentTarget })

        XCTAssertFalse(session.seedInitialHiResWheelState(claim, for: lease))
    }

    func testUnconsumedBaselineSurvivesAFailedRestoreAttempt() throws {
        let store = LogitechHardwareBaselineStore()
        let target = try directTarget(serial: "ABC123")
        _ = store.captureHiResBaseline(enabled: false, for: target)

        // A failed hardware write has no consume call.
        XCTAssertEqual(store.hiResBaseline(for: target)?.baseline, .init(enabled: false))
    }

    func testPreWriteCaptureSurvivesAWriteWhoseReplyIsLost() throws {
        let target = try directTarget(serial: "ABC123")
        let store = LogitechHardwareBaselineStore()
        var hardwareMode = false

        var captured = false
        XCTAssertTrue(LogitechHiResBaselineCapture.ensureCaptured(
            hasInitialState: { captured },
            readCurrentMode: { hardwareMode }
        ) { initialMode in
            _ = store.captureHiResBaseline(enabled: initialMode, for: target)
            captured = true
        })

        // The device applies the write but its acknowledgement is lost.
        hardwareMode = true
        let rebuiltSession = LogitechDeviceSession(deviceID: 4)
        let claim = try XCTUnwrap(store.hiResBaseline(for: target))
        let lease = try XCTUnwrap(rebuiltSession.hiResWheelTargetLease(
            receiverSlot: nil
        ) { _, _ in target })
        XCTAssertTrue(rebuiltSession.seedInitialHiResWheelState(claim, for: lease))
    }

    func testHiResWriteIsRejectedWhenBaselineCannotBeRead() {
        var captured = false

        let admitted = LogitechHiResBaselineCapture.ensureCaptured(
            hasInitialState: { captured },
            readCurrentMode: { nil },
            capture: { _ in captured = true }
        )

        XCTAssertFalse(admitted)
        XCTAssertFalse(captured)
    }

    func testHiResRestoreUsesReadbackWhenWriteAcknowledgementIsLost() {
        var hardwareMode = false
        var writes = 0

        let restored = LogitechHiResRestoreOperation.perform(
            initialEnabled: true,
            shouldContinue: { true },
            readCurrentMode: { hardwareMode },
            writeMode: { enabled in
                writes += 1
                hardwareMode = enabled
                // The helper deliberately has no acknowledgement result.
            }
        )

        XCTAssertTrue(restored)
        XCTAssertEqual(writes, 1)
        XCTAssertTrue(hardwareMode)
    }

    func testHiResRestoreRequiresReadbackBeforeSuccess() {
        var hardwareMode = false

        let restored = LogitechHiResRestoreOperation.perform(
            initialEnabled: true,
            shouldContinue: { true },
            readCurrentMode: { hardwareMode },
            writeMode: { _ in hardwareMode = false }
        )

        XCTAssertFalse(restored)
    }

    func testLifecycleRestoreRetriesUntilAWriteSucceeds() {
        var calls = 0
        var delays = [TimeInterval]()

        let restored = LogitechHardwareRestoreRetry.perform(
            operation: {
                calls += 1
                return calls == 2
            },
            wait: { delays.append($0) }
        )

        XCTAssertTrue(restored)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(delays, [0.1])
    }

    func testLifecycleRestoreStopsAfterFiniteRetryBudget() {
        var calls = 0
        var delays = [TimeInterval]()

        let restored = LogitechHardwareRestoreRetry.perform(
            operation: {
                calls += 1
                return false
            },
            wait: { delays.append($0) }
        )

        XCTAssertFalse(restored)
        XCTAssertEqual(calls, LogitechHardwareRestoreRetry.maximumAttempts)
        XCTAssertEqual(delays, [0.1, 0.2])
    }

    func testLifecycleRestoreSkipsFeatureAccessWithoutInitialOrBaseline() {
        var featureAccesses = 0

        if LogitechHiResRestoreAdmission.needsFeatureAccess(
            hasSessionInitial: false,
            hasKnownBaseline: false
        ) {
            featureAccesses += 1
        }

        XCTAssertEqual(featureAccesses, 0)
    }

    func testControlsBaselineFirstWriterWinsAndConsumesPerControl() throws {
        let store = LogitechHardwareBaselineStore()
        let target = try directTarget(serial: "ABC123")
        let native = LogitechHardwareBaselineStore.ControlsReportingBaseline(
            flagsRawValue: 0,
            mappedControlID: 0x00C3
        )
        let diverted = LogitechHardwareBaselineStore.ControlsReportingBaseline(
            flagsRawValue: 1,
            mappedControlID: 0x00C3
        )

        let first = store.captureControlsBaseline(native, controlID: 0x00C3, for: target)
        let duplicate = store.captureControlsBaseline(diverted, controlID: 0x00C3, for: target)
        let other = store.captureControlsBaseline(native, controlID: 0x00C4, for: target)

        XCTAssertEqual(duplicate.baseline, native)
        XCTAssertEqual(duplicate.handle, first.handle)
        XCTAssertTrue(store.consumeControlsBaseline(first.handle))
        XCTAssertNil(store.controlsBaseline(for: target, controlID: 0x00C3))
        XCTAssertEqual(store.controlsBaseline(for: target, controlID: 0x00C4)?.handle, other.handle)
    }

    func testControlsBaselineRejectsStaleHandleAndDifferentSerial() throws {
        let store = LogitechHardwareBaselineStore()
        let original = try directTarget(serial: "AAAA")
        let replacement = try directTarget(serial: "BBBB")
        let baseline = LogitechHardwareBaselineStore.ControlsReportingBaseline(
            flagsRawValue: 0,
            mappedControlID: 0x00C3
        )

        let old = store.captureControlsBaseline(baseline, controlID: 0x00C3, for: original)
        XCTAssertNil(store.controlsBaseline(for: replacement, controlID: 0x00C3))
        XCTAssertTrue(store.consumeControlsBaseline(old.handle))

        let new = store.captureControlsBaseline(baseline, controlID: 0x00C3, for: original)
        XCTAssertFalse(store.consumeControlsBaseline(old.handle))
        XCTAssertEqual(store.controlsBaseline(for: original, controlID: 0x00C3)?.handle, new.handle)
    }

    private func directTarget(serial: String) throws -> LogitechHardwareTargetKey {
        try XCTUnwrap(LogitechHardwareTargetKey.direct(
            transport: "Bluetooth Low Energy",
            locationID: 42,
            vendorID: 0x046D,
            productID: 0xB034,
            serialNumber: serial,
            name: "MX Master"
        ))
    }

    private func receiverIdentity(serial: String, productID: Int) -> ReceiverLogicalDeviceIdentity {
        .init(
            receiverLocationID: 123,
            slot: 1,
            kind: .mouse,
            name: "MX Master",
            serialNumber: serial,
            productID: productID,
            batteryLevel: nil
        )
    }

    private func route(serial: String) -> LogitechReceiverRoute {
        let identity = receiverIdentity(serial: serial, productID: 0xB034)
        return .init(slot: identity.slot, identity: identity)
    }
}
