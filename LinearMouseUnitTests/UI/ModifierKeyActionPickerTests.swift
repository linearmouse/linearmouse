// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import SwiftUI
import XCTest

final class ModifierKeyActionPickerTests: XCTestCase {
    func testNilActionBindingDisplaysDefaultAction() {
        let binding = makeActionBinding(action: nil)

        XCTAssertEqual(binding.kind.wrappedValue, Scheme.Scrolling.Modifiers.Action.Kind.defaultAction)
    }

    func testSelectingDefaultActionStoresAutoAction() {
        var action: Scheme.Scrolling.Modifiers.Action?
        let binding = makeActionBinding(action: action) { action = $0 }

        binding.kind.wrappedValue = .defaultAction

        XCTAssertEqual(action, .auto)
    }

    func testSelectingNoActionStoresPreventDefaultAction() {
        var action: Scheme.Scrolling.Modifiers.Action?
        let binding = makeActionBinding(action: action) { action = $0 }

        binding.kind.wrappedValue = .noAction

        XCTAssertEqual(action, .preventDefault)
    }

    func testChangeSpeedFactorBindingRoundsToNearestHalfAboveOne() {
        var action: Scheme.Scrolling.Modifiers.Action? = .changeSpeed(scale: 1)
        let binding = makeActionBinding(action: action) { action = $0 }

        binding.speedFactor.wrappedValue = 2.74

        XCTAssertEqual(action, .changeSpeed(scale: 2.5))
    }

    private func makeActionBinding(
        action: Scheme.Scrolling.Modifiers.Action?,
        setter: @escaping (Scheme.Scrolling.Modifiers.Action?) -> Void = { _ in }
    ) -> Binding<Scheme.Scrolling.Modifiers.Action?> {
        Binding(
            get: { action },
            set: setter
        )
    }
}
