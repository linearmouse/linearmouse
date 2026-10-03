// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
@testable import LinearMouse
import XCTest

final class HoverWindowQueryTests: XCTestCase {
    private func window(_ id: UInt32, layer: Int = 0, alpha: Double = 1) -> [String: Any] {
        [
            kCGWindowNumber as String: id,
            kCGWindowOwnerPID as String: pid_t(id + 10),
            kCGWindowLayer as String: layer,
            kCGWindowAlpha as String: alpha,
            kCGWindowBounds as String: CGRect(x: -100, y: -100, width: 200, height: 200)
                .dictionaryRepresentation
        ]
    }

    func testOverlappingWindowsChooseOnlyTopmostVisibleWindow() {
        let target = HoverWindowQuery.hitTest([window(1), window(2)], at: .zero)
        XCTAssertEqual(target?.windowID, 1)
        XCTAssertEqual(target?.pid, 11)
    }

    func testMenuOrDockOverlayBlocksWindowUnderneath() {
        for layer in [3, 20, 24, 101] {
            XCTAssertNil(HoverWindowQuery.hitTest([window(1, layer: layer), window(2)], at: .zero))
        }
    }

    func testTransparentOverlayDoesNotHideNormalWindow() {
        XCTAssertEqual(
            HoverWindowQuery.hitTest([window(1, layer: 24, alpha: 0), window(2)], at: .zero)?.windowID,
            2
        )
    }

    func testSecondaryDisplayCoordinatesAndOutsideBounds() {
        XCTAssertEqual(HoverWindowQuery.hitTest([window(1)], at: .init(x: -50, y: -50))?.windowID, 1)
        XCTAssertNil(HoverWindowQuery.hitTest([window(1)], at: .init(x: 200, y: 0)))
    }
}
