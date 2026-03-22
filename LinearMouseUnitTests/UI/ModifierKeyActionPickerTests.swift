// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import SwiftUI
import XCTest

final class ModifierKeyActionPickerTests: XCTestCase {
    func testNilActionDisplaysDefaultAction() {
        let picker = makePicker(action: nil)

        XCTAssertEqual(picker.actionType.wrappedValue, .defaultAction)
    }

    func testSelectingDefaultActionStoresAutoAction() {
        var action: Scheme.Scrolling.Modifiers.Action?
        let picker = makePicker(action: action) { action = $0 }

        picker.actionType.wrappedValue = .defaultAction

        XCTAssertEqual(action, .auto)
    }

    func testSelectingNoActionStoresPreventDefaultAction() {
        var action: Scheme.Scrolling.Modifiers.Action?
        let picker = makePicker(action: action) { action = $0 }

        picker.actionType.wrappedValue = .noAction

        XCTAssertEqual(action, .preventDefault)
    }

    private func makePicker(
        action: Scheme.Scrolling.Modifiers.Action?,
        setter: @escaping (Scheme.Scrolling.Modifiers.Action?) -> Void = { _ in }
    ) -> ScrollingSettings.ModifierKeysSection.ModifierKeyActionPicker {
        ScrollingSettings.ModifierKeysSection.ModifierKeyActionPicker(
            label: "Test",
            action: Binding(
                get: { action },
                set: setter
            )
        )
    }
}
