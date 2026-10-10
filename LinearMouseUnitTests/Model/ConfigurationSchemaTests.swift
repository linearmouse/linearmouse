// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import XCTest

final class ConfigurationSchemaTests: XCTestCase {
    func testSwipeSettingsDeclareDefaultsAndThresholdBounds() throws {
        let swipe = try definition(named: "Scheme.Buttons.Swipe")
        let properties = try XCTUnwrap(swipe["properties"] as? [String: [String: Any]])
        let threshold = try XCTUnwrap(properties["threshold"])
        XCTAssertEqual(threshold["default"] as? Double, 50)
        XCTAssertEqual(threshold["minimum"] as? Double, 10)
        XCTAssertEqual(threshold["maximum"] as? Double, 200)
        XCTAssertEqual(properties["lockPointer"]?["default"] as? Bool, false)
    }

    func testLegacyGestureConfigurationIsDeprecated() throws {
        let buttons = try definition(named: "Scheme.Buttons")
        let properties = try XCTUnwrap(buttons["properties"] as? [String: [String: Any]])
        XCTAssertEqual(properties["gesture"]?["deprecated"] as? Bool, true)
        XCTAssertNil(properties["mappings"]?["deprecated"])

        for name in [
            "Scheme.Buttons.Gesture", "Scheme.Buttons.Gesture.Trigger",
            "Scheme.Buttons.Gesture.Actions", "Scheme.Buttons.Gesture.GestureAction"
        ] {
            let legacy = try definition(named: name)
            XCTAssertEqual(legacy["deprecated"] as? Bool, true, name)
            for (field, property) in legacy["properties"] as? [String: [String: Any]] ?? [:] {
                XCTAssertEqual(property["deprecated"] as? Bool, true, "\(name).\(field)")
            }
        }
    }

    /// The committed JSON schema is generated from `Documentation/Configuration.d.ts`
    /// and lives outside the test bundle. Resolve it by walking up from this source
    /// file to the repository root, which stays valid regardless of the checkout path.
    private func configurationSchemaURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 10 {
            let candidate = url.appendingPathComponent("Documentation/Configuration.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            url = url.deletingLastPathComponent()
        }
        throw NSError(
            domain: "ConfigurationSchemaTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate Documentation/Configuration.json from \(#filePath)"]
        )
    }

    private func definition(
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let url = try configurationSchemaURL()
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let definitions = try XCTUnwrap(json?["definitions"] as? [String: Any], file: file, line: line)
        return try XCTUnwrap(definitions[name] as? [String: Any], "Missing definition \(name)", file: file, line: line)
    }

    /// The Pointer speed field clamps to `0 ... 1` in the Swift runtime
    /// (`Scheme.Speed.range`). The JSDoc tag producing the lower bound was
    /// misspelled `@minimal` instead of `@minimum`, so the schema generator
    /// dropped it: the published schema admitted negative speeds while the
    /// runtime rejected them. Pin both bounds so the schema keeps tracking the
    /// runtime clamp.
    func testPointerSpeedDeclaresBothBounds() throws {
        let pointer = try definition(named: "Scheme.Pointer")
        let properties = try XCTUnwrap(pointer["properties"] as? [String: Any])
        let speed = try XCTUnwrap(properties["speed"] as? [String: Any], "Missing Pointer.speed property")

        let minimum = try XCTUnwrap(
            (speed["minimum"] as? NSNumber)?.doubleValue,
            "Pointer speed must declare a minimum bound matching the runtime clamp (0 ... 1)."
        )
        let maximum = try XCTUnwrap(
            (speed["maximum"] as? NSNumber)?.doubleValue,
            "Pointer speed must keep its maximum bound (regression guard)."
        )

        XCTAssertEqual(minimum, 0, accuracy: 1e-9, "Pointer speed minimum should be 0.")
        XCTAssertEqual(maximum, 1, accuracy: 1e-9, "Pointer speed maximum should be 1.")
    }
}
