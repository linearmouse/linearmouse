// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
@testable import LinearMouse
import XCTest

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
}
