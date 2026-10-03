// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

/// Pure transformer replay: no shared configuration writes or event posting.
/// Use an optimized Debug build to retain the existing test-host isolation.
final class PointerMotionPerformanceTests: XCTestCase {
    func testConfiguredDragPipelinePerformance() throws {
        let transformers: [EventTransformer] = [
            ReverseScrollingTransformer(vertically: true, horizontally: false),
            SwitchPrimaryAndSecondaryButtonsTransformer(),
            LinearScrollingVerticalTransformer(distance: .pixel(2)),
            LibinputClickDebouncingTransformer(for: .left),
            LibinputClickDebouncingTransformer(for: .right),
            LibinputClickDebouncingTransformer(for: .center)
        ]
        let context = EventTransformerContext(device: nil) { _ in
            XCTFail("Dragging must not post a deferred event")
        }
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDragged,
            mouseCursorPosition: .zero,
            mouseButton: .left
        ))
        _ = transformers.transform(event, in: context)
        measure {
            for _ in 0 ..< 10_000 {
                _ = transformers.transform(event, in: context)
            }
        }
    }
}
