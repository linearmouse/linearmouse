// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class LogitechHighResolutionWheelNormalizerTests: XCTestCase {
    func testLowResolutionModeAccumulatesHighResolutionWheelUnits() throws {
        let transformer = LogitechHighResolutionWheelNormalizer(
            verticalMode: .lowResolution,
            horizontalMode: .passthrough,
            multiplier: { 8 },
            now: { 0 }
        )

        for _ in 0 ..< 3 {
            XCTAssertNil(try transformer.transform(makeVerticalHighResolutionScrollEvent()))
        }

        let transformedEvent = try XCTUnwrap(try transformer.transform(makeVerticalHighResolutionScrollEvent()))
        let view = ScrollWheelEventView(transformedEvent)

        XCTAssertFalse(view.continuous)
        XCTAssertEqual(view.deltaY, 1)
        XCTAssertEqual(view.deltaYPt, 10)
        XCTAssertEqual(view.deltaYFixedPt, 1)

        for _ in 0 ..< 4 {
            XCTAssertNil(try transformer.transform(makeVerticalHighResolutionScrollEvent()))
        }
    }

    func testLowResolutionModeUsesFixedPointUnitsWhenIntegerDeltaIsCoalesced() throws {
        let transformer = LogitechHighResolutionWheelNormalizer(
            verticalMode: .lowResolution,
            horizontalMode: .passthrough,
            multiplier: { 10 },
            now: { 0 }
        )

        let transformedEvent = try XCTUnwrap(try transformer.transform(
            makeVerticalHighResolutionScrollEvent(multiplier: 10, units: 17.390899658203125)
        ))
        let view = ScrollWheelEventView(transformedEvent)

        XCTAssertFalse(view.continuous)
        XCTAssertEqual(view.deltaY, 2)
        XCTAssertEqual(view.deltaYPt, 20)
        XCTAssertEqual(view.deltaYFixedPt, 2)
    }

    func testUnitReaderUsesAccelerationMagnitudeWhenIOHIDOnlyReportsRawTicks() {
        let resolution = LogitechHighResolutionWheelUnitReader.units(
            integerDelta: -6,
            pointDelta: -69,
            fixedPointDelta: -6.84417724609375,
            ioHidDelta: 1,
            signum: -1,
            multiplier: 8
        )

        XCTAssertEqual(resolution.rawUnits, -1, accuracy: 0.001)
        XCTAssertEqual(resolution.acceleratedUnits, -6.9, accuracy: 0.001)
        XCTAssertEqual(resolution.units, -6.9, accuracy: 0.001)
        XCTAssertEqual(
            normalizedPixels(for: resolution, multiplier: 8),
            -31.05,
            accuracy: 0.001
        )
    }

    func testUnitReaderUsesCoalescedEventDistanceWhenIOHIDDeltaIsSmaller() {
        let resolution = LogitechHighResolutionWheelUnitReader.units(
            integerDelta: -20,
            pointDelta: -204,
            fixedPointDelta: -20.31182861328125,
            ioHidDelta: 4,
            signum: -1,
            multiplier: 8
        )

        XCTAssertEqual(resolution.rawUnits, -4, accuracy: 0.001)
        XCTAssertEqual(resolution.acceleratedUnits, -20.4, accuracy: 0.001)
        XCTAssertEqual(resolution.units, -20.4, accuracy: 0.001)
        XCTAssertEqual(
            normalizedPixels(for: resolution, multiplier: 8),
            -91.8,
            accuracy: 0.001
        )
    }

    func testUnitReaderKeepsSlowRawIOHIDTickDistance() {
        let resolutions = (0 ..< 8).map { _ in
            LogitechHighResolutionWheelUnitReader.units(
                integerDelta: -1,
                pointDelta: -1,
                fixedPointDelta: -0.100006103515625,
                ioHidDelta: 1,
                signum: -1,
                multiplier: 8
            )
        }
        let units = resolutions.map(\.units)
        let pixels = resolutions
            .map { normalizedPixels(for: $0, multiplier: 8) }
            .reduce(0, +)

        XCTAssertEqual(units.reduce(0, +), -8, accuracy: 0.001)
        XCTAssertEqual(pixels, -36, accuracy: 0.001)
    }

    func testUnitReaderPreservesAcceleratedTraceDistance() {
        let fixedPointDeltas = [
            -0.100006103515625,
            -0.23114013671875,
            -1.065032958984375,
            -3.109100341796875,
            -4.987274169921875,
            -6.0433502197265625,
            -6.7981109619140625,
            -7.48211669921875
        ]
        let integerDeltas: [Int64] = [-1, -1, -1, -3, -4, -6, -6, -7]
        let pointDeltas = [-1.0, -3, -11, -32, -50, -61, -68, -75]

        let resolutions = zip(zip(integerDeltas, pointDeltas), fixedPointDeltas).map { fields, fixedPointDelta in
            let (integerDelta, pointDelta) = fields
            return LogitechHighResolutionWheelUnitReader.units(
                integerDelta: integerDelta,
                pointDelta: pointDelta,
                fixedPointDelta: fixedPointDelta,
                ioHidDelta: 1,
                signum: -1,
                multiplier: 8
            )
        }
        let units = resolutions.map(\.units)
        let acceleration = resolutions.map(\.acceleratedUnits)
        let pixels = resolutions
            .map { normalizedPixels(for: $0, multiplier: 8) }
            .reduce(0, +)

        XCTAssertEqual(units.reduce(0, +), -31.7, accuracy: 0.001)
        XCTAssertEqual(acceleration.reduce(0, +), -31.7, accuracy: 0.001)
        XCTAssertEqual(pixels, -142.65, accuracy: 0.001)
    }

    func testLoggedHighResolutionBurstStaysBetweenRawTicksAndUnscaledCGDistance() {
        let fields: [(integer: Int64, fixedPoint: Double, point: Double, ioHid: Double)] = [
            (1, 0.100006103515625, 1.0, -1.0),
            (1, 1.477264404296875, 15.0, -2.0),
            (5, 5.49005126953125, 55.0, -1.0),
            (6, 6.677581787109375, 67.0, -1.0),
            (8, 8.458969116210938, 85.0, -2.0),
            (9, 9.419586181640625, 95.0, -2.0),
            (9, 9.694992065429688, 97.0, -1.0),
            (10, 10.2265625, 103.0, -2.0),
            (11, 11.68096923828125, 117.0, -3.0),
            (12, 12.189132690429688, 122.0, -3.0),
            (12, 12.497634887695312, 125.0, -2.0),
            (12, 12.498245239257812, 125.0, -1.0),
            (13, 13.219070434570312, 133.0, -4.0),
            (13, 13.581680297851562, 136.0, -3.0),
            (14, 14.665756225585938, 147.0, -4.0),
            (15, 15.661636352539062, 157.0, -5.0),
            (16, 16.38055419921875, 164.0, -5.0),
            (18, 18.169158935546875, 182.0, -8.0),
            (19, 19.004440307617188, 191.0, -4.0),
            (19, 19.965545654296875, 200.0, -4.0),
            (19, 19.955291748046875, 200.0, -4.0),
            (20, 20.31182861328125, 204.0, -4.0),
            (19, 19.957611083984375, 200.0, -3.0),
            (19, 19.001113891601562, 191.0, -2.0),
            (17, 17.540130615234375, 176.0, -1.0),
            (15, 15.389617919921875, 154.0, -2.0),
            (14, 14.305068969726562, 144.0, -1.0),
            (12, 12.974929809570312, 130.0, -1.0),
            (11, 11.932373046875, 120.0, -1.0)
        ]

        let normalizedPixels = normalizedPixelSum(for: fields, multiplier: 8)
        let rawIOHIDPixels = rawIOHIDPixelSum(for: fields, multiplier: 8)
        let unscaledCGPixels = unscaledCGPixelSum(for: fields)

        XCTAssertEqual(normalizedPixels, 1732.5, accuracy: 0.001)
        XCTAssertEqual(rawIOHIDPixels, 346.5, accuracy: 0.001)
        XCTAssertEqual(unscaledCGPixels, 13_842.0, accuracy: 0.001)
        XCTAssertGreaterThan(normalizedPixels, rawIOHIDPixels * 4.0)
        XCTAssertLessThan(normalizedPixels, unscaledCGPixels * 0.20)
    }

    func testLoggedSlowAndFastHighResolutionInputsKeepDistinctDistances() {
        let slowFields: [(integer: Int64, fixedPoint: Double, point: Double, ioHid: Double)] = [
            (1, 0.100006103515625, 1.0, -1.0),
            (1, 0.100006103515625, 1.0, -1.0),
            (1, 0.100006103515625, 1.0, -1.0),
            (1, 0.100006103515625, 1.0, -1.0),
            (1, 0.100006103515625, 1.0, -1.0)
        ]
        let fastFields: [(integer: Int64, fixedPoint: Double, point: Double, ioHid: Double)] = [
            (1, 0.100006103515625, 1.0, -1.0),
            (1, 0.100006103515625, 1.0, -1.0),
            (1, 0.7082061767578125, 8.0, -1.0),
            (1, 1.968719482421875, 20.0, -1.0),
            (3, 3.72259521484375, 38.0, -1.0),
            (5, 5.421630859375, 55.0, -1.0),
            (6, 6.1365203857421875, 62.0, -1.0),
            (6, 6.84417724609375, 69.0, -1.0)
        ]

        let slowPixels = normalizedPixelSum(for: slowFields, multiplier: 8)
        let fastPixels = normalizedPixelSum(for: fastFields, multiplier: 8)

        XCTAssertEqual(slowPixels, 22.5, accuracy: 0.001)
        XCTAssertEqual(fastPixels, 123.3, accuracy: 0.001)
        XCTAssertGreaterThan(fastPixels, slowPixels * 5.0)
    }

    private func normalizedPixels(
        for resolution: LogitechHighResolutionWheelUnitReader.UnitResolution,
        multiplier: Int
    ) -> Double {
        resolution.units * 36 / Double(multiplier)
    }

    private func normalizedPixelSum(
        for fields: [(integer: Int64, fixedPoint: Double, point: Double, ioHid: Double)],
        multiplier: Int
    ) -> Double {
        fields
            .map { field in
                let resolution = LogitechHighResolutionWheelUnitReader.units(
                    integerDelta: field.integer,
                    pointDelta: field.point,
                    fixedPointDelta: field.fixedPoint,
                    ioHidDelta: field.ioHid,
                    signum: field.integer.signum(),
                    multiplier: multiplier
                )
                return abs(normalizedPixels(for: resolution, multiplier: multiplier))
            }
            .reduce(0, +)
    }

    private func rawIOHIDPixelSum(
        for fields: [(integer: Int64, fixedPoint: Double, point: Double, ioHid: Double)],
        multiplier: Int
    ) -> Double {
        fields
            .map { abs($0.ioHid) * 36 / Double(multiplier) }
            .reduce(0, +)
    }

    private func unscaledCGPixelSum(
        for fields: [(integer: Int64, fixedPoint: Double, point: Double, ioHid: Double)]
    ) -> Double {
        fields
            .map { max(abs(Double($0.integer)), abs($0.point) / 10, abs($0.fixedPoint)) * 36 }
            .reduce(0, +)
    }

    private func makeVerticalHighResolutionScrollEvent(
        multiplier: Int = 8,
        units: Double = 1
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: Int32(units.sign == .minus ? -1 : 1),
            wheel2: 0,
            wheel3: 0
        ))
        let view = ScrollWheelEventView(event)
        view.deltaYFixedPt = units / Double(multiplier)
        view.deltaYPt = units * 10 / Double(multiplier)
        return event
    }
}
