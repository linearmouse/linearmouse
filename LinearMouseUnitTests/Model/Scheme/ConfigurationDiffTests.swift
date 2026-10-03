// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ConfigurationDiffTests: XCTestCase {
    private func diff(_ old: Scheme, _ new: Scheme) -> ConfigurationDiff {
        .init(previous: .init(schemes: [old]), current: .init(schemes: [new]))
    }

    func testFirstConfigurationInitializesBothConsumers() {
        let diff = ConfigurationDiff(previous: nil, current: .init())
        XCTAssertTrue(diff.affectsEventTransformers)
        XCTAssertTrue(diff.affectsFocusFollowsMouse)
    }

    func testDeviceSettingsDoNotInvalidateEventOrFocusState() {
        var scheme = Scheme()
        scheme.pointer.speed = .value(0.5)
        scheme.pointer.acceleration = .value(1)
        scheme.pointer.disableAcceleration = true
        scheme.pointer.hardwareDPI = 1200
        scheme.logitech.highResolutionWheel = true
        XCTAssertFalse(diff(Scheme(), scheme).affectsEventTransformers)
        XCTAssertFalse(diff(Scheme(), scheme).affectsFocusFollowsMouse)
    }

    func testScrollingAndButtonsOnlyInvalidateEventTransformers() {
        var scheme = Scheme()
        scheme.scrolling.reverse.vertical = true
        XCTAssertTrue(diff(Scheme(), scheme).affectsEventTransformers)
        XCTAssertFalse(diff(Scheme(), scheme).affectsFocusFollowsMouse)
        scheme = Scheme()
        scheme.buttons.switchPrimaryButtonAndSecondaryButtons = true
        XCTAssertTrue(diff(Scheme(), scheme).affectsEventTransformers)
        XCTAssertFalse(diff(Scheme(), scheme).affectsFocusFollowsMouse)
    }

    func testFocusAndRedirectDependencies() {
        var scheme = Scheme()
        scheme.pointer.focusFollowsMouse = true
        XCTAssertFalse(diff(Scheme(), scheme).affectsEventTransformers)
        XCTAssertTrue(diff(Scheme(), scheme).affectsFocusFollowsMouse)
        scheme.pointer.redirectsToScroll = true
        XCTAssertTrue(diff(Scheme(), scheme).affectsEventTransformers)
        XCTAssertTrue(diff(Scheme(), scheme).affectsFocusFollowsMouse)
    }

    func testExplicitFalseOverrideMustNotBeNormalizedAwayBeforeMerging() {
        var scheme = Scheme()
        scheme.pointer.redirectsToScroll = false
        XCTAssertTrue(diff(Scheme(), scheme).affectsEventTransformers)
        XCTAssertTrue(diff(Scheme(), scheme).affectsFocusFollowsMouse)
    }

    func testMatchingConditionsAndSchemeRemovalInvalidateConsumers() {
        var scheme = Scheme()
        scheme.pointer.redirectsToScroll = true
        scheme.if = [.init(display: "External")]
        XCTAssertTrue(diff(Scheme(), scheme).affectsEventTransformers)
        XCTAssertTrue(diff(Scheme(), scheme).affectsFocusFollowsMouse)
        let removed = ConfigurationDiff(previous: .init(schemes: [scheme]), current: .init())
        XCTAssertTrue(removed.affectsEventTransformers)
        XCTAssertTrue(removed.affectsFocusFollowsMouse)
    }

    func testUnrelatedRulesCanBeAddedRemovedAndReordered() {
        var relevant = Scheme()
        relevant.pointer.redirectsToScroll = true
        var hardware = Scheme()
        hardware.if = [.init(display: "External")]
        hardware.pointer.hardwareDPI = 1200
        let original = Configuration(schemes: [relevant])
        let expanded = Configuration(schemes: [hardware, relevant])
        let reordered = Configuration(schemes: [relevant, hardware])
        for (old, new) in [(original, expanded), (expanded, reordered), (reordered, original)] {
            let diff = ConfigurationDiff(previous: old, current: new)
            XCTAssertFalse(diff.affectsEventTransformers)
            XCTAssertFalse(diff.affectsFocusFollowsMouse)
        }
    }

    func testRelevantOverrideOrderAndConditionsArePreserved() {
        var enabled = Scheme()
        enabled.pointer.redirectsToScroll = true
        var disabled = Scheme()
        disabled.pointer.redirectsToScroll = false
        let previous = Configuration(schemes: [enabled, disabled])
        let reordered = ConfigurationDiff(previous: previous, current: .init(schemes: [disabled, enabled]))
        XCTAssertTrue(reordered.affectsEventTransformers)
        XCTAssertTrue(reordered.affectsFocusFollowsMouse)
        disabled.if = [.init(display: "External")]
        let conditional = ConfigurationDiff(previous: previous, current: .init(schemes: [enabled, disabled]))
        XCTAssertTrue(conditional.affectsEventTransformers)
        XCTAssertTrue(conditional.affectsFocusFollowsMouse)
    }
}
