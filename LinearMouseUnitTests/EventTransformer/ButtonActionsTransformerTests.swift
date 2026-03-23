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

        let handled = transformer.handleLogitechControlEvent(.init(
            device: nil,
            pid: nil,
            display: nil,
            controlIdentity: .init(controlID: 0x0053),
            isPressed: false,
            modifierFlags: [.maskCommand, .init(rawValue: UInt64(NX_DEVICERCMDKEYMASK))]
        ))

        XCTAssertTrue(handled)
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

        let handled = transformer.handleLogitechControlEvent(.init(
            device: nil,
            pid: nil,
            display: nil,
            controlIdentity: .init(controlID: 0x0053, productID: 0x405E, serialNumber: nil),
            isPressed: false,
            modifierFlags: []
        ))

        XCTAssertTrue(handled)
    }

    func testLogitechControlEventMatchesWithPartialIdentity() {
        // A mapping with only controlID should match an event with full identity
        let transformer = ButtonActionsTransformer(mappings: [
            .init(
                button: .logitechControl(.init(controlID: 0x00C3)),
                action: .arg0(.none)
            )
        ])

        let handled = transformer.handleLogitechControlEvent(.init(
            device: nil,
            pid: nil,
            display: nil,
            controlIdentity: .init(
                controlID: 0x00C3,
                productID: 0x405E,
                serialNumber: "45AFAFA6"
            ),
            isPressed: false,
            modifierFlags: []
        ))

        XCTAssertTrue(handled)
    }

    func testLogitechConfiguredProductIDMatchesEventWithoutSerialNumber() {
        let transformer = ButtonActionsTransformer(mappings: [
            .init(
                button: .logitechControl(.init(controlID: 0x00C3, productID: 0x405E, serialNumber: nil)),
                action: .arg0(.none)
            )
        ])

        let handled = transformer.handleLogitechControlEvent(.init(
            device: nil,
            pid: nil,
            display: nil,
            controlIdentity: .init(controlID: 0x00C3, productID: 0x405E, serialNumber: nil),
            isPressed: false,
            modifierFlags: []
        ))

        XCTAssertTrue(handled)
    }
}
