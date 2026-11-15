// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ConfigurationPathTests: XCTestCase {
    private let applicationSupport =
        URL(fileURLWithPath: "/Users/u/Library/Application Support/linearmouse/linearmouse.json")
    private let legacy = URL(fileURLWithPath: "/Users/u/.config/linearmouse/linearmouse.json")

    private func path(existing: Set<URL>) -> URL {
        let existingPaths = Set(existing.map(\.path))
        return ConfigurationState.configurationPath(in: [applicationSupport, legacy]) {
            existingPaths.contains($0)
        }
    }

    func testNewConfigurationGoesToApplicationSupport() {
        XCTAssertEqual(path(existing: []), applicationSupport)
    }

    func testExistingLegacyConfigurationKeepsBeingUsed() {
        XCTAssertEqual(path(existing: [legacy]), legacy)
    }

    func testApplicationSupportWinsWhenBothExist() {
        XCTAssertEqual(path(existing: [applicationSupport, legacy]), applicationSupport)
        XCTAssertEqual(path(existing: [applicationSupport]), applicationSupport)
    }
}
