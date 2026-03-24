// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class UniversalBackForwardTransformerTests: XCTestCase {
    func testReplacementUsesSwipeForBackInSupportedApp() {
        XCTAssertEqual(
            UniversalBackForwardTransformer.replacement(
                for: .back,
                universalBackForward: .both,
                targetBundleIdentifier: "com.apple.Safari"
            ),
            .navigationSwipe(.left)
        )
    }

    func testReplacementUsesSwipeForForwardInSupportedApp() {
        XCTAssertEqual(
            UniversalBackForwardTransformer.replacement(
                for: .forward,
                universalBackForward: .both,
                targetBundleIdentifier: "com.binarynights.ForkLift"
            ),
            .navigationSwipe(.right)
        )
    }

    func testReplacementFallsBackToMouseButtonWhenUniversalBackForwardDisabled() {
        XCTAssertEqual(
            UniversalBackForwardTransformer.replacement(
                for: .back,
                universalBackForward: .none,
                targetBundleIdentifier: "com.apple.Safari"
            ),
            .mouseButton(.back)
        )
    }

    func testReplacementFallsBackToMouseButtonWhenDirectionIsNotEnabled() {
        XCTAssertEqual(
            UniversalBackForwardTransformer.replacement(
                for: .forward,
                universalBackForward: .backOnly,
                targetBundleIdentifier: "com.apple.Safari"
            ),
            .mouseButton(.forward)
        )
    }

    func testReplacementFallsBackToMouseButtonInUnsupportedApp() {
        XCTAssertEqual(
            UniversalBackForwardTransformer.replacement(
                for: .back,
                universalBackForward: .both,
                targetBundleIdentifier: "com.example.CustomBrowser"
            ),
            .mouseButton(.back)
        )
    }
}
