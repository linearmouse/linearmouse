// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import SwiftUI
import XCTest

final class ScrollingDistanceBindingTests: XCTestCase {
    func testModeBindingReadsAutoAsByLines() {
        let binding = makeDistanceBinding(.auto)

        XCTAssertEqual(binding.mode.wrappedValue, .byLines)
    }

    func testModeBindingWritesPixelDefault() {
        var distance: Scheme.Scrolling.Distance = .line(3)
        let binding = makeDistanceBinding(distance) { distance = $0 }

        binding.mode.wrappedValue = .byPixels

        XCTAssertEqual(distance, .pixel(36))
    }

    func testLineCountBindingUpdatesDistance() {
        var distance: Scheme.Scrolling.Distance = .line(3)
        let binding = makeDistanceBinding(distance) { distance = $0 }

        binding.lineCount.wrappedValue = 7

        XCTAssertEqual(distance, .line(7))
    }

    func testPixelCountBindingRoundsToSingleDecimalPlace() {
        var distance: Scheme.Scrolling.Distance = .pixel(10)
        let binding = makeDistanceBinding(distance) { distance = $0 }

        binding.pixelCount.wrappedValue = 12.34

        XCTAssertEqual(distance, .pixel(12.3))
    }

    private func makeDistanceBinding(
        _ distance: Scheme.Scrolling.Distance,
        setter: @escaping (Scheme.Scrolling.Distance) -> Void = { _ in }
    ) -> Binding<Scheme.Scrolling.Distance> {
        Binding(
            get: { distance },
            set: setter
        )
    }
}
