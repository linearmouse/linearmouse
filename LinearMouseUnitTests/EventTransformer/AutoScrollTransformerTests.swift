// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
@testable import LinearMouse
import XCTest

final class AutoScrollTransformerTests: XCTestCase {
    private typealias Mapping = Scheme.Buttons.Mapping

    override func tearDown() {
        SettingsState.shared.endButtonMappingRecording()
        super.tearDown()
    }

    func testScrollDistanceFollowsFirefoxCurve() {
        // Within one 12px step of the anchor, nothing scrolls.
        XCTAssertEqual(AutoScrollTransformer.scrollDistance(forOffset: 12, over: 0.02), 0)
        XCTAssertEqual(AutoScrollTransformer.scrollDistance(forOffset: -12, over: 0.02), 0)

        // 48px is 4 steps: 4 * sqrt(4) - 1 = 7px per 20ms.
        XCTAssertEqual(AutoScrollTransformer.scrollDistance(forOffset: 48, over: 0.02), 7, accuracy: 0.0001)
        XCTAssertEqual(AutoScrollTransformer.scrollDistance(forOffset: -48, over: 0.02), -7, accuracy: 0.0001)

        // The distance scales with elapsed time.
        XCTAssertEqual(AutoScrollTransformer.scrollDistance(forOffset: 48, over: 0.01), 3.5, accuracy: 0.0001)

        // Farther offsets accelerate faster than linearly.
        let near = AutoScrollTransformer.scrollDistance(forOffset: 100, over: 1)
        let far = AutoScrollTransformer.scrollDistance(forOffset: 400, over: 1)
        XCTAssertGreaterThan(far, near * 4)
    }

    func testScrollDeltaCarriesFractionsAndStaysWithinFixedPointRange() {
        let slow = AutoScrollTransformer.scrollDelta(for: 2.75)
        XCTAssertEqual(slow.delta, 2)
        XCTAssertEqual(slow.remainder, 0.75, accuracy: 0.0001)

        let reverse = AutoScrollTransformer.scrollDelta(for: -2.75)
        XCTAssertEqual(reverse.delta, -2)
        XCTAssertEqual(reverse.remainder, -0.75, accuracy: 0.0001)

        // A far offset after a stalled tick would overflow the 16.16 fields.
        let distance = AutoScrollTransformer.scrollDistance(forOffset: 5000, over: 0.1)
        XCTAssertGreaterThan(distance, 32_767)
        let clamped = AutoScrollTransformer.scrollDelta(for: -distance)
        XCTAssertEqual(clamped.delta, -AutoScrollTransformer.maxScrollDeltaPerEvent)
        XCTAssertEqual(clamped.remainder, 0)
    }

    func testButtonMappingRecordingBypassesAutoScrollTrigger() throws {
        var trigger = Scheme.Buttons.Mapping()
        trigger.button = .mouse(2)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.toggle, .hold]
        ) { _ in }
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: CGPoint(x: -10_000, y: -10_000),
            mouseButton: .center
        ))
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        SettingsState.shared.beginButtonMappingRecording(sessionID: UUID())

        XCTAssertIdentical(
            transformer.transform(event, in: .init(device: nil)),
            event
        )
        XCTAssertFalse(transformer.isAutoscrollActive)
    }

    func testScrollTargetIsResolvedAtTheTriggerScreenLocation() throws {
        var trigger = Scheme.Buttons.Mapping()
        trigger.button = .mouse(2)
        var resolvedLocations: [CGPoint] = []
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.toggle],
            activationHitProvider: { _ in nil },
            scrollTargetResolver: { location in
                resolvedLocations.append(location)
                return nil
            }
        ) { _ in }
        let location = CGPoint(x: 320, y: 240)
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: location,
            mouseButton: .center
        ))
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)

        XCTAssertNil(transformer.transform(event, in: .init(device: nil)))
        XCTAssertTrue(transformer.isAutoscrollActive)
        // Window hit testing uses global display coordinates, not the unflipped
        // coordinates Auto Scroll measures pointer travel in.
        XCTAssertEqual(resolvedLocations, [location])

        transformer.deactivate()
    }

    func testLogitechModifierMismatchAllowsLowerPriorityRecognizer() {
        let identity = LogitechControlIdentity(controlID: 0xC4)
        var trigger = Scheme.Buttons.Mapping()
        trigger.button = .logitechControl(identity)
        trigger.command = true
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.hold]
        ) { _ in }

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(.init(
                device: nil,
                pid: nil,
                display: nil,
                mouseLocation: .zero,
                controlIdentity: identity,
                isPressed: true,
                modifierFlags: []
            )),
            .notHandled
        )
        XCTAssertFalse(transformer.isAutoscrollActive)
    }

    func testLogitechHoldAnchorsAtTheCursorPosition() throws {
        let identity = LogitechControlIdentity(controlID: 0xC4)
        var trigger = Scheme.Buttons.Mapping()
        trigger.button = .logitechControl(identity)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.hold]
        ) { _ in }
        let press = LogitechEventContext(
            device: nil,
            pid: nil,
            display: nil,
            mouseLocation: CGPoint(x: 500, y: 300),
            controlIdentity: identity,
            isPressed: true,
            modifierFlags: []
        )

        XCTAssertEqual(transformer.handleLogitechControlEvent(press), .handledDeferringSyntheticFallback)

        // A small move stays inside the dead zone around the press location.
        try XCTAssertNotNil(transformer.transform(
            XCTUnwrap(CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: CGPoint(x: 502, y: 302),
                mouseButton: .center
            )),
            in: .init(device: nil)
        ))
        XCTAssertFalse(transformer.isAutoscrollActive)

        try XCTAssertNotNil(transformer.transform(
            XCTUnwrap(CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: CGPoint(x: 500, y: 320),
                mouseButton: .center
            )),
            in: .init(device: nil)
        ))
        XCTAssertTrue(transformer.isAutoscrollActive)

        transformer.deactivate()
    }

    func testCancelingLostLogitechHoldStopsAutoScroll() throws {
        let identity = LogitechControlIdentity(controlID: 0xC4)
        var trigger = Scheme.Buttons.Mapping()
        trigger.button = .logitechControl(identity)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.hold]
        ) { _ in }
        let context = LogitechEventContext(
            device: nil,
            pid: nil,
            display: nil,
            mouseLocation: .zero,
            controlIdentity: identity,
            isPressed: true,
            modifierFlags: []
        )

        XCTAssertEqual(transformer.handleLogitechControlEvent(context), .handledDeferringSyntheticFallback)
        XCTAssertFalse(transformer.isAutoscrollActive)

        try XCTAssertNotNil(transformer.transform(
            XCTUnwrap(CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: CGPoint(x: 11, y: 0),
                mouseButton: .center
            )),
            in: .init(device: nil)
        ))
        XCTAssertTrue(transformer.isAutoscrollActive)

        XCTAssertTrue(transformer.cancelLogitechControlInteraction(context))
        XCTAssertFalse(transformer.isAutoscrollActive)
    }

    func testReleasingLogitechHoldWithinDeadZoneDoesNotActivateAutoScroll() {
        let identity = LogitechControlIdentity(controlID: 0xC4)
        var trigger = Scheme.Buttons.Mapping()
        trigger.button = .logitechControl(identity)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.hold]
        ) { _ in }
        let press = LogitechEventContext(
            device: nil,
            pid: nil,
            display: nil,
            mouseLocation: .zero,
            controlIdentity: identity,
            isPressed: true,
            modifierFlags: []
        )
        let release = LogitechEventContext(
            device: nil,
            pid: nil,
            display: nil,
            mouseLocation: .zero,
            controlIdentity: identity,
            isPressed: false,
            modifierFlags: []
        )

        XCTAssertEqual(transformer.handleLogitechControlEvent(press), .handledDeferringSyntheticFallback)
        XCTAssertFalse(transformer.isAutoscrollActive)
        XCTAssertEqual(transformer.handleLogitechControlEvent(release), .notHandled)
        XCTAssertFalse(transformer.isAutoscrollActive)
    }

    func testLongPressLogitechToggleRestoresShortClickFallback() {
        let timer = LongPressTimerHarness()
        let identity = LogitechControlIdentity(controlID: 0xC4)
        var trigger = Mapping()
        trigger.button = .logitechControl(identity)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.toggle],
            toggleActivation: .longPress,
            longPressTimerScheduler: timer.schedule
        ) { _ in }
        let press = logitechContext(identity: identity, pressed: true)
        let release = logitechContext(identity: identity, pressed: false)

        XCTAssertEqual(transformer.handleLogitechControlEvent(press), .handledDeferringSyntheticFallback)
        XCTAssertFalse(transformer.isAutoscrollActive)
        XCTAssertEqual(transformer.handleLogitechControlEvent(release), .notHandled)
        XCTAssertEqual(timer.cancellationCount, 1)
        XCTAssertFalse(transformer.isAutoscrollActive)
    }

    func testLongPressLogitechToggleSuppressesFallbackAfterThreshold() {
        let timer = LongPressTimerHarness()
        let identity = LogitechControlIdentity(controlID: 0xC4)
        var trigger = Mapping()
        trigger.button = .logitechControl(identity)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.toggle],
            toggleActivation: .longPress,
            longPressTimerScheduler: timer.schedule
        ) { _ in }
        let press = logitechContext(identity: identity, pressed: true)
        let release = logitechContext(identity: identity, pressed: false)

        XCTAssertEqual(transformer.handleLogitechControlEvent(press), .handledDeferringSyntheticFallback)
        timer.fire()
        XCTAssertTrue(transformer.isAutoscrollActive)
        XCTAssertEqual(transformer.handleLogitechControlEvent(release), .handled)
        XCTAssertTrue(transformer.isAutoscrollActive)
        transformer.deactivate()
    }

    func testHoldOnlyClickReplaysNativeClickWithoutAccessibilityHitTest() throws {
        var replayedEvents = [CGEventType]()
        var trigger = Mapping()
        trigger.button = .mouse(2)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.hold],
            activationHitProvider: { _ in
                XCTFail("Hold-only activation should not depend on accessibility hit testing")
                return .nonPressable(diagnostic: nil, path: [])
            }
        ) { replayedEvents.append($0.type) }

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDown, location: CGPoint(x: 100, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertFalse(transformer.isAutoscrollActive)

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseUp, location: CGPoint(x: 100, y: 100)),
            in: .init(device: nil)
        ))

        XCTAssertEqual(replayedEvents, [.otherMouseDown, .otherMouseUp])
        XCTAssertFalse(transformer.isAutoscrollActive)
    }

    func testHoldOnlyDragActivatesAfterDeadZone() throws {
        var replayedEvents = [CGEventType]()
        var trigger = Mapping()
        trigger.button = .mouse(2)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.hold],
            activationHitProvider: { _ in
                XCTFail("Hold-only activation should not depend on accessibility hit testing")
                return nil
            }
        ) { replayedEvents.append($0.type) }

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDown, location: CGPoint(x: 100, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDragged, location: CGPoint(x: 105, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertFalse(transformer.isAutoscrollActive)

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDragged, location: CGPoint(x: 111, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertTrue(transformer.isAutoscrollActive)

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseUp, location: CGPoint(x: 111, y: 100)),
            in: .init(device: nil)
        ))

        XCTAssertEqual(replayedEvents, [])
        XCTAssertFalse(transformer.isAutoscrollActive)
    }

    func testLongPressToggleReplaysShortClick() throws {
        let timer = LongPressTimerHarness()
        var replayedEvents = [CGEventType]()
        var trigger = Mapping()
        trigger.button = .mouse(2)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.toggle],
            toggleActivation: .longPress,
            longPressTimerScheduler: timer.schedule,
            activationHitProvider: { _ in
                XCTFail("Long-press toggle should not depend on accessibility hit testing")
                return nil
            }
        ) { replayedEvents.append($0.type) }

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDown, location: CGPoint(x: 100, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertEqual(timer.interval, ButtonMappingPolicy.default.longPressDuration)
        XCTAssertFalse(transformer.isAutoscrollActive)

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseUp, location: CGPoint(x: 100, y: 100)),
            in: .init(device: nil)
        ))

        XCTAssertEqual(replayedEvents, [.otherMouseDown, .otherMouseUp])
        XCTAssertEqual(timer.cancellationCount, 1)
        XCTAssertFalse(transformer.isAutoscrollActive)
    }

    func testLongPressToggleActivatesAtButtonMappingThreshold() throws {
        let timer = LongPressTimerHarness()
        var replayedEvents = [CGEventType]()
        var trigger = Mapping()
        trigger.button = .mouse(2)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.toggle],
            toggleActivation: .longPress,
            longPressTimerScheduler: timer.schedule,
            activationHitProvider: nil
        ) { replayedEvents.append($0.type) }

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDown, location: CGPoint(x: 100, y: 100)),
            in: .init(device: nil)
        ))
        timer.fire()
        XCTAssertTrue(transformer.isAutoscrollActive)

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseUp, location: CGPoint(x: 100, y: 100)),
            in: .init(device: nil)
        ))

        XCTAssertEqual(replayedEvents, [])
        XCTAssertTrue(transformer.isAutoscrollActive)
        transformer.deactivate()
    }

    func testLongPressToggleSettingDoesNotDelayHoldOnlyMode() throws {
        let timer = LongPressTimerHarness()
        var trigger = Mapping()
        trigger.button = .mouse(2)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.hold],
            toggleActivation: .longPress,
            longPressTimerScheduler: timer.schedule
        ) { _ in }

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDown, location: CGPoint(x: 100, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertNil(timer.interval)

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDragged, location: CGPoint(x: 111, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertTrue(transformer.isAutoscrollActive)

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseUp, location: CGPoint(x: 111, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertFalse(transformer.isAutoscrollActive)
    }

    func testCombinedLongPressModeStillActivatesHoldAfterDeadZone() throws {
        let timer = LongPressTimerHarness()
        var trigger = Mapping()
        trigger.button = .mouse(2)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.toggle, .hold],
            toggleActivation: .longPress,
            longPressTimerScheduler: timer.schedule
        ) { _ in }

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDown, location: CGPoint(x: 100, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertNotNil(timer.interval)

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDragged, location: CGPoint(x: 111, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertEqual(timer.cancellationCount, 1)
        XCTAssertTrue(transformer.isAutoscrollActive)

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseUp, location: CGPoint(x: 111, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertFalse(transformer.isAutoscrollActive)
    }

    func testCombinedLongPressModeTogglesAfterThresholdWithoutDrag() throws {
        let timer = LongPressTimerHarness()
        var trigger = Mapping()
        trigger.button = .mouse(2)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.toggle, .hold],
            toggleActivation: .longPress,
            longPressTimerScheduler: timer.schedule
        ) { _ in }

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDown, location: CGPoint(x: 100, y: 100)),
            in: .init(device: nil)
        ))
        timer.fire()
        XCTAssertTrue(transformer.isAutoscrollActive)

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseUp, location: CGPoint(x: 100, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertTrue(transformer.isAutoscrollActive)
        transformer.deactivate()
    }

    func testDraggingPressableElementBeyondDeadZoneActivatesAutoScroll() throws {
        var replayedEvents = [CGEventType]()
        let transformer = pressableElementTransformer { replayedEvents.append($0.type) }

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDown, location: CGPoint(x: 100, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertFalse(transformer.isAutoscrollActive)

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDragged, location: CGPoint(x: 120, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertTrue(transformer.isAutoscrollActive)

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseUp, location: CGPoint(x: 120, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertFalse(transformer.isAutoscrollActive)
        XCTAssertEqual(replayedEvents, [])
    }

    func testClickingPressableElementReplaysBalancedNativeClick() throws {
        var replayedEvents = [CGEventType]()
        let transformer = pressableElementTransformer { replayedEvents.append($0.type) }
        let down = try mouseEvent(type: .otherMouseDown, location: CGPoint(x: 100, y: 100))
        let up = try mouseEvent(type: .otherMouseUp, location: CGPoint(x: 100, y: 100))

        XCTAssertNil(transformer.transform(down, in: .init(device: nil)))
        XCTAssertNil(transformer.transform(up, in: .init(device: nil)))

        XCTAssertEqual(replayedEvents, [.otherMouseDown, .otherMouseUp])
        XCTAssertFalse(transformer.isAutoscrollActive)
    }

    func testReplayedClickUsesEachEventsDownstreamContinuation() throws {
        let transformer = pressableElementTransformer { _ in
            XCTFail("Expected the contextual event sinks to be used")
        }
        var deliveries = [(String, CGEventType)]()
        let down = try mouseEvent(type: .otherMouseDown, location: CGPoint(x: 100, y: 100))
        let up = try mouseEvent(type: .otherMouseUp, location: CGPoint(x: 100, y: 100))

        XCTAssertNil(transformer.transform(
            down,
            in: .init(device: nil) { deliveries.append(("down", $0.type)) }
        ))
        XCTAssertNil(transformer.transform(
            up,
            in: .init(device: nil) { deliveries.append(("up", $0.type)) }
        ))

        XCTAssertEqual(deliveries.map(\.0), ["down", "up"])
        XCTAssertEqual(deliveries.map(\.1), [.otherMouseDown, .otherMouseUp])
    }

    func testOtherButtonPressIsReplayedAfterPendingTriggerDown() throws {
        var replayedEvents = [CGEventType]()
        let transformer = pressableElementTransformer { replayedEvents.append($0.type) }
        let otherDown = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: CGPoint(x: 100, y: 100),
            mouseButton: .left
        ))

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDown, location: CGPoint(x: 100, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertNil(transformer.transform(otherDown, in: .init(device: nil)))

        XCTAssertEqual(replayedEvents, [.otherMouseDown, .leftMouseDown])
        XCTAssertFalse(transformer.isAutoscrollActive)
    }

    func testSubDeadZoneDragOnPressableElementReplaysNativeStream() throws {
        var replayedEvents = [CGEventType]()
        let transformer = pressableElementTransformer { replayedEvents.append($0.type) }
        let up = try mouseEvent(type: .otherMouseUp, location: CGPoint(x: 105, y: 100))

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDown, location: CGPoint(x: 100, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDragged, location: CGPoint(x: 105, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertNil(transformer.transform(up, in: .init(device: nil)))

        XCTAssertEqual(replayedEvents, [.otherMouseDown, .otherMouseDragged, .otherMouseUp])
        XCTAssertFalse(transformer.isAutoscrollActive)
    }

    func testToggleOnlyModeActivatesAfterDraggingPressableElement() throws {
        var trigger = Mapping()
        trigger.button = .mouse(2)
        var replayedEvents = [CGEventType]()
        let activationHitProvider: AutoScrollTransformer.ActivationHitProvider = { _ in
            .pressable(path: ["AXLink"])
        }
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.toggle],
            activationHitProvider: activationHitProvider
        ) { replayedEvents.append($0.type) }

        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDown, location: CGPoint(x: 100, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseDragged, location: CGPoint(x: 120, y: 100)),
            in: .init(device: nil)
        ))
        XCTAssertTrue(transformer.isAutoscrollActive)
        XCTAssertNil(try transformer.transform(
            mouseEvent(type: .otherMouseUp, location: CGPoint(x: 120, y: 100)),
            in: .init(device: nil)
        ))

        XCTAssertTrue(transformer.isAutoscrollActive)
        XCTAssertEqual(replayedEvents, [])
        transformer.deactivate()
    }

    private func pressableElementTransformer(
        eventSink: @escaping (CGEvent) -> Void
    ) -> AutoScrollTransformer {
        var trigger = Mapping()
        trigger.button = .mouse(2)
        return AutoScrollTransformer(
            trigger: trigger,
            modes: [.toggle, .hold],
            activationHitProvider: { _ in .pressable(path: ["AXLink"]) },
            eventSink: eventSink
        )
    }

    private func mouseEvent(type: CGEventType, location: CGPoint) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: .center
        ))
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        return event
    }

    private func logitechContext(
        identity: LogitechControlIdentity,
        pressed: Bool
    ) -> LogitechEventContext {
        .init(
            device: nil,
            pid: nil,
            display: nil,
            mouseLocation: .zero,
            controlIdentity: identity,
            isPressed: pressed,
            modifierFlags: []
        )
    }

    private final class LongPressTimerHarness {
        private(set) var interval: TimeInterval?
        private(set) var cancellationCount = 0
        private var handler: (() -> Void)?

        func schedule(_ interval: TimeInterval, _ handler: @escaping () -> Void) -> (() -> Void)? {
            self.interval = interval
            self.handler = handler
            return { [weak self] in
                self?.cancellationCount += 1
                self?.handler = nil
            }
        }

        func fire() {
            let handler = handler
            self.handler = nil
            handler?()
        }
    }
}
