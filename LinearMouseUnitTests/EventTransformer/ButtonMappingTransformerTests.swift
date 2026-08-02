// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import KeyKit
@testable import LinearMouse
import XCTest

private final class ButtonMappingTestTimerScheduler {
    private final class ScheduledTimer {
        var deadline: UInt64
        var handler: () -> Void
        var active = true

        init(deadline: UInt64, handler: @escaping () -> Void) {
            self.deadline = deadline
            self.handler = handler
        }
    }

    private var timers = [ScheduledTimer]()
    private(set) var now: UInt64 = 0

    func schedule(
        interval: TimeInterval,
        handler: @escaping () -> Void
    ) -> ButtonMappingTransformer.TimerToken {
        let timer = ScheduledTimer(
            deadline: now + UInt64(interval * 1_000_000_000),
            handler: handler
        )
        timers.append(timer)
        return .init {
            timer.active = false
        }
    }

    func advance(to timestamp: UInt64) {
        while let timer = timers
            .filter(\.active)
            .filter({ $0.deadline <= timestamp })
            .min(by: { $0.deadline < $1.deadline }) {
            now = timer.deadline
            timer.active = false
            timer.handler()
        }
        now = timestamp
    }
}

private final class ButtonMappingTestKeySimulator: KeySimulating {
    enum Event: Equatable {
        case down([Key])
        case up([Key])
        case press([Key])
        case reset
    }

    private(set) var events = [Event]()

    func down(keys: [Key], tap _: CGEventTapLocation?) throws {
        events.append(.down(keys))
    }

    func up(keys: [Key], tap _: CGEventTapLocation?) throws {
        events.append(.up(keys))
    }

    func press(keys: [Key], tap _: CGEventTapLocation?) throws {
        events.append(.press(keys))
    }

    func press(keys: [Key], modifierFlags _: CGEventFlags, tap _: CGEventTapLocation?) throws {
        events.append(.press(keys))
    }

    func press(
        keys: [Key],
        modifierFlags _: CGEventFlags,
        restoringModifierFlags _: CGEventFlags,
        tap _: CGEventTapLocation?
    ) throws {
        events.append(.press(keys))
    }

    func reset() {
        events.append(.reset)
    }

    func modifiedCGEventFlags(of _: CGEvent) -> CGEventFlags? {
        nil
    }
}

final class ButtonMappingTransformerTests: XCTestCase {
    private typealias Mapping = Scheme.Buttons.Mapping

    override func setUp() {
        super.setUp()
        SettingsState.shared.endButtonMappingRecording()
    }

    override func tearDown() {
        SettingsState.shared.endButtonMappingRecording()
        super.tearDown()
    }

    func testShortPressConsumesOriginalButtonEvents() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var replayed = [CGEventType]()
        let transformer = makeTransformer(
            mappings: [buttonMapping(short: .arg0(.none))],
            scheduler: scheduler
        ) { replayed.append($0.type) }

        XCTAssertNil(try transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))
        scheduler.advance(to: ms(100))
        XCTAssertNil(try transformer.transform(buttonEvent(pressed: false), in: .init(device: nil)))
        XCTAssertEqual(replayed, [])
    }

    func testGestureButtonWinsOverShortPressMappingAfterDrag() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let gestureTransformer = makeGestureTransformer(button: .mouse(4))
        let transformer = makeTransformer(
            mappings: [buttonMapping(short: .arg1(.keyPress([.a])))],
            scheduler: scheduler,
            keySimulator: keySimulator,
            gestureTransformer: gestureTransformer
        )

        XCTAssertNil(try transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))
        XCTAssertNil(try transformer.transform(
            draggedEvent(button: 4, deltaX: 10),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(buttonEvent(pressed: false), in: .init(device: nil)))

        XCTAssertEqual(keySimulator.events, [])
    }

    func testShortPressMappingRemainsGestureButtonClickFallback() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let transformer = makeTransformer(
            mappings: [buttonMapping(short: .arg1(.keyPress([.a])))],
            scheduler: scheduler,
            keySimulator: keySimulator,
            gestureTransformer: makeGestureTransformer(button: .mouse(4))
        )

        XCTAssertNil(try transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))
        XCTAssertNil(try transformer.transform(buttonEvent(pressed: false), in: .init(device: nil)))

        let actionPerformed = expectation(description: "short press action performed")
        DispatchQueue.main.async {
            XCTAssertEqual(keySimulator.events, [.press([.a]), .reset])
            actionPerformed.fulfill()
        }
        wait(for: [actionPerformed], timeout: 1)
    }

    func testUndefinedShortPressReplaysBalancedClick() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var replayed = [CGEventType]()
        let transformer = makeTransformer(
            mappings: [buttonMapping(long: .arg0(.none))],
            scheduler: scheduler
        ) { replayed.append($0.type) }

        XCTAssertNil(try transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))
        scheduler.advance(to: ms(100))
        XCTAssertNil(try transformer.transform(buttonEvent(pressed: false), in: .init(device: nil)))

        XCTAssertEqual(replayed, [.otherMouseDown, .otherMouseUp])
    }

    func testFailedChordReplaysPrefixAtChordDeadline() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var replayed = [CGEventType]()
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4)), simultaneous: [.mouse(5)]),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler
        ) { replayed.append($0.type) }

        XCTAssertNil(try transformer.transform(buttonEvent(button: 4, pressed: true), in: .init(device: nil)))
        scheduler.advance(to: ms(80))
        XCTAssertEqual(replayed, [.otherMouseDown])
        XCTAssertNil(try transformer.transform(buttonEvent(button: 4, pressed: false), in: .init(device: nil)))
        XCTAssertEqual(replayed, [.otherMouseDown, .otherMouseUp])
    }

    func testFailedPrimarySecondaryChordForwardsBalancedIndividualClicks() throws {
        for button in [0, 1] {
            let scheduler = ButtonMappingTestTimerScheduler()
            var delivered = [CGEventType]()
            let mapping = Mapping(
                trigger: .init(input: .button(.mouse(0)), simultaneous: [.mouse(1)]),
                outcomes: .init(shortPress: .arg0(.none))
            )
            let transformer = makeTransformer(
                mappings: [mapping],
                scheduler: scheduler
            ) { delivered.append($0.type) }

            if let event = try transformer.transform(
                buttonEvent(button: button, pressed: true),
                in: .init(device: nil)
            ) {
                delivered.append(event.type)
            }
            scheduler.advance(to: ms(80))
            XCTAssertNil(try transformer.transform(
                buttonEvent(button: button, pressed: false),
                in: .init(device: nil)
            ))

            let mouseButton = CGMouseButton(rawValue: UInt32(button)) ?? .left
            XCTAssertEqual(delivered, [
                mouseButton.fixedCGEventType(of: .otherMouseDown),
                mouseButton.fixedCGEventType(of: .otherMouseUp)
            ])
        }
    }

    func testQuickPrimarySecondaryChordFallbackReplaysBalancedIndividualClicks() throws {
        for button in [0, 1] {
            let scheduler = ButtonMappingTestTimerScheduler()
            var delivered = [CGEventType]()
            let mapping = Mapping(
                trigger: .init(input: .button(.mouse(0)), simultaneous: [.mouse(1)]),
                outcomes: .init(shortPress: .arg0(.none))
            )
            let transformer = makeTransformer(
                mappings: [mapping],
                scheduler: scheduler
            ) { delivered.append($0.type) }

            XCTAssertNil(try transformer.transform(
                buttonEvent(button: button, pressed: true),
                in: .init(device: nil)
            ))
            scheduler.advance(to: ms(40))
            XCTAssertNil(try transformer.transform(
                buttonEvent(button: button, pressed: false),
                in: .init(device: nil)
            ))

            let mouseButton = CGMouseButton(rawValue: UInt32(button)) ?? .left
            XCTAssertEqual(delivered, [
                mouseButton.fixedCGEventType(of: .otherMouseDown),
                mouseButton.fixedCGEventType(of: .otherMouseUp)
            ])
        }
    }

    func testFailedPrimarySecondaryChordForwardsDragAndReleaseThroughDeferredSink() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var fallbackEvents = [CGEventType]()
        var deferredEvents = [CGEventType]()
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(0)), simultaneous: [.mouse(1)]),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler
        ) { fallbackEvents.append($0.type) }
        let context = EventTransformerContext(device: nil) {
            deferredEvents.append($0.type)
        }

        XCTAssertNil(try transformer.transform(buttonEvent(button: 0, pressed: true), in: context))
        scheduler.advance(to: ms(80))
        XCTAssertEqual(deferredEvents, [.leftMouseDown])

        XCTAssertNil(try transformer.transform(draggedEvent(button: 0, deltaX: 3), in: context))
        XCTAssertNil(try transformer.transform(buttonEvent(button: 0, pressed: false), in: context))

        XCTAssertEqual(deferredEvents, [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        XCTAssertEqual(fallbackEvents, [])
    }

    func testCompletedChordDoesNotReplayEitherButton() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        var replayed = [CGEventType]()
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4)), simultaneous: [.mouse(5)]),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler
        ) { replayed.append($0.type) }

        XCTAssertNil(try transformer.transform(buttonEvent(button: 4, pressed: true), in: .init(device: nil)))
        scheduler.advance(to: ms(30))
        XCTAssertNil(try transformer.transform(buttonEvent(button: 5, pressed: true), in: .init(device: nil)))
        scheduler.advance(to: ms(50))
        XCTAssertNil(try transformer.transform(buttonEvent(button: 5, pressed: false), in: .init(device: nil)))
        XCTAssertNil(try transformer.transform(buttonEvent(button: 4, pressed: false), in: .init(device: nil)))
        XCTAssertEqual(replayed, [])
    }

    func testWheelMappingConsumesPhysicalEventButIgnoresSyntheticAndMomentum() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let mapping = Mapping(trigger: .init(input: .wheel(.up)), action: .arg0(.none))
        let transformer = makeTransformer(mappings: [mapping], scheduler: scheduler)

        XCTAssertNil(try transformer.transform(scrollEvent(vertical: 1), in: .init(device: nil)))

        let synthetic = try scrollEvent(vertical: 1)
        synthetic.isLinearMouseSyntheticEvent = true
        XCTAssertNotNil(transformer.transform(synthetic, in: .init(device: nil)))

        let momentum = try scrollEvent(vertical: 1)
        ScrollWheelEventView(momentum).momentumPhase = .begin
        XCTAssertNotNil(transformer.transform(momentum, in: .init(device: nil)))
    }

    func testHorizontalWheelUsesDominantAxis() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let mapping = Mapping(trigger: .init(input: .wheel(.left)), action: .arg0(.none))
        let transformer = makeTransformer(mappings: [mapping], scheduler: scheduler)

        XCTAssertNil(try transformer.transform(
            scrollEvent(horizontal: 3, vertical: 1),
            in: .init(device: nil)
        ))
        XCTAssertNotNil(try transformer.transform(
            scrollEvent(horizontal: -3, vertical: 1),
            in: .init(device: nil)
        ))
    }

    func testSwappedPrimaryButtonMatchesItsRecordedLogicalButton() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(1))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler,
            swapsPrimaryAndSecondaryButtons: true
        )

        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 0, pressed: true),
            in: .init(device: nil)
        ))
        XCTAssertNil(try transformer.transform(
            buttonEvent(button: 0, pressed: false),
            in: .init(device: nil)
        ))
    }

    func testLogitechQuickReleaseAllowsDeferredFallback() {
        let scheduler = ButtonMappingTestTimerScheduler()
        let identity = LogitechControlIdentity(controlID: 0xC4)
        let mapping = Mapping(
            trigger: .init(input: .button(.logitechControl(identity))),
            outcomes: .init(longPress: .arg0(.none))
        )
        let transformer = makeTransformer(mappings: [mapping], scheduler: scheduler)

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(identity, pressed: true)),
            .handledDeferringSyntheticFallback
        )
        scheduler.advance(to: ms(100))
        XCTAssertEqual(transformer.handleLogitechControlEvent(logitech(identity, pressed: false)), .notHandled)
    }

    func testLogitechLongPressSuppressesDeferredFallback() {
        let scheduler = ButtonMappingTestTimerScheduler()
        let identity = LogitechControlIdentity(controlID: 0xC4)
        let mapping = Mapping(
            trigger: .init(input: .button(.logitechControl(identity))),
            outcomes: .init(longPress: .arg0(.none))
        )
        let transformer = makeTransformer(mappings: [mapping], scheduler: scheduler)

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(identity, pressed: true)),
            .handledDeferringSyntheticFallback
        )
        scheduler.advance(to: ms(500))
        XCTAssertEqual(transformer.handleLogitechControlEvent(logitech(identity, pressed: false)), .handled)
    }

    func testLogitechGestureWinsOverShortPressMapping() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let identity = LogitechControlIdentity(controlID: 0xC4)
        let mapping = Mapping(
            trigger: .init(input: .button(.logitechControl(identity))),
            outcomes: .init(shortPress: .arg1(.keyPress([.a])))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler,
            keySimulator: keySimulator,
            gestureTransformer: makeGestureTransformer(button: .logitechControl(identity))
        )

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(identity, pressed: true)),
            .handledDeferringSyntheticFallback
        )
        XCTAssertNil(try transformer.transform(mouseMovedEvent(deltaX: 10), in: .init(device: nil)))
        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(identity, pressed: false)),
            .handled
        )
        XCTAssertEqual(keySimulator.events, [])
    }

    func testGenericLogitechControlMatchesDeviceSpecificEventIdentity() {
        let scheduler = ButtonMappingTestTimerScheduler()
        let configured = LogitechControlIdentity(controlID: 0xC4)
        let eventIdentity = LogitechControlIdentity(controlID: 0xC4, productID: 0x405E, serialNumber: "ABC")
        let mapping = Mapping(
            trigger: .init(input: .button(.logitechControl(configured))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let transformer = makeTransformer(mappings: [mapping], scheduler: scheduler)

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(eventIdentity, pressed: true)),
            .handledDeferringSyntheticFallback
        )
        XCTAssertEqual(transformer.handleLogitechControlEvent(logitech(eventIdentity, pressed: false)), .handled)
    }

    func testLogitechIdentityFallbackIsRespected() {
        let scheduler = ButtonMappingTestTimerScheduler()
        let configured = LogitechControlIdentity(controlID: 0xC4, productID: 0x405E, serialNumber: "ABC")
        let eventIdentity = LogitechControlIdentity(controlID: 0xC4, productID: 0x405E)
        let mapping = Mapping(
            trigger: .init(input: .button(.logitechControl(configured))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let transformer = makeTransformer(mappings: [mapping], scheduler: scheduler)

        XCTAssertEqual(transformer.handleLogitechControlEvent(
            logitech(eventIdentity, pressed: true, allowsIdentityFallback: true)
        ), .handledDeferringSyntheticFallback)
        XCTAssertEqual(transformer.handleLogitechControlEvent(
            logitech(eventIdentity, pressed: false, allowsIdentityFallback: true)
        ), .handled)
    }

    func testDeviceSpecificLogitechMappingWinsOverGenericMapping() {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let generic = LogitechControlIdentity(controlID: 0xC4)
        let specific = LogitechControlIdentity(controlID: 0xC4, productID: 0x405E, serialNumber: "ABC")
        let transformer = makeTransformer(
            mappings: [
                Mapping(
                    trigger: .init(input: .button(.logitechControl(generic))),
                    outcomes: .init(press: .init(action: .arg1(.keyPress([.a])), behavior: .hold))
                ),
                Mapping(
                    trigger: .init(input: .button(.logitechControl(specific))),
                    outcomes: .init(press: .init(action: .arg1(.keyPress([.b])), behavior: .hold))
                )
            ],
            scheduler: scheduler,
            keySimulator: keySimulator
        )

        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(specific, pressed: true)),
            .handledDeferringSyntheticFallback
        )
        XCTAssertEqual(keySimulator.events, [.down([.b])])
        XCTAssertEqual(
            transformer.handleLogitechControlEvent(logitech(specific, pressed: false)),
            .handled
        )
        XCTAssertEqual(keySimulator.events, [.down([.b]), .up([.b]), .reset])
    }

    func testHoldPressUsesKeyDownAndKeyUpLifecycle() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(press: .init(action: .arg1(.keyPress([.a])), behavior: .hold))
        )
        let transformer = makeTransformer(
            mappings: [mapping],
            scheduler: scheduler,
            keySimulator: keySimulator
        )

        XCTAssertNil(try transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))
        XCTAssertNil(try transformer.transform(buttonEvent(pressed: false), in: .init(device: nil)))

        XCTAssertEqual(keySimulator.events, [.down([.a]), .up([.a]), .reset])
    }

    func testOverlappingHoldPressesReleaseIndependently() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let mappings = [
            Mapping(
                trigger: .init(input: .button(.mouse(4))),
                outcomes: .init(press: .init(action: .arg1(.keyPress([.command])), behavior: .hold))
            ),
            Mapping(
                trigger: .init(input: .button(.mouse(5))),
                outcomes: .init(press: .init(action: .arg1(.keyPress([.shift])), behavior: .hold))
            )
        ]
        let transformer = makeTransformer(
            mappings: mappings,
            scheduler: scheduler,
            keySimulator: keySimulator
        )

        _ = try transformer.transform(buttonEvent(button: 4, pressed: true), in: .init(device: nil))
        _ = try transformer.transform(buttonEvent(button: 5, pressed: true), in: .init(device: nil))
        _ = try transformer.transform(buttonEvent(button: 5, pressed: false), in: .init(device: nil))
        _ = try transformer.transform(buttonEvent(button: 4, pressed: false), in: .init(device: nil))

        XCTAssertEqual(keySimulator.events, [
            .down([.command]),
            .down([.shift]),
            .up([.shift]),
            .up([.command]),
            .reset
        ])
    }

    func testOverlappingHoldsReferenceCountSharedKeys() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let keySimulator = ButtonMappingTestKeySimulator()
        let holdA = Mapping.PressAction(action: .arg1(.keyPress([.a])), behavior: .hold)
        let transformer = makeTransformer(
            mappings: [
                Mapping(
                    trigger: .init(input: .button(.mouse(4))),
                    outcomes: .init(press: holdA)
                ),
                Mapping(
                    trigger: .init(input: .button(.mouse(5))),
                    outcomes: .init(press: holdA)
                )
            ],
            scheduler: scheduler,
            keySimulator: keySimulator
        )

        _ = try transformer.transform(buttonEvent(button: 4, pressed: true), in: .init(device: nil))
        _ = try transformer.transform(buttonEvent(button: 5, pressed: true), in: .init(device: nil))
        XCTAssertEqual(keySimulator.events, [.down([.a])])

        _ = try transformer.transform(buttonEvent(button: 4, pressed: false), in: .init(device: nil))
        XCTAssertEqual(keySimulator.events, [.down([.a])])

        _ = try transformer.transform(buttonEvent(button: 5, pressed: false), in: .init(device: nil))
        XCTAssertEqual(keySimulator.events, [.down([.a]), .up([.a]), .reset])
    }

    func testRemapPressRewritesDownDragAndUpStream() throws {
        let scheduler = ButtonMappingTestTimerScheduler()
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(press: .init(action: .arg0(.mouseButtonLeft), behavior: .remap))
        )
        let transformer = makeTransformer(mappings: [mapping], scheduler: scheduler)

        let down = try XCTUnwrap(transformer.transform(buttonEvent(pressed: true), in: .init(device: nil)))
        let dragged = try XCTUnwrap(transformer.transform(
            draggedEvent(button: 4, deltaX: 3),
            in: .init(device: nil)
        ))
        let up = try XCTUnwrap(transformer.transform(buttonEvent(pressed: false), in: .init(device: nil)))

        XCTAssertEqual(down.type, .leftMouseDown)
        XCTAssertEqual(dragged.type, .leftMouseDragged)
        XCTAssertEqual(up.type, .leftMouseUp)
        XCTAssertEqual(MouseEventView(down).mouseButton, .left)
        XCTAssertEqual(MouseEventView(dragged).mouseButton, .left)
        XCTAssertEqual(MouseEventView(up).mouseButton, .left)
    }

    private func makeTransformer(
        mappings: [Mapping],
        scheduler: ButtonMappingTestTimerScheduler,
        swapsPrimaryAndSecondaryButtons: Bool = false,
        keySimulator: KeySimulating? = nil,
        gestureTransformer: GestureButtonTransformer? = nil,
        eventSink: @escaping (CGEvent) -> Void = { _ in }
    ) -> ButtonMappingTransformer {
        .init(
            mappings: mappings,
            swapsPrimaryAndSecondaryButtons: swapsPrimaryAndSecondaryButtons,
            scheduleTimer: scheduler.schedule,
            monotonicClock: { scheduler.now },
            keySimulator: keySimulator,
            gestureTransformer: gestureTransformer,
            eventSink: eventSink
        )
    }

    private func makeGestureTransformer(button: Mapping.Button) -> GestureButtonTransformer {
        GestureButtonTransformer(
            trigger: .init(button: button),
            threshold: 10,
            deadZone: 40,
            cooldownMs: 500,
            actions: .init(right: .some(.none))
        )
    }

    private func buttonMapping(
        short: Mapping.Action? = nil,
        long: Mapping.Action? = nil
    ) -> Mapping {
        .init(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(shortPress: short, longPress: long)
        )
    }

    private func buttonEvent(button: Int = 4, pressed: Bool) throws -> CGEvent {
        let mouseButton = CGMouseButton(rawValue: UInt32(button)) ?? .center
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: mouseButton.fixedCGEventType(of: pressed ? .otherMouseDown : .otherMouseUp),
            mouseCursorPosition: .zero,
            mouseButton: mouseButton
        ))
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        return event
    }

    private func draggedEvent(button: Int, deltaX: Double, deltaY: Double = 0) throws -> CGEvent {
        let mouseButton = CGMouseButton(rawValue: UInt32(button)) ?? .center
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: mouseButton.fixedCGEventType(of: .otherMouseDragged),
            mouseCursorPosition: .zero,
            mouseButton: mouseButton
        ))
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        event.setDoubleValueField(.mouseEventDeltaX, value: deltaX)
        event.setDoubleValueField(.mouseEventDeltaY, value: deltaY)
        return event
    }

    private func mouseMovedEvent(deltaX: Double, deltaY: Double = 0) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: .zero,
            mouseButton: .center
        ))
        event.setDoubleValueField(.mouseEventDeltaX, value: deltaX)
        event.setDoubleValueField(.mouseEventDeltaY, value: deltaY)
        return event
    }

    private func scrollEvent(horizontal: Int32 = 0, vertical: Int32 = 0) throws -> CGEvent {
        try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        ))
    }

    private func logitech(
        _ identity: LogitechControlIdentity,
        pressed: Bool,
        allowsIdentityFallback: Bool = false
    ) -> LogitechEventContext {
        .init(
            device: nil,
            pid: nil,
            display: nil,
            mouseLocation: .zero,
            controlIdentity: identity,
            allowsIdentityFallback: allowsIdentityFallback,
            isPressed: pressed,
            modifierFlags: []
        )
    }

    private func ms(_ milliseconds: UInt64) -> UInt64 {
        milliseconds * 1_000_000
    }
}
