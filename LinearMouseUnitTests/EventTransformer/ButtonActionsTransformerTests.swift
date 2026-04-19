// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import KeyKit
@testable import LinearMouse
import XCTest

private final class RecordingKeySimulator: KeySimulating {
    enum Event: Equatable {
        case down([Key])
        case up([Key])
        case press([Key])
        case reset
    }

    private(set) var events: [Event] = []

    func down(keys: [Key], tap _: CGEventTapLocation?) throws {
        events.append(.down(keys))
    }

    func up(keys: [Key], tap _: CGEventTapLocation?) throws {
        events.append(.up(keys))
    }

    func press(keys: [Key], tap _: CGEventTapLocation?) throws {
        events.append(.press(keys))
    }

    func reset() {
        events.append(.reset)
    }

    func modifiedCGEventFlags(of _: CGEvent) -> CGEventFlags? {
        nil
    }
}

private func logitechContext(
    _ controlID: Int,
    pressed: Bool
) -> LogitechEventContext {
    .init(
        device: nil,
        pid: nil,
        display: nil,
        mouseLocation: .zero,
        controlIdentity: .init(controlID: controlID),
        isPressed: pressed,
        modifierFlags: []
    )
}

final class ButtonActionsTransformerTests: XCTestCase {
    func testLogitechControlEventMatchesGenericCommandMappingWithRightCommandFlag() {
        let transformer = ButtonActionsTransformer(mappings: [
            .init(
                button: .logitechControl(.init(controlID: 0x0053)),
                command: true,
                action: .arg0(.none)
            )
        ])

        let result = transformer.findLogitechMapping(for: .init(
            device: nil,
            pid: nil,
            display: nil,
            mouseLocation: .zero,
            controlIdentity: .init(controlID: 0x0053),
            isPressed: false,
            modifierFlags: [.maskCommand, .init(rawValue: UInt64(NX_DEVICERCMDKEYMASK))]
        ))

        XCTAssertNotNil(result)
    }

    func testLogitechSpecificMappingWinsOverGenericMapping() {
        let transformer = ButtonActionsTransformer(mappings: [
            .init(
                button: .logitechControl(.init(controlID: 0x0053, productID: 0x405E, serialNumber: nil)),
                action: .arg0(.mouseButtonBack)
            ),
            .init(
                button: .logitechControl(.init(controlID: 0x0053)),
                action: .arg0(.auto)
            )
        ])

        let result = transformer.findLogitechMapping(for: .init(
            device: nil,
            pid: nil,
            display: nil,
            mouseLocation: .zero,
            controlIdentity: .init(controlID: 0x0053, productID: 0x405E, serialNumber: nil),
            isPressed: false,
            modifierFlags: []
        ))

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.action, Scheme.Buttons.Mapping.Action.arg0(.mouseButtonBack))
    }

    func testLogitechControlEventMatchesWithPartialIdentity() {
        // A mapping with only controlID should match an event with full identity
        let transformer = ButtonActionsTransformer(mappings: [
            .init(
                button: .logitechControl(.init(controlID: 0x00C3)),
                action: .arg0(.none)
            )
        ])

        let result = transformer.findLogitechMapping(for: .init(
            device: nil,
            pid: nil,
            display: nil,
            mouseLocation: .zero,
            controlIdentity: .init(
                controlID: 0x00C3,
                productID: 0x405E,
                serialNumber: "45AFAFA6"
            ),
            isPressed: false,
            modifierFlags: []
        ))

        XCTAssertNotNil(result)
    }

    func testLogitechConfiguredProductIDMatchesEventWithoutSerialNumber() {
        let transformer = ButtonActionsTransformer(mappings: [
            .init(
                button: .logitechControl(.init(controlID: 0x00C3, productID: 0x405E, serialNumber: nil)),
                action: .arg0(.none)
            )
        ])

        let result = transformer.findLogitechMapping(for: .init(
            device: nil,
            pid: nil,
            display: nil,
            mouseLocation: .zero,
            controlIdentity: .init(controlID: 0x00C3, productID: 0x405E, serialNumber: nil),
            isPressed: false,
            modifierFlags: []
        ))

        XCTAssertNotNil(result)
    }

    // MARK: - Hold-while-pressed

    func testHoldKeyPressDownOnButtonDownAndUpOnButtonUp() {
        let simulator = RecordingKeySimulator()
        let transformer = ButtonActionsTransformer(
            mappings: [
                .init(
                    button: .logitechControl(.init(controlID: 0x0001)),
                    hold: true,
                    action: .arg1(.keyPress([.a]))
                )
            ],
            keySimulator: simulator
        )

        XCTAssertTrue(transformer.handleLogitechControlEvent(logitechContext(0x0001, pressed: true)))
        XCTAssertTrue(transformer.handleLogitechControlEvent(logitechContext(0x0001, pressed: false)))

        XCTAssertEqual(simulator.events, [.down([.a]), .up([.a]), .reset])
    }

    func testHoldDoesNotResendDownIfButtonRepeats() {
        let simulator = RecordingKeySimulator()
        let transformer = ButtonActionsTransformer(
            mappings: [
                .init(
                    button: .logitechControl(.init(controlID: 0x0001)),
                    hold: true,
                    action: .arg1(.keyPress([.a]))
                )
            ],
            keySimulator: simulator
        )

        _ = transformer.handleLogitechControlEvent(logitechContext(0x0001, pressed: true))
        // A second pressed=true event for the same button (e.g. a stuttering report) should not
        // re-emit a key down — `pressAndStoreHeldKeys` short-circuits when the same keys are
        // already tracked.
        _ = transformer.handleLogitechControlEvent(logitechContext(0x0001, pressed: true))

        XCTAssertEqual(simulator.events, [.down([.a])])
    }

    func testOverlappingHoldsDoNotResetWhileAnotherHoldIsActive() {
        let simulator = RecordingKeySimulator()
        let transformer = ButtonActionsTransformer(
            mappings: [
                .init(
                    button: .logitechControl(.init(controlID: 0x0001)),
                    hold: true,
                    action: .arg1(.keyPress([.command]))
                ),
                .init(
                    button: .logitechControl(.init(controlID: 0x0002)),
                    hold: true,
                    action: .arg1(.keyPress([.shift]))
                )
            ],
            keySimulator: simulator
        )

        _ = transformer.handleLogitechControlEvent(logitechContext(0x0001, pressed: true))
        _ = transformer.handleLogitechControlEvent(logitechContext(0x0002, pressed: true))
        _ = transformer.handleLogitechControlEvent(logitechContext(0x0002, pressed: false))
        _ = transformer.handleLogitechControlEvent(logitechContext(0x0001, pressed: false))

        // Crucially: no `.reset` between releasing button 2 and releasing button 1, so the
        // KeySimulator's tracked modifier flags still know command is held while shift is gone.
        XCTAssertEqual(simulator.events, [
            .down([.command]),
            .down([.shift]),
            .up([.shift]),
            .up([.command]),
            .reset
        ])
    }

    func testHoldFallsBackToFallbackKeysWhenNothingTracked() {
        // If a button-up arrives with no prior down (e.g. the down event was filtered out by
        // app-specific matching), `releaseHeldKeys` still releases the action's keys so the
        // synthetic key never gets stuck.
        let simulator = RecordingKeySimulator()
        let transformer = ButtonActionsTransformer(
            mappings: [
                .init(
                    button: .logitechControl(.init(controlID: 0x0001)),
                    hold: true,
                    action: .arg1(.keyPress([.a]))
                )
            ],
            keySimulator: simulator
        )

        _ = transformer.handleLogitechControlEvent(logitechContext(0x0001, pressed: false))

        XCTAssertEqual(simulator.events, [.up([.a]), .reset])
    }
}
