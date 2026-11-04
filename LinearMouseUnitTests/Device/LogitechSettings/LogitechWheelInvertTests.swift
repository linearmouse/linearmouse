// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
@testable import HIDPP
@testable import LinearMouse
import PointerKit
import XCTest

/// Covers the invert bit of the HID++ Hi-Res Wheel feature, its session state,
/// and its process-lifetime baseline.
final class LogitechWheelInvertTests: XCTestCase {
    // MARK: HID++ mode byte

    func testReadsInvertBitWithoutResolutionBit() throws {
        let (_, wheel) = try wheel(mode: 0x04)

        XCTAssertEqual(wheel.isWheelInverted(), true)
        XCTAssertEqual(wheel.isHighResolutionWheelEnabled(), false)
    }

    func testSettingInvertPreservesResolutionAndTargetBits() throws {
        let (device, wheel) = try wheel(mode: 0x03)

        XCTAssertEqual(wheel.setWheelInverted(true), true)
        XCTAssertEqual(
            device.sentReports.last.map { Array($0.prefix(5)) },
            Optional([0x11, 0xFF, 0x1E, 0x28, 0x07] as [UInt8])
        )
    }

    func testClearingInvertPreservesResolutionBit() throws {
        let (device, wheel) = try wheel(mode: 0x06)

        XCTAssertEqual(wheel.setWheelInverted(false), false)
        XCTAssertEqual(
            device.sentReports.last.map { Array($0.prefix(5)) },
            Optional([0x11, 0xFF, 0x1E, 0x28, 0x02] as [UInt8])
        )
    }

    func testHighResolutionWritePreservesInvertBit() throws {
        let (device, wheel) = try wheel(mode: 0x04)

        XCTAssertEqual(wheel.setHighResolutionWheelEnabled(true), true)
        XCTAssertEqual(
            device.sentReports.last.map { Array($0.prefix(5)) },
            Optional([0x11, 0xFF, 0x1E, 0x28, 0x06] as [UInt8])
        )
    }

    func testModeWriteEchoesUndocumentedModeBytes() throws {
        let (device, wheel) = try wheel(mode: 0x02, extensionBytes: [0x05, 0x07])

        XCTAssertEqual(wheel.setWheelInverted(true), true)
        XCTAssertEqual(
            device.sentReports.last.map { Array($0.prefix(7)) },
            Optional([0x11, 0xFF, 0x1E, 0x28, 0x06, 0x05, 0x07] as [UInt8])
        )
    }

    func testInvertCapabilityComesFromFlagBitThree() {
        XCTAssertTrue(HiResWheel.Capabilities(multiplier: 8, flags: 0x0C).supportsInversion)
        XCTAssertFalse(HiResWheel.Capabilities(multiplier: 8, flags: 0x04).supportsInversion)
    }

    func testSkipsWritingWhenInvertAlreadyMatches() throws {
        let (device, wheel) = try wheel(mode: 0x06)

        XCTAssertEqual(wheel.setWheelInverted(true), true)
        XCTAssertEqual(device.sentReports.count, 1)
        XCTAssertEqual([UInt8](device.sentReports[0])[3], 0x18)
    }

    func testInvertWriteLosesAdmissionAfterModeRead() throws {
        var admitted = true
        let (device, wheel) = try wheel(mode: 0x02) { admitted = false }

        XCTAssertNil(wheel.setWheelInverted(true) { admitted })
        XCTAssertEqual(device.sentReports.count, 1)
        XCTAssertEqual([UInt8](device.sentReports[0])[3], 0x18)
    }

    // MARK: Session

    func testWheelInvertPipelineIsIndependentOfHighResolution() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let invertAccess = try wheelInvertAccess(for: session)
        session.recordInitialWheelInvertState(inverted: false, for: invertAccess)
        session.updateWheelInverted(true, for: invertAccess)

        session.cancelHiResWheelApply()

        XCTAssertEqual(session.wheelInverted, true)
        XCTAssertEqual(session.initialWheelInverted(for: invertAccess), false)
        XCTAssertTrue(session.allowsConfiguredWheelInvertWrite(for: invertAccess))
    }

    func testSupersededWheelInvertAccessCannotMutateSessionState() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try wheelInvertAccess(for: session, receiverSlot: 2)

        session.cancelWheelInvertApply()
        session.recordInitialWheelInvertState(inverted: false, for: access)
        session.updateWheelInverted(true, for: access)

        XCTAssertNil(session.initialWheelInverted(for: access))
        XCTAssertNil(session.wheelInverted)
        XCTAssertFalse(session.hasInitialWheelInvertState)
    }

    func testWheelInvertRestoreCommitsOnlyTheOriginalDirection() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try wheelInvertAccess(for: session, receiverSlot: 2)
        session.recordInitialWheelInvertState(inverted: false, for: access)
        session.updateWheelInverted(true, for: access)

        guard case .rejected = session.completeWheelInvertRestore(inverted: true, for: access) else {
            XCTFail("A direction other than the original must not commit")
            return
        }
        XCTAssertTrue(session.hasInitialWheelInvertState)

        guard case .committed(nil) = session.completeWheelInvertRestore(inverted: false, for: access) else {
            XCTFail("The original direction should commit")
            return
        }
        XCTAssertEqual(session.wheelInverted, false)
        XCTAssertFalse(session.hasInitialWheelInvertState)
    }

    func testInitialWheelInvertStateIsBoundToHardwareTarget() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        _ = session.updateDiscovery(discovery(serialNumber: "AAAAAAAA", productID: 0xB034))
        let access = try wheelInvertAccess(for: session, receiverSlot: 2)
        session.recordInitialWheelInvertState(inverted: false, for: access)

        _ = session.updateDiscovery(discovery(serialNumber: "BBBBBBBB", productID: 0xB037))

        XCTAssertNil(session.initialWheelInverted(for: access))
    }

    func testNewWheelInvertDesiredCancelsRetryingRestore() {
        let session = LogitechDeviceSession(deviceID: 1)
        let restoreToken = session.startWheelInvertRestore { _, _ in false }

        session.startWheelInvertApply { _, _ in false }

        XCTAssertTrue(restoreToken.isCancelled)
    }

    func testHardwareSuspensionClearsConfirmedDirectionButKeepsBaseline() throws {
        let session = LogitechDeviceSession(deviceID: 1)
        let access = try wheelInvertAccess(for: session)
        session.recordInitialWheelInvertState(inverted: false, for: access)
        session.updateWheelInverted(true, for: access)

        _ = try XCTUnwrap(session.suspendHardware())

        XCTAssertNil(session.wheelInverted)
        XCTAssertTrue(session.hasInitialWheelInvertState)
    }

    func testTerminalRestoreKeepsWheelInvertTokenWhenAnotherFeatureIsCancelled() {
        let session = LogitechDeviceSession(deviceID: 1)
        let queueGate = DispatchSemaphore(value: 0)
        session.perform { queueGate.wait() }
        let ran = expectation(description: "terminal restore ran")

        session.runTerminalHardwareRestore { tokens, _ in
            XCTAssertFalse(tokens.wheel.shouldContinue)
            XCTAssertTrue(tokens.wheelInvert.shouldContinue)
            ran.fulfill()
        } onCancelled: {
            XCTFail("The terminal owner itself remains current")
        }

        session.cancelHiResWheelApply()
        queueGate.signal()
        wait(for: [ran], timeout: 1)
    }

    // MARK: Baseline store

    func testWheelInvertBaselineFirstWriterWinsAndStaleOwnershipCannotConsumeReplacement() throws {
        let store = LogitechHardwareBaselineStore()
        let target = try directTarget(serial: "ABC123")

        let first = store.captureWheelInvertBaseline(inverted: false, for: target)
        let duplicate = store.captureWheelInvertBaseline(inverted: true, for: target)

        XCTAssertEqual(first.baseline, .init(inverted: false))
        XCTAssertEqual(duplicate.baseline, .init(inverted: false))
        XCTAssertEqual(first.handle, duplicate.handle)
        XCTAssertTrue(store.consumeWheelInvertBaseline(first.handle))

        let replacement = store.captureWheelInvertBaseline(inverted: true, for: target)
        XCTAssertFalse(store.consumeWheelInvertBaseline(first.handle))
        XCTAssertEqual(store.wheelInvertBaseline(for: target)?.baseline, .init(inverted: true))
        XCTAssertEqual(replacement.baseline, .init(inverted: true))
    }

    func testRebuiltSessionSeedsWheelInvertBaselineFromStore() throws {
        let store = LogitechHardwareBaselineStore()
        let target = try directTarget(serial: "ABC123")
        _ = store.captureWheelInvertBaseline(inverted: false, for: target)

        let rebuiltSession = LogitechDeviceSession(deviceID: 2)
        let claim = try XCTUnwrap(store.wheelInvertBaseline(for: target))
        let lease = try XCTUnwrap(rebuiltSession.wheelInvertTargetLease(
            receiverSlot: nil
        ) { _, _ in target })

        XCTAssertTrue(rebuiltSession.seedInitialWheelInvertState(claim, for: lease))
        XCTAssertTrue(rebuiltSession.hasInitialWheelInvertState)
        // The high resolution baseline is separate and stays empty.
        XCTAssertFalse(rebuiltSession.hasInitialHiResWheelState)
    }

    // MARK: Helpers

    private func wheel(
        mode: UInt8,
        extensionBytes: [UInt8] = [0x00, 0x00],
        onModeRead: @escaping () -> Void = {}
    ) throws -> (MockVendorSpecificDeviceContext, HiResWheel) {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB042,
            transport: PointerDeviceTransportName.bluetoothLowEnergy,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            guard bytes.count >= 4, bytes[2] == 0x1E else {
                return nil
            }

            switch bytes[3] {
            case 0x18:
                onModeRead()
                return Self.hidppLongReply(featureIndex: 0x1E, address: 0x18, payload: [mode] + extensionBytes)
            case 0x28:
                return Self.hidppLongReply(featureIndex: 0x1E, address: 0x28, payload: [])
            default:
                return nil
            }
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))
        return (device, HiResWheel(transport: transport, featureIndex: 0x1E))
    }

    private func wheelInvertAccess(
        for session: LogitechDeviceSession,
        receiverSlot: UInt8? = nil
    ) throws -> LogitechDeviceSession.FeatureAccess<HiResWheel> {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xB042,
            transport: PointerDeviceTransportName.usb,
            maxInputReportSize: 20,
            maxOutputReportSize: 20
        )
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: receiverSlot))
        return try XCTUnwrap(session.wheelInvert { _, _ in
            .init(
                feature: HiResWheel(transport: transport, featureIndex: 1),
                stableTargetKey: nil,
                receiverSlot: receiverSlot
            )
        })
    }

    private func directTarget(serial: String) throws -> LogitechHardwareTargetKey {
        try XCTUnwrap(LogitechHardwareTargetKey.direct(
            transport: "Bluetooth Low Energy",
            locationID: 42,
            vendorID: 0x046D,
            productID: 0xB042,
            serialNumber: serial,
            name: "MX Master"
        ))
    }

    private func discovery(serialNumber: String, productID: Int) -> LogitechReceiverDiscovery {
        let identity = ReceiverLogicalDeviceIdentity(
            receiverLocationID: 123,
            slot: 2,
            kind: .mouse,
            name: "MX Mouse",
            serialNumber: serialNumber,
            productID: productID,
            batteryLevel: nil
        )
        return .init(
            identities: [identity],
            route: .init(slot: identity.slot, identity: identity)
        )
    }

    private static func hidppLongReply(
        featureIndex: UInt8,
        address: UInt8,
        payload: [UInt8]
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = 0x11
        bytes[1] = 0xFF
        bytes[2] = featureIndex
        bytes[3] = address
        for (index, byte) in payload.enumerated() where index + 4 < bytes.count {
            bytes[index + 4] = byte
        }
        return Data(bytes)
    }
}
