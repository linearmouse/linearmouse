// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class PointerMotionRequirementsTests: XCTestCase {
    func testScrollAndPointerSpeedOnlyDoNotSubscribeToMotion() {
        var scheme = Scheme()
        scheme.scrolling.reverse.vertical = true
        scheme.buttons.clickDebouncing.timeout = 25
        scheme.buttons.clickDebouncing.mode = .libinput
        scheme.pointer.disableAcceleration = true
        XCTAssertTrue(PointerMotionRequirements(configuration: .init(schemes: [scheme])).isEmpty)
    }

    func testHeldFeaturesDoNotSubscribeBeforeTheirTrigger() {
        var autoScroll = Scheme()
        autoScroll.buttons.autoScroll.enabled = true
        var gesture = Scheme()
        gesture.buttons.gesture.enabled = true
        var redirect = Scheme()
        redirect.pointer.redirectsToScroll = true
        redirect.pointer.redirectsToScrollTrigger = .init(input: .button(.mouse(1)))
        var mapping = Scheme()
        mapping.buttons.mappings = [
            .init(trigger: .init(input: .button(.mouse(4))), outcomes: .init(shortPress: .arg0(.none)))
        ]
        for scheme in [autoScroll, gesture, redirect, mapping] {
            let requirements = PointerMotionRequirements(configuration: .init(schemes: [scheme]))
            XCTAssertTrue(requirements.isEmpty)
            for type: CGEventType in [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged] {
                XCTAssertFalse(requirements.contains(eventType: type))
            }
            XCTAssertFalse(requirements.contains(eventType: .leftMouseDown))
        }
    }

    func testInheritedAndOtherApplicationFeaturesAreConservativelyIncluded() {
        var enabled = Scheme()
        enabled.pointer.redirectsToScroll = true
        var trigger = Scheme()
        trigger.pointer.redirectsToScrollTrigger = .init(input: .button(.mouse(4)))
        var disabled = Scheme()
        disabled.pointer.redirectsToScroll = false
        XCTAssertEqual(
            PointerMotionRequirements(configuration: .init(schemes: [enabled, trigger, disabled])),
            .all
        )
    }

    func testSwapOnlyNeedsDragAndDisabledFeaturesNeedNeitherCategory() {
        var scheme = Scheme()
        scheme.buttons.autoScroll.enabled = false
        scheme.buttons.gesture.enabled = false
        scheme.pointer.redirectsToScroll = false
        scheme.buttons.mappings = []
        XCTAssertTrue(PointerMotionRequirements(configuration: .init(schemes: [scheme])).isEmpty)
        scheme.buttons.switchPrimaryButtonAndSecondaryButtons = true
        let requirements = PointerMotionRequirements(configuration: .init(schemes: [scheme]))
        XCTAssertEqual(requirements, .dragged)
        XCTAssertFalse(requirements.contains(eventType: .mouseMoved))
    }
}
