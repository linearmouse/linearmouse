// MIT License
// Copyright (c) 2021-2026 LinearMouse

import KeyKit
@testable import LinearMouse
import SwiftUI
import XCTest

final class ButtonMappingActionBindingTests: XCTestCase {
    func testKindBindingReadsExistingActionKind() {
        let binding = makeActionBinding(.arg1(.mouseWheelScrollLeft(.pixel(12))))

        XCTAssertEqual(binding.kind.wrappedValue, .mouseWheelScrollLeft)
    }

    func testKindBindingWritesDefaultPayloadForScrollableAction() {
        var action: Scheme.Buttons.Mapping.Action = .arg0(.auto)
        let binding = makeActionBinding(action) { action = $0 }

        binding.kind.wrappedValue = .mouseWheelScrollUp

        XCTAssertEqual(action, .arg1(.mouseWheelScrollUp(.line(3))))
    }

    func testRunCommandBindingUpdatesCommand() {
        var action: Scheme.Buttons.Mapping.Action = .arg1(.run("open"))
        let binding = makeActionBinding(action) { action = $0 }

        binding.runCommand.wrappedValue = "say hi"

        XCTAssertEqual(action, .arg1(.run("say hi")))
    }

    func testScrollDistanceBindingUpdatesCurrentScrollAction() {
        var action: Scheme.Buttons.Mapping.Action = .arg1(.mouseWheelScrollDown(.line(3)))
        let binding = makeActionBinding(action) { action = $0 }

        binding.scrollDistance.wrappedValue = .pixel(24)

        XCTAssertEqual(action, .arg1(.mouseWheelScrollDown(.pixel(24))))
    }

    func testKeyPressKeysBindingUpdatesKeys() {
        var action: Scheme.Buttons.Mapping.Action = .arg1(.keyPress([]))
        let binding = makeActionBinding(action) { action = $0 }

        binding.keyPressKeys.wrappedValue = [.command, .a]

        XCTAssertEqual(action, .arg1(.keyPress([.command, .a])))
    }

    private func makeActionBinding(
        _ action: Scheme.Buttons.Mapping.Action,
        setter: @escaping (Scheme.Buttons.Mapping.Action) -> Void = { _ in }
    ) -> Binding<Scheme.Buttons.Mapping.Action> {
        Binding(
            get: { action },
            set: setter
        )
    }
}
