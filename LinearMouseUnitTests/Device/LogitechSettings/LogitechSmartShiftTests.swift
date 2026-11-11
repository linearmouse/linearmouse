// MIT License
// Copyright (c) 2021-2026 LinearMouse

import HIDPP
@testable import LinearMouse
import XCTest

/// Covers SmartShift configuration, target, restore, and baseline behavior.
final class LogitechSmartShiftTests: XCTestCase {
    private let baseline = SmartShift.Status(wheelMode: .freeSpin, autoDisengage: 16, torque: 50)

    func testConfigurationRoundTripsThresholdAndNever() throws {
        let configuration = try Configuration.load(from: #"""
        {
          "schemes": [
            { "logitech": { "smartShift": { "mode": "ratchet", "autoDisengage": 35, "torque": 75 } } },
            { "logitech": { "smartShift": { "mode": "freeSpin", "autoDisengage": "never" } } }
          ]
        }
        """#)

        XCTAssertEqual(
            configuration.schemes[0].logitech.smartShift,
            .init(mode: .ratchet, autoDisengage: .threshold(35), torque: 75)
        )
        XCTAssertEqual(
            configuration.schemes[1].logitech.smartShift,
            .init(mode: .freeSpin, autoDisengage: .never)
        )

        let reloaded = try Configuration.load(from: configuration.dump())
        XCTAssertEqual(reloaded.schemes[0].logitech, configuration.schemes[0].logitech)
        XCTAssertEqual(reloaded.schemes[1].logitech, configuration.schemes[1].logitech)
    }

    func testConfigurationRejectsAnUnknownAutoDisengageString() {
        XCTAssertThrowsError(try Configuration.load(from: #"""
        { "schemes": [{ "logitech": { "smartShift": { "autoDisengage": "always" } } }] }
        """#))
    }

    func testMergeOverridesOnlyConfiguredFields() {
        var scheme = Scheme()
        var base = Scheme()
        base.logitech.smartShift = .init(mode: .ratchet, autoDisengage: .threshold(35), torque: 75)
        base.merge(into: &scheme)

        var override = Scheme()
        override.logitech.smartShift = .init(mode: .freeSpin)
        override.merge(into: &scheme)

        XCTAssertEqual(
            scheme.logitech.smartShift,
            .init(mode: .freeSpin, autoDisengage: .threshold(35), torque: 75)
        )
    }

    func testTargetClampsToWireRangesAndIgnoresEmptyConfiguration() {
        XCTAssertNil(LogitechSmartShiftTarget(nil))
        XCTAssertNil(LogitechSmartShiftTarget(.init()))

        let target = LogitechSmartShiftTarget(.init(autoDisengage: .threshold(400), torque: 0))
        XCTAssertNil(target?.wheelMode)
        XCTAssertEqual(target?.autoDisengage, 254)
        XCTAssertEqual(target?.torque, 1)
        XCTAssertEqual(LogitechSmartShiftTarget(.init(autoDisengage: .never))?.autoDisengage, 0xFF)
    }

    func testTargetWritesTorqueOnlyOnWheelsThatSupportIt() throws {
        let target = try XCTUnwrap(LogitechSmartShiftTarget(
            .init(mode: .ratchet, autoDisengage: .threshold(35), torque: 75)
        ))

        XCTAssertEqual(
            target.change(supportsTunableTorque: true, managedFields: [], baseline: baseline),
            .init(wheelMode: .ratchet, autoDisengage: 35, torque: 75)
        )
        XCTAssertEqual(
            target.change(supportsTunableTorque: false, managedFields: [], baseline: baseline),
            .init(wheelMode: .ratchet, autoDisengage: 35)
        )
        XCTAssertEqual(target.fields(supportsTunableTorque: false), [.wheelMode, .autoDisengage])
    }

    func testTargetReturnsNoLongerConfiguredFieldsToTheirBaseline() throws {
        let target = try XCTUnwrap(LogitechSmartShiftTarget(.init(torque: 75)))

        let change = target.change(
            supportsTunableTorque: true,
            managedFields: [.wheelMode, .torque],
            baseline: baseline
        )

        // The mode LinearMouse set earlier goes back; the threshold it never
        // touched is left to the wheel.
        XCTAssertEqual(change, .init(wheelMode: .freeSpin, torque: 75))
    }

    func testChangeSatisfactionComparesOnlyWrittenFields() {
        let status = SmartShift.Status(wheelMode: .ratchet, autoDisengage: 35, torque: 75)

        XCTAssertTrue(SmartShift.Change(torque: 75).isSatisfied(by: status))
        XCTAssertTrue(SmartShift.Change().isSatisfied(by: status))
        XCTAssertFalse(SmartShift.Change(wheelMode: .freeSpin, torque: 75).isSatisfied(by: status))
    }

    func testRestoreChangeSkipsATorqueTheBaselineDidNotReport() {
        let standardBaseline = SmartShift.Status(wheelMode: .ratchet, autoDisengage: 10, torque: nil)

        XCTAssertEqual(
            LogitechSmartShiftFields.restoreChange([.wheelMode, .torque], from: standardBaseline),
            .init(wheelMode: .ratchet)
        )
    }

    func testRestoreUsesReadbackWhenWriteAcknowledgementIsLost() {
        var hardware = SmartShift.Status(wheelMode: .ratchet, autoDisengage: 35, torque: 75)
        var writes = [SmartShift.Change]()

        let restored = LogitechSmartShiftRestoreOperation.perform(
            change: .init(wheelMode: .freeSpin, torque: 50),
            shouldContinue: { true },
            readCurrentStatus: { hardware },
            write: { change in
                writes.append(change)
                // The write lands, but its reply is never seen.
                hardware = .init(wheelMode: .freeSpin, autoDisengage: 35, torque: 50)
            }
        )

        XCTAssertEqual(restored, .init(wheelMode: .freeSpin, autoDisengage: 35, torque: 50))
        XCTAssertEqual(writes, [.init(wheelMode: .freeSpin, torque: 50)])
    }

    func testRestoreSkipsTheWriteWhenTheWheelAlreadyMatches() {
        var writes = 0

        let restored = LogitechSmartShiftRestoreOperation.perform(
            change: .init(wheelMode: .freeSpin),
            shouldContinue: { true },
            readCurrentStatus: { self.baseline },
            write: { _ in writes += 1 }
        )

        XCTAssertEqual(restored, baseline)
        XCTAssertEqual(writes, 0)
    }

    func testRestoreFailsWhenReadbackDoesNotMatch() {
        let restored = LogitechSmartShiftRestoreOperation.perform(
            change: .init(torque: 50),
            shouldContinue: { true },
            readCurrentStatus: { .init(wheelMode: .ratchet, autoDisengage: 35, torque: 75) },
            write: { _ in }
        )

        XCTAssertNil(restored)
    }

    func testWriteIsRejectedWhenBaselineCannotBeRead() {
        var records = 0

        XCTAssertFalse(LogitechSmartShiftBaselineCapture.ensureCaptured(
            hasInitialState: { false },
            readCurrentStatus: { nil },
            record: { _ in records += 1 }
        ))
        XCTAssertEqual(records, 0)
    }

    func testBaselineFirstWriterWinsAndManagedFieldsAccumulate() throws {
        let store = LogitechHardwareBaselineStore()
        let target = try XCTUnwrap(LogitechHardwareTargetKey.direct(
            transport: "Bluetooth Low Energy",
            locationID: 42,
            vendorID: 0x046D,
            productID: 0xB042,
            serialNumber: "ABC123",
            name: "MX Master"
        ))

        let first = store.captureSmartShiftBaseline(baseline, managedFields: [.torque], for: target)
        let duplicate = store.captureSmartShiftBaseline(
            .init(wheelMode: .ratchet, autoDisengage: 35, torque: 75),
            managedFields: [.wheelMode],
            for: target
        )

        XCTAssertEqual(duplicate.baseline.status, baseline)
        XCTAssertEqual(duplicate.managedFields, [.torque, .wheelMode])
        XCTAssertEqual(first.handle, duplicate.handle)
        XCTAssertTrue(store.addSmartShiftManagedFields([.autoDisengage], to: first.handle))
        XCTAssertEqual(
            store.smartShiftBaseline(for: target)?.managedFields,
            [.torque, .wheelMode, .autoDisengage]
        )
        XCTAssertTrue(store.consumeSmartShiftBaseline(first.handle))
        XCTAssertNil(store.smartShiftBaseline(for: target))

        let replacement = store.captureSmartShiftBaseline(baseline, managedFields: [], for: target)
        XCTAssertFalse(store.consumeSmartShiftBaseline(first.handle))
        XCTAssertFalse(store.addSmartShiftManagedFields([.torque], to: first.handle))
        XCTAssertEqual(store.smartShiftBaseline(for: target)?.managedFields, [])
        XCTAssertEqual(store.smartShiftBaseline(for: target)?.handle, replacement.handle)
    }

    func testThresholdSliderPrefersConfiguredThenCurrentThenDeviceDefault() {
        XCTAssertEqual(
            ScrollingSettingsState.smartShiftSliderThreshold(configured: 35, current: 20, deviceDefault: 10),
            35
        )
        XCTAssertEqual(
            ScrollingSettingsState.smartShiftSliderThreshold(configured: nil, current: 20, deviceDefault: 10),
            20
        )
        // A permanently ratcheted wheel reports no threshold of its own.
        XCTAssertEqual(
            ScrollingSettingsState.smartShiftSliderThreshold(configured: nil, current: 0xFF, deviceDefault: 10),
            10
        )
        XCTAssertEqual(
            ScrollingSettingsState.smartShiftSliderThreshold(configured: nil, current: nil, deviceDefault: nil),
            16
        )
    }

    func testThresholdSliderStaysInsideItsBand() {
        // Above the band clamps; below it is replaced by the default, which
        // must itself be inside the band.
        XCTAssertEqual(
            ScrollingSettingsState.smartShiftSliderThreshold(configured: 254, current: nil, deviceDefault: 10),
            50
        )
        XCTAssertEqual(
            ScrollingSettingsState.smartShiftSliderThreshold(configured: 3, current: nil, deviceDefault: 10),
            10
        )
        XCTAssertEqual(
            ScrollingSettingsState.smartShiftSliderThreshold(configured: 3, current: nil, deviceDefault: 4),
            16
        )
    }
}
