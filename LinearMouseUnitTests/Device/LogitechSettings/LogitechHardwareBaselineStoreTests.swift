// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class LogitechHardwareBaselineStoreTests: XCTestCase {
    func testHiResFirstWriterWinsAndStaleHandleCannotConsumeNewBaseline() throws {
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
        rebuiltSession.seedInitialHiResWheelState(enabled: claim.baseline.enabled, route: nil, receiverSlot: nil)

        XCTAssertEqual(rebuiltSession.initialHiResWheelEnabled(
            requiresReceiverRoute: false,
            receiverSlot: nil
        ), false)
        XCTAssertTrue(store.consumeHiResBaseline(claim.handle))
        XCTAssertNil(store.hiResBaseline(for: direct))
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

    func testRouteMismatchedSessionCannotSeedReceiverBaseline() {
        let session = LogitechDeviceSession(deviceID: 1)
        let current = route(serial: "AAAA")
        let replacement = route(serial: "BBBB")
        _ = session.updateDiscovery(.init(identities: [current.identity], route: current))

        session.seedInitialHiResWheelState(
            enabled: false,
            route: replacement,
            receiverSlot: replacement.slot
        )

        XCTAssertNil(session.initialHiResWheelEnabled(
            requiresReceiverRoute: true,
            receiverSlot: current.slot
        ))
    }

    func testUnconsumedBaselineSurvivesAFailedRestoreAttempt() throws {
        let store = LogitechHardwareBaselineStore()
        let target = try directTarget(serial: "ABC123")
        _ = store.captureHiResBaseline(enabled: false, for: target)

        // A failed hardware write has no consume call.
        XCTAssertEqual(store.hiResBaseline(for: target)?.baseline, .init(enabled: false))
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
