// MIT License
// Copyright (c) 2021-2026 LinearMouse

import KeyKit
@testable import LinearMouse
import XCTest

final class ButtonMappingConfigurationTests: XCTestCase {
    private typealias Mapping = Scheme.Buttons.Mapping

    func testLegacyButtonMappingMigratesWhenDecodedInsideButtons() throws {
        let json = #"{"mappings":[{"button":4,"command":true,"action":"missionControl"}]}"#
        let buttons = try JSONDecoder().decode(
            Scheme.Buttons.self,
            from: XCTUnwrap(json.data(using: .utf8))
        )
        let mapping = try XCTUnwrap(buttons.mappings?.first)

        XCTAssertEqual(mapping.trigger, .init(input: .button(.mouse(4)), modifiers: [.command]))
        XCTAssertEqual(mapping.outcomes?.shortPress, .arg0(.missionControl))
        XCTAssertNil(mapping.button)
        XCTAssertNil(mapping.command)
        XCTAssertNil(mapping.action)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(buttons)) as? [String: Any]
        )
        let mappings = try XCTUnwrap(object["mappings"] as? [[String: Any]])
        let encoded = try XCTUnwrap(mappings.first)
        XCTAssertNotNil(encoded["trigger"])
        XCTAssertNotNil(encoded["outcomes"])
        XCTAssertNil(encoded["button"])
        XCTAssertNil(encoded["command"])
        XCTAssertNil(encoded["repeat"])
        XCTAssertNil(encoded["hold"])
    }

    func testConfigurationLoadAndDumpMigratesLegacyLifecycleFields() throws {
        let configuration = try Configuration.load(from: #"""
        {
          "schemes": [{
            "buttons": {
              "mappings": [
                { "button": 4, "repeat": true, "action": "media.volumeUp" },
                { "button": 5, "hold": true, "action": { "keyPress": ["c"] } }
              ]
            }
          }]
        }
        """#)

        let mappings = try XCTUnwrap(configuration.schemes.first?.buttons.mappings)
        XCTAssertEqual(mappings[0].outcomes?.press?.behavior, .repeat)
        XCTAssertEqual(mappings[1].outcomes?.press?.behavior, .hold)

        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: configuration.dump()) as? [String: Any]
        )
        let schemes = try XCTUnwrap(root["schemes"] as? [[String: Any]])
        let buttons = try XCTUnwrap(schemes.first?["buttons"] as? [String: Any])
        let encodedMappings = try XCTUnwrap(buttons["mappings"] as? [[String: Any]])

        for mapping in encodedMappings {
            XCTAssertNotNil(mapping["trigger"])
            XCTAssertNotNil(mapping["outcomes"])
            XCTAssertNil(mapping["repeat"])
            XCTAssertNil(mapping["hold"])
        }
    }

    func testLegacyRepeatMigratesToRepeatPressOutcome() throws {
        let mapping = try decodeLegacyMapping(
            #"{"button":4,"repeat":true,"action":"media.volumeUp"}"#
        )

        XCTAssertEqual(
            mapping.outcomes?.press,
            .init(action: .arg0(.mediaVolumeUp), behavior: .repeat)
        )
        XCTAssertNil(mapping.outcomes?.shortPress)
    }

    func testLegacyHoldMigratesToHoldPressOutcome() throws {
        let mapping = try decodeLegacyMapping(
            #"{"button":4,"hold":true,"action":{"keyPress":["c"]}}"#
        )

        XCTAssertEqual(
            mapping.outcomes?.press,
            .init(action: .arg1(.keyPress([.c])), behavior: .hold)
        )
    }

    func testLegacyModifierOnlyKeyPressImplicitlyMigratesToHold() throws {
        let mapping = try decodeLegacyMapping(
            #"{"button":4,"action":{"keyPress":["command"]}}"#
        )

        XCTAssertEqual(mapping.outcomes?.press?.behavior, .hold)
    }

    func testLegacyPhysicalButtonSwapMigratesToRemapPressOutcome() throws {
        let mapping = try decodeLegacyMapping(
            #"{"button":4,"action":"mouse.button.left"}"#
        )

        XCTAssertEqual(
            mapping.outcomes?.press,
            .init(action: .arg0(.mouseButtonLeft), behavior: .remap)
        )
    }

    func testLegacyWheelMigratesToWheelTrigger() throws {
        let mapping = try decodeLegacyMapping(
            #"{"scroll":"up","option":true,"action":"media.volumeUp"}"#
        )

        XCTAssertEqual(mapping.trigger, .init(input: .wheel(.up), modifiers: [.option]))
        XCTAssertEqual(mapping.action, .arg0(.mediaVolumeUp))
        XCTAssertNil(mapping.scroll)
        XCTAssertNil(mapping.option)
    }

    func testLegacyMappingWithoutActionMigratesToExplicitPassThrough() throws {
        let mapping = try decodeLegacyMapping(#"{"button":4}"#)

        XCTAssertEqual(mapping.outcomes?.shortPress, .arg0(.auto))
        XCTAssertTrue(mapping.valid)
    }

    func testLegacyLogitechMouseButtonActionRemainsReleaseAction() throws {
        let mapping = try decodeLegacyMapping(
            #"{"button":{"kind":"logitechControl","controlID":83},"action":"mouse.button.back"}"#
        )

        XCTAssertNil(mapping.outcomes?.press)
        XCTAssertEqual(mapping.outcomes?.shortPress, .arg0(.mouseButtonBack))
    }

    func testMappingMigrationDoesNotRewriteAutoScrollTrigger() throws {
        let json = #"""
        {
          "mappings": [{ "button": 4, "action": "missionControl" }],
          "autoScroll": {
            "enabled": true,
            "trigger": { "button": 2, "command": true }
          }
        }
        """#
        let buttons = try JSONDecoder().decode(
            Scheme.Buttons.self,
            from: XCTUnwrap(json.data(using: .utf8))
        )

        XCTAssertNotNil(buttons.mappings?.first?.trigger)
        XCTAssertEqual(buttons.autoScroll.trigger?.button, .mouse(2))
        XCTAssertNil(buttons.autoScroll.trigger?.trigger)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(buttons)) as? [String: Any]
        )
        let autoScroll = try XCTUnwrap(object["autoScroll"] as? [String: Any])
        let autoScrollTrigger = try XCTUnwrap(autoScroll["trigger"] as? [String: Any])
        XCTAssertEqual(autoScrollTrigger["button"] as? Int, 2)
        XCTAssertNil(autoScrollTrigger["trigger"])
    }

    func testStructuredButtonMappingRoundTrips() throws {
        let mapping = Mapping(
            trigger: .init(
                input: .button(.mouse(4)),
                simultaneous: [.mouse(5)],
                modifiers: [.command, .shift]
            ),
            outcomes: .init(
                shortPress: .arg0(.missionControl),
                longPress: .arg0(.launchpad),
                swipe: .init(left: .arg0(.missionControlSpaceLeft), right: .arg0(.missionControlSpaceRight))
            )
        )

        let decoded = try JSONDecoder().decode(Mapping.self, from: JSONEncoder().encode(mapping))

        XCTAssertEqual(decoded, mapping)
        XCTAssertTrue(decoded.valid)
        XCTAssertNil(decoded.button)
        XCTAssertNil(decoded.scroll)
    }

    func testPressOutcomeRoundTrips() throws {
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4)), modifiers: [.option]),
            outcomes: .init(press: .init(action: .arg1(.keyPress([.a])), behavior: .hold))
        )

        let data = try JSONEncoder().encode(mapping)
        let decoded = try JSONDecoder().decode(Mapping.self, from: data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let outcomes = try XCTUnwrap(object["outcomes"] as? [String: Any])
        let press = try XCTUnwrap(outcomes["press"] as? [String: Any])

        XCTAssertEqual(decoded, mapping)
        XCTAssertEqual(press["behavior"] as? String, "hold")
        XCTAssertNotNil(press["action"])
    }

    func testStructuredWheelWithHeldButtonRoundTrips() throws {
        let mapping = Mapping(
            trigger: .init(input: .wheel(.left), whileHeld: [.mouse(4)]),
            action: .arg0(.showDesktop)
        )

        let data = try JSONEncoder().encode(mapping)
        let decoded = try JSONDecoder().decode(Mapping.self, from: data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let trigger = try XCTUnwrap(object["trigger"] as? [String: Any])
        let input = try XCTUnwrap(trigger["input"] as? [String: Any])

        XCTAssertEqual(input["wheel"] as? String, "left")
        XCTAssertEqual(trigger["whileHeld"] as? [Int], [4])
        XCTAssertEqual(decoded, mapping)
        XCTAssertTrue(decoded.valid)
    }

    func testWheelRejectsLongPressAndSwipeOutcomes() {
        let shortPress = Mapping(
            trigger: .init(input: .wheel(.up)),
            outcomes: .init(shortPress: .arg0(.missionControl)),
            action: .arg0(.none)
        )
        let longPress = Mapping(
            trigger: .init(input: .wheel(.up)),
            outcomes: .init(longPress: .arg0(.missionControl)),
            action: .arg0(.none)
        )
        let swipe = Mapping(
            trigger: .init(input: .wheel(.up)),
            outcomes: .init(swipe: .init(up: .arg0(.missionControl))),
            action: .arg0(.none)
        )

        XCTAssertFalse(shortPress.valid)
        XCTAssertFalse(longPress.valid)
        XCTAssertFalse(swipe.valid)
    }

    func testStructuredMappingsRequireAnOutcomeOrAction() {
        let button = Mapping(trigger: .init(input: .button(.mouse(4))))
        let wheel = Mapping(trigger: .init(input: .wheel(.up)))

        XCTAssertFalse(button.valid)
        XCTAssertFalse(wheel.valid)
    }

    func testTriggerInputRejectsButtonAndWheelTogether() throws {
        let json = #"""
        {
          "trigger": { "input": { "button": 4, "wheel": "up" } },
          "outcomes": { "shortPress": "none" }
        }
        """#

        XCTAssertThrowsError(try JSONDecoder().decode(
            Mapping.self,
            from: XCTUnwrap(json.data(using: .utf8))
        ))
    }

    func testWheelRejectsSimultaneousButtonsButAllowsHeldButtons() {
        let simultaneous = Mapping(
            trigger: .init(input: .wheel(.up), simultaneous: [.mouse(4)]),
            action: .arg0(.none)
        )
        let held = Mapping(
            trigger: .init(input: .wheel(.up), whileHeld: [.mouse(4)]),
            action: .arg0(.none)
        )

        XCTAssertFalse(simultaneous.valid)
        XCTAssertTrue(held.valid)
    }

    func testButtonCannotAlsoRequireItselfToBeHeld() {
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4)), whileHeld: [.mouse(4)]),
            outcomes: .init(shortPress: .arg0(.none))
        )

        XCTAssertFalse(mapping.valid)
    }

    func testPressOutcomeCannotCompeteWithDeferredOutcomes() {
        let mapping = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(
                press: .init(action: .arg0(.missionControl), behavior: .repeat),
                longPress: .arg0(.launchpad)
            )
        )

        XCTAssertFalse(mapping.valid)
    }

    func testHoldAndRemapBehaviorsValidateTheirActionKinds() {
        let invalidHold = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(press: .init(action: .arg0(.missionControl), behavior: .hold))
        )
        let invalidRemap = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(press: .init(action: .arg0(.missionControl), behavior: .remap))
        )

        XCTAssertFalse(invalidHold.valid)
        XCTAssertFalse(invalidRemap.valid)
    }

    func testStandaloneUnmodifiedPrimaryButtonOnlyAllowsLongPress() {
        let shortPressPrimary = Mapping(
            trigger: .init(input: .button(.mouse(0))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let longPressPrimary = Mapping(
            trigger: .init(input: .button(.mouse(0))),
            outcomes: .init(longPress: .arg0(.none))
        )
        let combinedPrimary = Mapping(
            trigger: .init(input: .button(.mouse(0))),
            outcomes: .init(shortPress: .arg0(.none), longPress: .arg0(.none))
        )
        let modifiedPrimary = Mapping(
            trigger: .init(input: .button(.mouse(0)), modifiers: [.control]),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let chordedPrimary = Mapping(
            trigger: .init(input: .button(.mouse(0)), simultaneous: [.mouse(1)]),
            outcomes: .init(shortPress: .arg0(.none))
        )

        XCTAssertFalse(shortPressPrimary.valid)
        XCTAssertTrue(longPressPrimary.valid)
        XCTAssertFalse(combinedPrimary.valid)
        XCTAssertTrue(modifiedPrimary.valid)
        XCTAssertTrue(chordedPrimary.valid)
    }

    func testButtonUsageRiskClassifiesActualCaptureRoles() {
        let standaloneLongPress = Mapping(
            trigger: .init(input: .button(.mouse(0))),
            outcomes: .init(longPress: .arg0(.none))
        )
        let chord = Mapping(
            trigger: .init(input: .button(.mouse(1)), simultaneous: [.mouse(0)]),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let heldPrefix = Mapping(
            trigger: .init(input: .button(.mouse(4)), whileHeld: [.mouse(0)]),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let heldWheel = Mapping(
            trigger: .init(input: .wheel(.up), whileHeld: [.mouse(0)]),
            action: .arg0(.none)
        )

        XCTAssertEqual(
            standaloneLongPress.buttonUsageRisk,
            .singleButtonLongPress(button: .mouse(0))
        )
        XCTAssertEqual(
            chord.buttonUsageRisk,
            .simultaneousPrimaryChord(recommendedHeldButton: .mouse(1))
        )
        XCTAssertEqual(heldPrefix.buttonUsageRisk, .primaryHeldPrefix)
        XCTAssertEqual(heldWheel.buttonUsageRisk, .primaryHeldPrefix)
    }

    func testButtonUsageRiskIgnoresSafeOrderedPrimaryInputAndModifiedChords() {
        let orderedPrimaryInput = Mapping(
            trigger: .init(input: .button(.mouse(0)), whileHeld: [.mouse(4)]),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let prefixedChord = Mapping(
            trigger: .init(
                input: .button(.mouse(0)),
                simultaneous: [.mouse(1)],
                whileHeld: [.mouse(4)]
            ),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let modifiedChord = Mapping(
            trigger: .init(
                input: .button(.mouse(1)),
                simultaneous: [.mouse(0)],
                modifiers: [.command]
            ),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let unrelated = Mapping(
            trigger: .init(input: .button(.mouse(4)), simultaneous: [.mouse(5)]),
            outcomes: .init(shortPress: .arg0(.none))
        )

        XCTAssertNil(orderedPrimaryInput.buttonUsageRisk)
        XCTAssertNil(prefixedChord.buttonUsageRisk)
        XCTAssertNil(modifiedChord.buttonUsageRisk)
        XCTAssertNil(unrelated.buttonUsageRisk)
    }

    func testButtonUsageRiskIncludesLongPressForSecondaryAndOtherButtons() {
        let secondaryLongPress = Mapping(
            trigger: .init(input: .button(.mouse(1))),
            outcomes: .init(longPress: .arg0(.none))
        )
        let modifiedOtherButtonWithShortPress = Mapping(
            trigger: .init(input: .button(.mouse(4)), modifiers: [.command]),
            outcomes: .init(shortPress: .arg0(.none), longPress: .arg0(.none))
        )
        let otherButtonShortPressOnly = Mapping(
            trigger: .init(input: .button(.mouse(5))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let logitechLongPress = Mapping(
            trigger: .init(input: .button(.logitechControl(.init(controlID: 0xC4)))),
            outcomes: .init(longPress: .arg0(.none))
        )

        XCTAssertTrue(secondaryLongPress.valid)
        XCTAssertTrue(modifiedOtherButtonWithShortPress.valid)
        XCTAssertEqual(
            secondaryLongPress.buttonUsageRisk,
            .singleButtonLongPress(button: .mouse(1))
        )
        XCTAssertEqual(
            modifiedOtherButtonWithShortPress.buttonUsageRisk,
            .singleButtonLongPress(button: .mouse(4))
        )
        XCTAssertNil(otherButtonShortPressOnly.buttonUsageRisk)
        XCTAssertEqual(
            logitechLongPress.buttonUsageRisk,
            .singleButtonLongPress(button: .logitechControl(.init(controlID: 0xC4)))
        )
    }

    func testPrimaryChordRecommendationIsIndependentOfInputOrder() {
        let primaryFirst = Mapping(
            trigger: .init(input: .button(.mouse(0)), simultaneous: [.mouse(4)]),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let primarySecond = Mapping(
            trigger: .init(input: .button(.mouse(4)), simultaneous: [.mouse(0)]),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let multiButtonChord = Mapping(
            trigger: .init(input: .button(.mouse(0)), simultaneous: [.mouse(1), .mouse(4)]),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let ordered = Mapping(
            trigger: .init(input: .button(.mouse(0)), whileHeld: [.mouse(4)]),
            outcomes: .init(shortPress: .arg0(.none))
        )

        XCTAssertEqual(
            primaryFirst.buttonUsageRisk,
            .simultaneousPrimaryChord(recommendedHeldButton: .mouse(4))
        )
        XCTAssertEqual(
            primarySecond.buttonUsageRisk,
            .simultaneousPrimaryChord(recommendedHeldButton: .mouse(4))
        )
        XCTAssertEqual(
            multiButtonChord.buttonUsageRisk,
            .simultaneousPrimaryChord(recommendedHeldButton: nil)
        )
        XCTAssertNil(ordered.buttonUsageRisk)
    }

    func testPrimarySecondaryChordCanBeConvertedToSafeOrderedTrigger() throws {
        var chord = Mapping(
            trigger: .init(input: .button(.mouse(1)), simultaneous: [.mouse(0)]),
            outcomes: .init(shortPress: .arg0(.none))
        )
        chord.trigger?.setTwoButtonRelationship(.holdThenPress, preferredHeldButton: .mouse(1))

        let trigger = try XCTUnwrap(chord.trigger)
        XCTAssertEqual(trigger.input, .button(.mouse(0)))
        XCTAssertEqual(trigger.whileHeld, [.mouse(1)])
        XCTAssertNil(trigger.simultaneous)
        XCTAssertNil(chord.buttonUsageRisk)
    }

    func testTwoButtonRelationshipCanSwitchWithoutChangingModifiersOrOutcomes() {
        let outcomes = Mapping.Outcomes(shortPress: .arg0(.missionControl))
        var trigger = Mapping.Trigger(
            input: .button(.mouse(4)),
            simultaneous: [.mouse(5)],
            modifiers: [.command]
        )

        XCTAssertEqual(trigger.twoButtonRelationship?.kind, .simultaneous)
        XCTAssertEqual(trigger.twoButtonRelationship?.first, .mouse(4))
        XCTAssertEqual(trigger.twoButtonRelationship?.second, .mouse(5))

        trigger.setTwoButtonRelationship(.holdThenPress)
        let ordered = Mapping(trigger: trigger, outcomes: outcomes)

        XCTAssertEqual(ordered.trigger?.input, .button(.mouse(5)))
        XCTAssertEqual(ordered.trigger?.whileHeld, [.mouse(4)])
        XCTAssertNil(ordered.trigger?.simultaneous)
        XCTAssertEqual(ordered.trigger?.modifiers, [.command])
        XCTAssertEqual(ordered.outcomes, outcomes)

        trigger.setTwoButtonRelationship(.simultaneous)
        let chord = Mapping(trigger: trigger, outcomes: outcomes)

        XCTAssertEqual(chord.trigger?.input, .button(.mouse(4)))
        XCTAssertEqual(chord.trigger?.simultaneous, [.mouse(5)])
        XCTAssertNil(chord.trigger?.whileHeld)
        XCTAssertEqual(chord.trigger?.modifiers, [.command])
        XCTAssertEqual(chord.outcomes, outcomes)
    }

    func testTwoButtonRelationshipDoesNotFlattenMixedOrLargerTriggers() {
        let mixed = Mapping.Trigger(
            input: .button(.mouse(5)),
            simultaneous: [.mouse(6)],
            whileHeld: [.mouse(4)]
        )
        let largerChord = Mapping.Trigger(
            input: .button(.mouse(4)),
            simultaneous: [.mouse(5), .mouse(6)]
        )
        let heldWheel = Mapping.Trigger(
            input: .wheel(.up),
            whileHeld: [.mouse(4)]
        )

        XCTAssertNil(mixed.twoButtonRelationship)
        XCTAssertNil(largerChord.twoButtonRelationship)
        XCTAssertNil(heldWheel.twoButtonRelationship)
    }

    func testTwoButtonRelationshipCanPreferWhichButtonIsHeld() {
        var trigger = Mapping.Trigger(
            input: .button(.mouse(0)),
            simultaneous: [.mouse(1)]
        )

        trigger.setTwoButtonRelationship(
            .holdThenPress,
            preferredHeldButton: .mouse(1)
        )

        XCTAssertEqual(trigger.input, .button(.mouse(0)))
        XCTAssertEqual(trigger.whileHeld, [.mouse(1)])
        XCTAssertNil(trigger.simultaneous)
    }

    func testCanonicalTriggerRemovesDuplicatesAndIgnoresOrderForConflicts() {
        let first = Mapping(
            trigger: .init(
                input: .button(.mouse(4)),
                simultaneous: [.mouse(5), .mouse(5)],
                modifiers: [.shift, .command]
            ),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let second = Mapping(
            trigger: .init(
                input: .button(.mouse(4)),
                simultaneous: [.mouse(5)],
                modifiers: [.command, .shift]
            ),
            outcomes: .init(shortPress: .arg0(.none))
        )

        XCTAssertTrue(first.conflicted(with: second))
    }

    func testLegacyMappingNormalizesOnlyWhenRequested() {
        var mapping = Mapping(button: .mouse(4), command: true, action: .arg0(.missionControl))

        mapping.normalizeAsStructured()

        XCTAssertEqual(mapping.trigger, .init(input: .button(.mouse(4)), modifiers: [.command]))
        XCTAssertEqual(mapping.outcomes?.shortPress, .arg0(.missionControl))
        XCTAssertNil(mapping.button)
        XCTAssertNil(mapping.command)
        XCTAssertNil(mapping.action)
    }

    func testDifferentOutcomesOnSameTriggerDoNotConflict() {
        let shortPress = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(shortPress: .arg0(.missionControl))
        )
        let longPress = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(longPress: .arg0(.launchpad))
        )

        XCTAssertFalse(shortPress.conflicted(with: longPress))
        XCTAssertTrue(shortPress.conflicted(with: shortPress))
    }

    func testPressOutcomeConflictsWithEveryOutcomeOnSameTrigger() {
        let press = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(press: .init(action: .arg0(.missionControl), behavior: .repeat))
        )
        let longPress = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(longPress: .arg0(.launchpad))
        )

        XCTAssertTrue(press.conflicted(with: longPress))
        XCTAssertTrue(longPress.conflicted(with: press))
    }

    func testLaterIncompatiblePressOrDeferredMappingReplacesEarlierOutcomes() {
        var mapping = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(press: .init(action: .arg0(.missionControl), behavior: .repeat))
        )
        let longPress = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(longPress: .arg0(.launchpad))
        )

        mapping.mergeOutcomes(from: longPress)

        XCTAssertNil(mapping.outcomes?.press)
        XCTAssertEqual(mapping.outcomes?.longPress, .arg0(.launchpad))
    }

    func testChordIdentityIsIndependentOfPrimaryButtonEncoding() {
        let first = Mapping(
            trigger: .init(input: .button(.mouse(4)), simultaneous: [.mouse(5)]),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let reversed = Mapping(
            trigger: .init(input: .button(.mouse(5)), simultaneous: [.mouse(4)]),
            outcomes: .init(shortPress: .arg0(.none))
        )

        XCTAssertTrue(first.conflicted(with: reversed))
    }

    func testStructuredMappingsSortByTheirTriggerInput() {
        let buttonFive = Mapping(
            trigger: .init(input: .button(.mouse(5))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let buttonFour = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let wheel = Mapping(
            trigger: .init(input: .wheel(.up)),
            action: .arg0(.none)
        )

        XCTAssertEqual([wheel, buttonFive, buttonFour].sorted(), [buttonFour, buttonFive, wheel])
    }

    func testMergingStructuredOutcomePreservesExistingBranches() {
        var mapping = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(shortPress: .arg0(.missionControl))
        )
        let addition = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(
                longPress: .arg0(.launchpad),
                swipe: .init(left: .arg0(.missionControlSpaceLeft))
            )
        )

        mapping.mergeOutcomes(from: addition)

        XCTAssertEqual(mapping.outcomes?.shortPress, .arg0(.missionControl))
        XCTAssertEqual(mapping.outcomes?.longPress, .arg0(.launchpad))
        XCTAssertEqual(mapping.outcomes?.swipe?.left, .arg0(.missionControlSpaceLeft))
    }

    func testLegacyShortPressCanMergeWithNewLongPress() {
        var legacy = Mapping(button: .mouse(4), action: .arg0(.missionControl))
        let longPress = Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(longPress: .arg0(.launchpad))
        )

        XCTAssertFalse(legacy.conflicted(with: longPress))
        legacy.normalizeAsStructured()
        legacy.mergeOutcomes(from: longPress)

        XCTAssertEqual(legacy.outcomes?.shortPress, .arg0(.missionControl))
        XCTAssertEqual(legacy.outcomes?.longPress, .arg0(.launchpad))
    }

    private func decodeLegacyMapping(_ mappingJSON: String) throws -> Mapping {
        let json = #"{"mappings":["# + mappingJSON + "]}"
        let buttons = try JSONDecoder().decode(
            Scheme.Buttons.self,
            from: XCTUnwrap(json.data(using: .utf8))
        )
        return try XCTUnwrap(buttons.mappings?.first)
    }
}
