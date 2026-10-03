// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class GestureMigrationTests: XCTestCase {
    private typealias Mapping = Scheme.Buttons.Mapping

    func testMigrationPreservesDefaultsAndIsIdempotentAcrossSerialization() throws {
        var configuration = try load(#"{"gesture":{"enabled":true,"button":2}}"#)
        XCTAssertTrue(configuration.migrateLegacyGestureButtons())
        let mapping = try XCTUnwrap(configuration.schemes[0].buttons.mappings?.first)
        XCTAssertEqual(mapping.trigger?.input, .button(.mouse(2)))
        XCTAssertEqual(mapping.outcomes?.swipe?.left, .arg0(.missionControlSpaceLeft))
        XCTAssertEqual(mapping.outcomes?.swipe?.right, .arg0(.missionControlSpaceRight))
        XCTAssertEqual(mapping.outcomes?.swipe?.up, .arg0(.missionControl))
        XCTAssertEqual(mapping.outcomes?.swipe?.down, .arg0(.appExpose))
        XCTAssertNil(configuration.schemes[0].buttons.$gesture)
        var restored = try Configuration.load(from: configuration.dump())
        XCTAssertFalse(restored.migrateLegacyGestureButtons())
        XCTAssertEqual(configuration, restored)
    }

    func testCustomDistancesAreDiscardedWithoutExtendingMappingConfiguration() throws {
        var configuration = try load(#"""
        {"gesture":{"enabled":true,"trigger":{"button":1,"shift":true},
          "threshold":90,"deadZone":20,"actions":{"left":"none","right":"showDesktop"}}}
        """#)
        configuration.migrateLegacyGestureButtons()
        let mapping = try XCTUnwrap(configuration.schemes[0].buttons.mappings?.first)
        XCTAssertEqual(mapping.trigger?.modifiers, [.shift])
        XCTAssertEqual(mapping.outcomes?.swipe?.left, .arg0(.none))
        XCTAssertEqual(mapping.outcomes?.swipe?.right, .arg0(.showDesktop))
        var engine = ButtonMappingEngine(mappings: [mapping])
        _ = engine.buttonDown(.mouse(1), modifierFlags: [.maskShift], at: 0)
        // Uses the existing 50/40 policy, not the legacy gesture's 90/20.
        XCTAssertEqual(engine.pointerMoved(deltaX: 60, deltaY: 25, at: 1).actions, [.arg0(.showDesktop)])
        let json = try XCTUnwrap(String(data: configuration.dump(), encoding: .utf8))
        XCTAssertFalse(json.contains("threshold"))
        XCTAssertFalse(json.contains("deadZone"))
        var boundary = ButtonMappingEngine(mappings: [mapping])
        _ = boundary.buttonDown(.mouse(1), modifierFlags: [.maskShift], at: 0)
        XCTAssertTrue(boundary.pointerMoved(deltaX: 60, deltaY: 40, at: 1).actions.isEmpty)
    }

    func testExistingMappingOutcomesTakePriorityAndShortPressIsPreserved() throws {
        var configuration = try load(#"""
        {"gesture":{"enabled":true,"button":2},"mappings":[
          {"trigger":{"input":{"button":2}},"outcomes":{
            "shortPress":"launchpad","swipe":{"right":"showDesktop"}}}]}
        """#)
        configuration.migrateLegacyGestureButtons()
        let mappings = try XCTUnwrap(configuration.schemes[0].buttons.mappings)
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings[0].outcomes?.shortPress, .arg0(.launchpad))
        XCTAssertEqual(mappings[0].outcomes?.swipe?.right, .arg0(.showDesktop))
        XCTAssertEqual(mappings[0].outcomes?.swipe?.left, .arg0(.missionControlSpaceLeft))
    }

    func testDisabledApplicationOverrideSuppressesInheritedGesture() throws {
        var configuration = try Configuration.load(from: #"""
        {"schemes":[
          {"buttons":{"gesture":{"enabled":true,"button":2}}},
          {"if":{"app":"com.apple.finder"},"buttons":{"gesture":{"enabled":false}}}
        ]}
        """#)
        configuration.migrateLegacyGestureButtons()
        var finder = ButtonMappingEngine(mappings: configuration.matchScheme(
            withDeviceMatcher: nil,
            withApp: "com.apple.finder"
        )
        .buttons
        .mappings ?? [])
        XCTAssertFalse(finder.buttonDown(.mouse(2), modifierFlags: [], at: 0).consumesEvent)
        var other = ButtonMappingEngine(mappings: configuration.matchScheme(withDeviceMatcher: nil, withApp: "other")
            .buttons
            .mappings ?? [])
        XCTAssertTrue(other.buttonDown(.mouse(2), modifierFlags: [], at: 0).consumesEvent)
    }

    func testChangingGestureButtonInLaterSchemeSuppressesPreviousButton() throws {
        var configuration = try Configuration.load(from: #"""
        {"schemes":[
          {"buttons":{"gesture":{"enabled":true,"button":2}}},
          {"buttons":{"gesture":{"enabled":true,"button":4}}}
        ]}
        """#)
        configuration.migrateLegacyGestureButtons()
        var engine = ButtonMappingEngine(mappings: configuration.matchScheme(withDeviceMatcher: nil, withApp: "test")
            .buttons
            .mappings ?? [])
        XCTAssertFalse(engine.buttonDown(.mouse(2), modifierFlags: [], at: 0).consumesEvent)
        XCTAssertTrue(engine.buttonDown(.mouse(4), modifierFlags: [], at: 1).consumesEvent)
    }

    func testLogitechTriggerIsPreserved() throws {
        var configuration = try load(#"""
        {"gesture":{"enabled":true,"trigger":{"button":{"kind":"logitechControl","controlID":195}}}}
        """#)
        let trigger = configuration.schemes[0].buttons.gesture.trigger?.effectiveTrigger
        configuration.migrateLegacyGestureButtons()
        XCTAssertEqual(configuration.schemes[0].buttons.mappings?.first?.trigger, trigger)
        XCTAssertNil(configuration.schemes[0].buttons.$gesture)
    }

    func testDisabledGestureDoesNotBecomeEnabled() throws {
        var configuration = try load(#"{"gesture":{"enabled":false,"button":2}}"#)
        XCTAssertTrue(configuration.migrateLegacyGestureButtons())
        XCTAssertNil(configuration.schemes[0].buttons.mappings)
        XCTAssertNil(configuration.schemes[0].buttons.$gesture)
    }

    func testPlainLoadDoesNotMigrateLegacyGesture() throws {
        let configuration = try load(#"{"gesture":{"enabled":true,"button":2}}"#)
        XCTAssertNotNil(configuration.schemes[0].buttons.$gesture)
        XCTAssertNil(configuration.schemes[0].buttons.mappings)
    }

    func testStartupMigrationBacksUpSymlinkContentsAndPersistsOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("source.json")
        let url = directory.appendingPathComponent("linearmouse.json")
        let original = try load(#"{"gesture":{"enabled":true,"button":2}}"#).dump()
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        var configuration = try Configuration.load(from: url)
        try configuration.migrateLegacyGestureButtons(persistingTo: url)
        let backup = url.appendingPathExtension("before-gesture-migration")
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(try Configuration.load(from: url), configuration)
        XCTAssertNil(configuration.schemes[0].buttons.$gesture)
        let firstSave = try Data(contentsOf: target)
        try configuration.migrateLegacyGestureButtons(persistingTo: url)
        XCTAssertEqual(try Data(contentsOf: target), firstSave)
        XCTAssertEqual(try Data(contentsOf: backup), original)
    }

    func testFailedPersistenceLeavesLegacyConfigurationIntact() throws {
        var configuration = try load(#"{"gesture":{"enabled":true,"button":2}}"#)
        let original = configuration
        let missing = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.json")
        XCTAssertThrowsError(try configuration.migrateLegacyGestureButtons(persistingTo: missing))
        XCTAssertEqual(configuration, original)
    }

    func testExistingMappingOrderIsPreserved() throws {
        var configuration = try load(#"""
        {"gesture":{"enabled":true,"button":2},"mappings":[
          {"button":4,"action":"showDesktop"}, {"button":2,"action":"launchpad"}]}
        """#)
        configuration.migrateLegacyGestureButtons()
        XCTAssertEqual(
            configuration.schemes[0].buttons.mappings?.map(\.trigger?.input),
            [.button(.mouse(4)), .button(.mouse(2))]
        )
    }

    func testDisablingGesturePreservesOrdinarySwipeInAnotherApplication() throws {
        var configuration = try Configuration.load(from: #"""
        {"schemes":[
          {"if":{"app":"app.a"},"buttons":{"gesture":{"enabled":true,"button":2}}},
          {"buttons":{"mappings":[{"trigger":{"input":{"button":2}},
            "outcomes":{"swipe":{"right":"none"}}}]}},
          {"if":{"app":"app.b"},"buttons":{"gesture":{"enabled":false}}}
        ]}
        """#)
        configuration.migrateLegacyGestureButtons()
        var engine = ButtonMappingEngine(mappings: configuration.matchScheme(withDeviceMatcher: nil, withApp: "app.b")
            .buttons
            .mappings ?? [])
        XCTAssertTrue(engine.buttonDown(.mouse(2), modifierFlags: [], at: 0).consumesEvent)
        XCTAssertEqual(engine.pointerMoved(deltaX: 60, deltaY: 0, at: 1).actions, [.arg0(.none)])
    }

    func testDisablingGestureRestoresOrdinaryPressLifecycle() throws {
        for behavior in ["perform", "repeat", "hold"] {
            var configuration = try Configuration.load(from: """
            {"schemes":[
              {"buttons":{"gesture":{"enabled":true,"button":2}}},
              {"buttons":{"mappings":[{"trigger":{"input":{"button":2}},
                "outcomes":{"press":{"action":{"keyPress":["a"]},"behavior":"\(behavior)"}}}]}},
              {"if":{"app":"app.b"},"buttons":{"gesture":{"enabled":false}}}
            ]}
            """)
            configuration.migrateLegacyGestureButtons()
            var engine = ButtonMappingEngine(mappings: configuration
                .matchScheme(withDeviceMatcher: nil, withApp: "app.b")
                .buttons
                .mappings ?? [])
            let output = engine.buttonDown(.mouse(2), modifierFlags: [], at: 0)
            XCTAssertEqual(output.lifecycleEvents.count, 1, behavior)
        }
    }

    func testRestoredMappingsKeepApplicationDeviceAndDisplayConditions() throws {
        var configuration = try Configuration.load(from: #"""
        {"schemes":[
          {"buttons":{"gesture":{"enabled":true,"button":2}}},
          {"if":[{"app":"app.b","device":{"category":"mouse"},"display":"Screen"},
                  {"app":"app.c","device":{"category":"mouse"},"display":"Screen"}],
           "buttons":{"mappings":[{"trigger":{"input":{"button":2}},
             "outcomes":{"swipe":{"right":"none"}}}]}},
          {"if":{"app":"app.b","device":{"vendorID":123}},"buttons":{"gesture":{"enabled":false}}}
        ]}
        """#)
        configuration.migrateLegacyGestureButtons()
        configuration = try Configuration.load(from: configuration.dump())
        XCTAssertFalse(configuration.migrateLegacyGestureButtons())
        for category: DeviceMatcher.Category in [.mouse, .trackpad] {
            for display in ["Screen", "Other"] {
                let device = DeviceMatcher(vendorID: 123, category: [category])
                var engine = ButtonMappingEngine(mappings: configuration.matchScheme(
                    withDeviceMatcher: device, withApp: "app.b", withDisplay: display
                )
                .buttons
                .mappings ?? [])
                XCTAssertEqual(
                    engine.buttonDown(.mouse(2), modifierFlags: [], at: 0).consumesEvent,
                    category == .mouse && display == "Screen"
                )
            }
        }
    }

    func testChangingGestureButtonRestoresPreviousButtonsOrdinaryMapping() throws {
        var configuration = try Configuration.load(from: #"""
        {"schemes":[
          {"buttons":{"gesture":{"enabled":true,"button":2},"mappings":[
            {"trigger":{"input":{"button":2}},"outcomes":{"swipe":{"right":"none"}}}]}},
          {"buttons":{"gesture":{"enabled":true,"button":4}}}
        ]}
        """#)
        configuration.migrateLegacyGestureButtons()
        let mappings = configuration.matchScheme(withDeviceMatcher: nil).buttons.mappings ?? []
        var oldButton = ButtonMappingEngine(mappings: mappings)
        _ = oldButton.buttonDown(.mouse(2), modifierFlags: [], at: 0)
        XCTAssertEqual(oldButton.pointerMoved(deltaX: 60, deltaY: 0, at: 1).actions, [.arg0(.none)])
        var newButton = ButtonMappingEngine(mappings: mappings)
        XCTAssertTrue(newButton.buttonDown(.mouse(4), modifierFlags: [], at: 0).consumesEvent)
    }

    func testMigrationUsesLegacyFieldRatherThanSchemaVersion() throws {
        for version in ["0.1.0", "0.13.0-beta.2", "99.0.0"] {
            var configuration = try Configuration.load(from: """
            {"$schema":"https://schema.linearmouse.app/\(version)",
             "schemes":[{"buttons":{"gesture":{"enabled":true,"button":2}}}]}
            """)
            XCTAssertTrue(configuration.migrateLegacyGestureButtons())
            XCTAssertNil(configuration.schemes[0].buttons.$gesture)
            XCTAssertFalse(configuration.migrateLegacyGestureButtons())
        }
        var current = Configuration(schemes: [])
        XCTAssertFalse(current.migrateLegacyGestureButtons())
    }

    private func load(_ buttons: String) throws -> Configuration {
        try Configuration.load(from: "{\"schemes\":[{\"buttons\":\(buttons)}]}")
    }
}
