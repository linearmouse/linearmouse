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

    func testButtonMappingRecordingBypassesAutoScrollTrigger() throws {
        var trigger = Scheme.Buttons.Mapping()
        trigger.button = .mouse(2)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.toggle, .hold],
            speed: 1
        )
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

    func testLogitechModifierMismatchAllowsLowerPriorityRecognizer() {
        let identity = LogitechControlIdentity(controlID: 0xC4)
        var trigger = Scheme.Buttons.Mapping()
        trigger.button = .logitechControl(identity)
        trigger.command = true
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.hold],
            speed: 1
        )

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

    func testCancelingLostLogitechHoldStopsAutoScroll() throws {
        let identity = LogitechControlIdentity(controlID: 0xC4)
        var trigger = Scheme.Buttons.Mapping()
        trigger.button = .logitechControl(identity)
        let transformer = AutoScrollTransformer(
            trigger: trigger,
            modes: [.hold],
            speed: 1
        )
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
            modes: [.hold],
            speed: 1
        )
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
            speed: 1,
            longPressTimerScheduler: timer.schedule
        )
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
            speed: 1,
            longPressTimerScheduler: timer.schedule
        )
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
            speed: 1,
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
            speed: 1,
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
            speed: 1,
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
            speed: 1,
            longPressTimerScheduler: timer.schedule
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
            speed: 1,
            longPressTimerScheduler: timer.schedule
        )

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
            speed: 1,
            longPressTimerScheduler: timer.schedule
        )

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
            speed: 1,
            longPressTimerScheduler: timer.schedule
        )

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
            speed: 1,
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
            speed: 1,
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
