// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class SmoothedScrollingEngineTests: XCTestCase {
    func testSmoothedScrollingTransitionsIntoMomentumAndEnds() {
        let engine = SmoothedScrollingEngine(
            smoothed: .init(
                vertical: .init(
                    enabled: true,
                    preset: .natural,
                    response: Decimal(string: "0.45"),
                    speed: 1,
                    acceleration: Decimal(string: "1.2"),
                    inertia: Decimal(string: "0.65")
                )
            )
        )

        var emissions: [SmoothedScrollingEngine.Emission] = []

        for step in 0 ..< 6 {
            let timestamp = Double(step) / 120
            engine.feed(deltaX: 0, deltaY: 40, timestamp: timestamp)
            if let emission = engine.advance(to: timestamp + 1.0 / 120) {
                emissions.append(emission)
            }
        }

        for step in 6 ..< 240 {
            let timestamp = Double(step + 1) / 120
            if let emission = engine.advance(to: timestamp) {
                emissions.append(emission)
            }
        }

        XCTAssertEqual(emissions.first?.phase, .touchBegan)
        XCTAssertTrue(emissions.dropFirst().contains { $0.phase == .touchChanged })
        let endedIndex = emissions.firstIndex { $0.phase == .touchEnded }
        let momentumBeginIndex = emissions.firstIndex { $0.phase == .momentumBegan }
        XCTAssertNotNil(endedIndex)
        XCTAssertNotNil(momentumBeginIndex)
        if let endedIndex, let momentumBeginIndex {
            XCTAssertLessThan(endedIndex, momentumBeginIndex)
        }
        XCTAssertTrue(emissions.contains { $0.phase == .momentumBegan })
        XCTAssertTrue(emissions.contains { $0.phase == .momentumChanged })
        XCTAssertEqual(emissions.last?.phase, .momentumEnded)
    }

    func testSmoothedScrollingPreservesPassthroughAxis() {
        let engine = SmoothedScrollingEngine(
            smoothed: .init(
                vertical: .init(
                    enabled: true,
                    preset: .natural,
                    response: Decimal(string: "0.45"),
                    speed: 1,
                    acceleration: Decimal(string: "1.2"),
                    inertia: Decimal(string: "0.65")
                )
            )
        )

        engine.feed(deltaX: 18, deltaY: 24, timestamp: 0)
        let emission = engine.advance(to: 1.0 / 120)

        XCTAssertEqual(emission?.phase, .touchBegan)
        XCTAssertEqual(emission?.deltaX ?? 0, 18, accuracy: 0.001)
        XCTAssertGreaterThan(abs(emission?.deltaY ?? 0), 0)
    }

    func testEaseInStartsSlowerThanEaseOut() {
        let easeInEngine = SmoothedScrollingEngine(smoothed: .init(
            vertical: Scheme.Scrolling.Smoothed.Preset.easeIn.defaultConfiguration
        ))
        let easeOutEngine = SmoothedScrollingEngine(smoothed: .init(
            vertical: Scheme.Scrolling.Smoothed.Preset.easeOut.defaultConfiguration
        ))

        easeInEngine.feed(deltaX: 0, deltaY: 36, timestamp: 0)
        easeOutEngine.feed(deltaX: 0, deltaY: 36, timestamp: 0)

        let easeInEmission = easeInEngine.advance(to: 1.0 / 120)
        let easeOutEmission = easeOutEngine.advance(to: 1.0 / 120)

        XCTAssertNotNil(easeInEmission)
        XCTAssertNotNil(easeOutEmission)
        XCTAssertLessThan(abs(easeInEmission?.deltaY ?? 0), abs(easeOutEmission?.deltaY ?? 0))
    }

    func testMomentumReengagementBlendsAdditionalInputWithoutSharpJump() throws {
        let engine = SmoothedScrollingEngine(smoothed: .init(
            vertical: Scheme.Scrolling.Smoothed.Preset.easeInOut.defaultConfiguration
        ))

        var latestMomentumEmission: SmoothedScrollingEngine.Emission?

        for step in 0 ..< 6 {
            let timestamp = Double(step) / 120
            engine.feed(deltaX: 0, deltaY: 40, timestamp: timestamp)
            _ = engine.advance(to: timestamp + 1.0 / 120)
        }

        for step in 6 ..< 24 {
            let timestamp = Double(step + 1) / 120
            if let emission = engine.advance(to: timestamp), emission.phase == .momentumChanged {
                latestMomentumEmission = emission
            }
        }

        let baseline = try XCTUnwrap(latestMomentumEmission)
        let reengagementTimestamp = 25.0 / 120.0
        engine.feed(deltaX: 0, deltaY: 36, timestamp: reengagementTimestamp)
        let reengagedEmission = try XCTUnwrap(engine.advance(to: reengagementTimestamp + 1.0 / 120.0))

        XCTAssertEqual(reengagedEmission.phase, .touchBegan)
        XCTAssertGreaterThan(abs(reengagedEmission.deltaY), abs(baseline.deltaY))
        XCTAssertLessThan(abs(reengagedEmission.deltaY), abs(baseline.deltaY) * 2.6)
    }

    func testMomentumTailReengagementRecoversTowardFreshPickup() throws {
        let configuration = Scheme.Scrolling.Smoothed.Preset.easeInOut.defaultConfiguration
        let engine = SmoothedScrollingEngine(smoothed: .init(vertical: configuration))
        let freshEngine = SmoothedScrollingEngine(smoothed: .init(vertical: configuration))

        var tailEmission: SmoothedScrollingEngine.Emission?

        for step in 0 ..< 6 {
            let timestamp = Double(step) / 120
            engine.feed(deltaX: 0, deltaY: 40, timestamp: timestamp)
            _ = engine.advance(to: timestamp + 1.0 / 120)
        }

        for step in 6 ..< 240 {
            let timestamp = Double(step + 1) / 120
            if let emission = engine.advance(to: timestamp),
               emission.phase == .momentumChanged,
               abs(emission.deltaY) < 0.25 {
                tailEmission = emission
                break
            }
        }

        let baselineTail = try XCTUnwrap(tailEmission)

        freshEngine.feed(deltaX: 0, deltaY: 36, timestamp: 0)
        let freshPickup = try XCTUnwrap(freshEngine.advance(to: 1.0 / 120))

        let reengagementTimestamp = 2.0
        engine.feed(deltaX: 0, deltaY: 36, timestamp: reengagementTimestamp)
        let reengagedEmission = try XCTUnwrap(engine.advance(to: reengagementTimestamp + 1.0 / 120.0))

        XCTAssertEqual(reengagedEmission.phase, .touchBegan)
        XCTAssertGreaterThan(abs(reengagedEmission.deltaY), abs(baselineTail.deltaY) * 3)
        XCTAssertGreaterThan(abs(reengagedEmission.deltaY), abs(freshPickup.deltaY) * 0.7)
    }

    func testExclusiveAxisSwitchResetsPreviousAxisMomentum() throws {
        let configuration = Scheme.Scrolling.Smoothed.Preset.easeInOut.defaultConfiguration
        let engine = SmoothedScrollingEngine(smoothed: .init(
            vertical: configuration,
            horizontal: configuration
        ))

        for step in 0 ..< 6 {
            let timestamp = Double(step) / 120
            engine.feed(deltaX: 0, deltaY: 40, timestamp: timestamp)
            _ = engine.advance(to: timestamp + 1.0 / 120)
        }

        var verticalMomentumDetected = false
        for step in 6 ..< 60 {
            let timestamp = Double(step + 1) / 120
            if let emission = engine.advance(to: timestamp), emission.phase == .momentumChanged,
               abs(emission.deltaY) > 0.01 {
                verticalMomentumDetected = true
                break
            }
        }
        XCTAssertTrue(verticalMomentumDetected)

        let switchTimestamp = 1.0
        engine.resetOtherAxis(ifExclusiveIncomingAxis: .horizontal)
        engine.feed(deltaX: 36, deltaY: 0, timestamp: switchTimestamp)
        let switchedEmission = try XCTUnwrap(engine.advance(to: switchTimestamp + 1.0 / 120.0))

        XCTAssertEqual(switchedEmission.phase, .touchBegan)
        XCTAssertGreaterThan(abs(switchedEmission.deltaX), 0.01)
        XCTAssertEqual(switchedEmission.deltaY, 0, accuracy: 0.001)
    }
}
