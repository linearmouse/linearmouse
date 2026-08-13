// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
@testable import LinearMouse
import XCTest

final class EventTransformerManagerTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        ConfigurationState.shared.configuration = .init()
        SettingsState.shared.endButtonMappingRecording()
        SettingsState.shared.recordedButtonMappingEvent = nil
    }

    func testCacheKeyIsConfigurationScoped() {
        let matcher = DeviceMatcher(category: .mouse)
        let firstKey = EventTransformerManager.CacheKey(
            deviceMatcher: matcher,
            process: nil,
            screen: nil
        )
        let secondKey = EventTransformerManager.CacheKey(
            deviceMatcher: matcher,
            process: nil,
            screen: nil
        )

        XCTAssertEqual(firstKey, secondKey)
    }

    func testCacheKeySeparatesRuntimeDevicesWithTheSameMatcher() {
        let matcher = DeviceMatcher(category: .mouse)
        let firstKey = EventTransformerManager.CacheKey(
            deviceID: 1,
            deviceMatcher: matcher,
            process: nil,
            screen: nil
        )
        let secondKey = EventTransformerManager.CacheKey(
            deviceID: 2,
            deviceMatcher: matcher,
            process: nil,
            screen: nil
        )

        XCTAssertNotEqual(firstKey, secondKey)
    }

    func testClickDebouncingWithoutModeUsesLegacyTransformer() throws {
        var scheme = Scheme()
        scheme.buttons.clickDebouncing.timeout = 50
        scheme.buttons.clickDebouncing.buttons = [.left]
        ConfigurationState.shared.configuration = .init(schemes: [scheme])

        let transformers = try XCTUnwrap(EventTransformerManager.shared.get(
            withDevice: nil,
            withPid: nil,
            withDisplay: nil
        ) as? [EventTransformer])

        XCTAssertEqual(transformers.compactMap { $0 as? ClickDebouncingTransformer }.count, 1)
        XCTAssertTrue(transformers.compactMap { $0 as? LibinputClickDebouncingTransformer }.isEmpty)
    }

    func testLibinputClickDebouncingModeUsesBetaTransformer() throws {
        var scheme = Scheme()
        scheme.buttons.clickDebouncing.mode = .libinput
        scheme.buttons.clickDebouncing.timeout = 25
        scheme.buttons.clickDebouncing.buttons = [.left]
        ConfigurationState.shared.configuration = .init(schemes: [scheme])

        let transformers = try XCTUnwrap(EventTransformerManager.shared.get(
            withDevice: nil,
            withPid: nil,
            withDisplay: nil
        ) as? [EventTransformer])

        XCTAssertTrue(transformers.compactMap { $0 as? ClickDebouncingTransformer }.isEmpty)
        XCTAssertEqual(
            transformers.compactMap { $0 as? LibinputClickDebouncingTransformer }.count,
            Scheme.Buttons.ClickDebouncing.standardButtons.count
        )
    }

    func testAutoScrollKeepsPriorityWhenButtonMappingsArePresent() throws {
        var scheme = Scheme()
        scheme.buttons.autoScroll.enabled = true
        scheme.buttons.autoScroll.modes = [.hold]
        var autoScrollTrigger = Scheme.Buttons.Mapping()
        autoScrollTrigger.button = .mouse(2)
        scheme.buttons.autoScroll.trigger = autoScrollTrigger

        var gesture = Scheme.Buttons.Gesture()
        gesture.enabled = true
        gesture.trigger = .init(button: .mouse(2))
        gesture.actions = .init(right: .some(.none))
        scheme.buttons.gesture = gesture
        scheme.buttons.mappings = [
            .init(
                trigger: .init(input: .button(.mouse(4))),
                outcomes: .init(shortPress: .arg0(.none))
            )
        ]
        ConfigurationState.shared.configuration = .init(schemes: [scheme])

        let transformers = try XCTUnwrap(EventTransformerManager().get(
            withDevice: nil,
            withPid: nil,
            withDisplay: nil
        ) as? [EventTransformer])
        let autoScrollIndex = try XCTUnwrap(transformers.firstIndex { $0 is AutoScrollTransformer })
        let buttonMappingIndex = try XCTUnwrap(transformers.firstIndex { $0 is ButtonMappingTransformer })

        XCTAssertLessThan(autoScrollIndex, buttonMappingIndex)
    }

    func testAutoScrollPrecedesGestureWithoutButtonMappings() throws {
        var scheme = Scheme()
        scheme.buttons.autoScroll.enabled = true
        var autoScrollTrigger = Scheme.Buttons.Mapping()
        autoScrollTrigger.button = .mouse(2)
        scheme.buttons.autoScroll.trigger = autoScrollTrigger

        var gesture = Scheme.Buttons.Gesture()
        gesture.enabled = true
        gesture.trigger = .init(button: .mouse(2))
        gesture.actions = .init(right: .some(.none))
        scheme.buttons.gesture = gesture
        ConfigurationState.shared.configuration = .init(schemes: [scheme])

        let transformers = try XCTUnwrap(EventTransformerManager().get(
            withDevice: nil,
            withPid: nil,
            withDisplay: nil
        ) as? [EventTransformer])
        let autoScrollIndex = try XCTUnwrap(transformers.firstIndex { $0 is AutoScrollTransformer })
        let gestureIndex = try XCTUnwrap(transformers.firstIndex { $0 is GestureButtonTransformer })

        XCTAssertLessThan(autoScrollIndex, gestureIndex)
    }

    func testStandaloneGestureDoesNotInterceptButtonMappingRecording() throws {
        var gesture = Scheme.Buttons.Gesture()
        gesture.enabled = true
        gesture.trigger = .init(button: .mouse(4))
        gesture.threshold = 10
        gesture.actions = .init(right: .some(.none))
        var scheme = Scheme()
        scheme.buttons.gesture = gesture
        ConfigurationState.shared.configuration = .init(schemes: [scheme])
        SettingsState.shared.beginButtonMappingRecording(sessionID: UUID())

        let transformer = EventTransformerManager().get(
            withDevice: nil,
            withPid: nil,
            withDisplay: nil
        )
        let button = try XCTUnwrap(CGMouseButton(rawValue: 4))
        let down = try mouseEvent(type: .otherMouseDown, button: button)
        let dragged = try mouseEvent(type: .otherMouseDragged, button: button)
        dragged.setDoubleValueField(.mouseEventDeltaX, value: 10)

        XCTAssertNotNil(transformer.transform(down, in: .init(device: nil)))
        XCTAssertNotNil(transformer.transform(dragged, in: .init(device: nil)))
    }

    func testTransformerCacheDoesNotReuseValueForNewProcess() throws {
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(scrolling: .init(reverse: .init(vertical: true)))
        ])
        let firstProcess = ProcessIdentity(pid: 42, startTimeSeconds: 100, startTimeMicroseconds: 1)
        let secondProcess = ProcessIdentity(pid: 42, startTimeSeconds: 200, startTimeMicroseconds: 2)
        let firstTransformer = EventTransformerManager.shared.get(
            withDevice: nil,
            withProcess: firstProcess,
            withDisplay: nil
        )
        let cachedFirstTransformer = EventTransformerManager.shared.get(
            withDevice: nil,
            withProcess: firstProcess,
            withDisplay: nil
        )
        let secondTransformer = EventTransformerManager.shared.get(
            withDevice: nil,
            withProcess: secondProcess,
            withDisplay: nil
        )
        let firstReverseTransformer = try XCTUnwrap((firstTransformer as? [EventTransformer])?
            .compactMap { $0 as? ReverseScrollingTransformer }
            .first)
        let cachedFirstReverseTransformer = try XCTUnwrap((cachedFirstTransformer as? [EventTransformer])?
            .compactMap { $0 as? ReverseScrollingTransformer }
            .first)
        let secondReverseTransformer = try XCTUnwrap((secondTransformer as? [EventTransformer])?
            .compactMap { $0 as? ReverseScrollingTransformer }
            .first)

        XCTAssertIdentical(firstReverseTransformer, cachedFirstReverseTransformer)
        XCTAssertNotIdentical(firstReverseTransformer, secondReverseTransformer)
    }

    func testButtonMappingTransformerRemainsUntilEveryMouseButtonIsReleased() throws {
        let orderedMapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(1)), whileHeld: [.mouse(0)]),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(mappings: [orderedMapping]))
        ])
        let manager = EventTransformerManager()

        let initialResolution = try manager.resolve(
            withCGEvent: mouseEvent(type: .leftMouseDown, button: .left),
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display A"
        )
        let initialDown = try mouseEvent(type: .leftMouseDown, button: .left)
        _ = initialResolution.transform(initialDown) { _ in }

        let secondDown = try mouseEvent(type: .rightMouseDown, button: .right)
        let secondButtonResolution = manager.resolve(
            withCGEvent: secondDown,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        _ = secondButtonResolution.transform(secondDown) { _ in }
        let initialTransformer = try buttonMappingTransformer(in: initialResolution)
        XCTAssertTrue(initialTransformer.hasActiveInteraction)
        let wheelEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        let wheelResolution = manager.resolve(
            withCGEvent: wheelEvent,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        _ = wheelResolution.transform(wheelEvent) { _ in }

        let firstRelease = try mouseEvent(type: .leftMouseUp, button: .left)
        let firstReleaseResolution = manager.resolve(
            withCGEvent: firstRelease,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        _ = firstReleaseResolution.transform(firstRelease) { _ in }
        XCTAssertTrue(initialTransformer.hasActiveInteraction)

        let finalRelease = try mouseEvent(type: .rightMouseUp, button: .right)
        let finalReleaseResolution = manager.resolve(
            withCGEvent: finalRelease,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        _ = finalReleaseResolution.transform(finalRelease) { _ in }

        XCTAssertIdentical(try buttonMappingTransformer(in: secondButtonResolution), initialTransformer)
        XCTAssertIdentical(try buttonMappingTransformer(in: wheelResolution), initialTransformer)
        XCTAssertIdentical(try buttonMappingTransformer(in: firstReleaseResolution), initialTransformer)
        XCTAssertIdentical(try buttonMappingTransformer(in: finalReleaseResolution), initialTransformer)

        let nextStreamResolution = try manager.resolve(
            withCGEvent: mouseEvent(type: .leftMouseDown, button: .left),
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertNotIdentical(try buttonMappingTransformer(in: nextStreamResolution), initialTransformer)
    }

    func testOnlyActiveButtonTransformerDrainsAcrossSchemeBoundary() throws {
        let mapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(
                if: [.init(display: "Display A")],
                scrolling: .init(reverse: .init(vertical: true)),
                buttons: .init(mappings: [mapping])
            ),
            Scheme(
                if: [.init(display: "Display B")],
                scrolling: .init(reverse: .init(vertical: false))
            )
        ])
        let manager = EventTransformerManager()
        let button = try XCTUnwrap(CGMouseButton(rawValue: 4))

        let down = try mouseEvent(type: .otherMouseDown, button: button)
        let downResolution = manager.resolve(
            withCGEvent: down,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display A"
        )
        XCTAssertNil(downResolution.transform(down) { _ in })
        let owner = try buttonMappingTransformer(in: downResolution)
        XCTAssertTrue(owner.hasActiveInteraction)

        let wheel = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        let wheelResolution = manager.resolve(
            withCGEvent: wheel,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertIdentical(try buttonMappingTransformer(in: wheelResolution), owner)
        let transformedWheel = try XCTUnwrap(wheelResolution.transform(wheel) { _ in })
        XCTAssertEqual(ScrollWheelEventView(transformedWheel).deltaY, 1)
        XCTAssertTrue(owner.hasActiveInteraction)

        let release = try mouseEvent(type: .otherMouseUp, button: button)
        let releaseResolution = manager.resolve(
            withCGEvent: release,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertIdentical(try buttonMappingTransformer(in: releaseResolution), owner)
        XCTAssertNil(releaseResolution.transform(release) { _ in })
        XCTAssertFalse(owner.hasActiveInteraction)

        let nextWheel = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        let nextResolution = manager.resolve(
            withCGEvent: nextWheel,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertTrue((nextResolution.transformer as? [EventTransformer])?
            .compactMap { $0 as? ButtonMappingTransformer }
            .isEmpty == true)
    }

    func testOwnedReleaseUsesOriginalButtonSwapAcrossSchemeBoundary() throws {
        let mapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(1))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(
                if: [.init(display: "Display A")],
                buttons: .init(
                    mappings: [mapping],
                    switchPrimaryButtonAndSecondaryButtons: true
                )
            ),
            Scheme(
                if: [.init(display: "Display B")],
                buttons: .init(switchPrimaryButtonAndSecondaryButtons: false)
            )
        ])
        let manager = EventTransformerManager()

        let down = try mouseEvent(type: .leftMouseDown, button: .left)
        let downResolution = manager.resolve(
            withCGEvent: down,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display A"
        )
        XCTAssertNil(downResolution.transform(down) { _ in })
        let owner = try buttonMappingTransformer(in: downResolution)
        XCTAssertTrue(owner.hasActiveInteraction)

        let release = try mouseEvent(type: .leftMouseUp, button: .left)
        let releaseResolution = manager.resolve(
            withCGEvent: release,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )

        XCTAssertIdentical(try buttonMappingTransformer(in: releaseResolution), owner)
        XCTAssertNil(releaseResolution.transform(release) { _ in })
        XCTAssertFalse(owner.hasActiveInteraction)
    }

    func testPassThroughButtonPairStaysOnOriginalRouteWhileOwnerDrains() throws {
        let mapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(
                if: [.init(display: "Display A")],
                buttons: .init(
                    mappings: [mapping],
                    switchPrimaryButtonAndSecondaryButtons: true
                )
            ),
            Scheme(
                if: [.init(display: "Display B")],
                buttons: .init(switchPrimaryButtonAndSecondaryButtons: false)
            )
        ])
        let manager = EventTransformerManager()
        let mappedButton = try XCTUnwrap(CGMouseButton(rawValue: 4))

        let mappedDown = try mouseEvent(type: .otherMouseDown, button: mappedButton)
        let initialResolution = manager.resolve(
            withCGEvent: mappedDown,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display A"
        )
        XCTAssertNil(initialResolution.transform(mappedDown) { _ in })
        let owner = try buttonMappingTransformer(in: initialResolution)

        let passThroughDown = try mouseEvent(type: .leftMouseDown, button: .left)
        let passThroughDownResolution = manager.resolve(
            withCGEvent: passThroughDown,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        let transformedDown = try XCTUnwrap(passThroughDownResolution.transform(passThroughDown) { _ in })
        XCTAssertEqual(transformedDown.type, .rightMouseDown)
        XCTAssertEqual(MouseEventView(transformedDown).mouseButton, .right)

        let mappedUp = try mouseEvent(type: .otherMouseUp, button: mappedButton)
        let mappedUpResolution = manager.resolve(
            withCGEvent: mappedUp,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertNil(mappedUpResolution.transform(mappedUp) { _ in })
        XCTAssertFalse(owner.hasActiveInteraction)

        let passThroughUp = try mouseEvent(type: .leftMouseUp, button: .left)
        let passThroughUpResolution = manager.resolve(
            withCGEvent: passThroughUp,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertIdentical(try buttonMappingTransformer(in: passThroughUpResolution), owner)
        let transformedUp = try XCTUnwrap(passThroughUpResolution.transform(passThroughUp) { _ in })
        XCTAssertEqual(transformedUp.type, .rightMouseUp)
        XCTAssertEqual(MouseEventView(transformedUp).mouseButton, .right)

        let nextDown = try mouseEvent(type: .leftMouseDown, button: .left)
        let nextResolution = manager.resolve(
            withCGEvent: nextDown,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        let transformedNextDown = try XCTUnwrap(nextResolution.transform(nextDown) { _ in })
        XCTAssertEqual(transformedNextDown.type, .leftMouseDown)
        XCTAssertEqual(MouseEventView(transformedNextDown).mouseButton, .left)
    }

    func testPassThroughRoutePinDoesNotRestoreIdleMappingForWheelInput() throws {
        let buttonMapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let oldWheelMapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .wheel(.up)),
            action: .arg0(.none)
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(
                if: [.init(display: "Display A")],
                buttons: .init(
                    mappings: [buttonMapping, oldWheelMapping],
                    switchPrimaryButtonAndSecondaryButtons: true
                )
            ),
            Scheme(
                if: [.init(display: "Display B")],
                scrolling: .init(reverse: .init(vertical: true)),
                buttons: .init(switchPrimaryButtonAndSecondaryButtons: false)
            )
        ])
        let manager = EventTransformerManager()
        let mappedButton = try XCTUnwrap(CGMouseButton(rawValue: 4))

        let mappedDown = try mouseEvent(type: .otherMouseDown, button: mappedButton)
        let initialResolution = manager.resolve(
            withCGEvent: mappedDown,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display A"
        )
        XCTAssertNil(initialResolution.transform(mappedDown) { _ in })
        let owner = try buttonMappingTransformer(in: initialResolution)

        let passThroughDown = try mouseEvent(type: .leftMouseDown, button: .left)
        let passThroughDownResolution = manager.resolve(
            withCGEvent: passThroughDown,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertNotNil(passThroughDownResolution.transform(passThroughDown) { _ in })

        let mappedUp = try mouseEvent(type: .otherMouseUp, button: mappedButton)
        let mappedUpResolution = manager.resolve(
            withCGEvent: mappedUp,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertNil(mappedUpResolution.transform(mappedUp) { _ in })
        XCTAssertFalse(owner.hasActiveInteraction)

        let wheel = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        let wheelResolution = manager.resolve(
            withCGEvent: wheel,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        let transformedWheel = try XCTUnwrap(wheelResolution.transform(wheel) { _ in })
        XCTAssertEqual(ScrollWheelEventView(transformedWheel).deltaY, -1)

        let passThroughUp = try mouseEvent(type: .leftMouseUp, button: .left)
        let passThroughUpResolution = manager.resolve(
            withCGEvent: passThroughUp,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertNotNil(passThroughUpResolution.transform(passThroughUp) { _ in })
    }

    func testGestureAndButtonMappingShareRouteUntilRelease() throws {
        let mapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        var gesture = Scheme.Buttons.Gesture()
        gesture.enabled = true
        gesture.trigger = .init(button: .mouse(4))
        gesture.threshold = 1000
        gesture.actions = .init(right: .some(.none))
        var buttons = Scheme.Buttons()
        buttons.mappings = [mapping]
        buttons.gesture = gesture
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: buttons)
        ])
        let manager = EventTransformerManager()
        let button = try XCTUnwrap(CGMouseButton(rawValue: 4))
        XCTAssertFalse(SettingsState.shared.recording)

        let down = try mouseEvent(type: .otherMouseDown, button: button)
        let downResolution = manager.resolve(
            withCGEvent: down,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display A"
        )
        XCTAssertNil(downResolution.transform(down) { _ in })
        let initialTransformer = try buttonMappingTransformer(in: downResolution)
        XCTAssertEqual(initialTransformer.mappings, [mapping])
        XCTAssertTrue(initialTransformer.hasActiveInteraction)

        let drag = try mouseEvent(type: .otherMouseDragged, button: button)
        drag.setDoubleValueField(.mouseEventDeltaX, value: 10)
        let dragResolution = manager.resolve(
            withCGEvent: drag,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertIdentical(try buttonMappingTransformer(in: dragResolution), initialTransformer)
        XCTAssertNil(dragResolution.transform(drag) { _ in })

        let release = try mouseEvent(type: .otherMouseUp, button: button)
        let releaseResolution = manager.resolve(
            withCGEvent: release,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertIdentical(try buttonMappingTransformer(in: releaseResolution), initialTransformer)
        XCTAssertNil(releaseResolution.transform(release) { _ in })
        XCTAssertFalse(initialTransformer.hasActiveInteraction)
    }

    func testDraggedStreamWithoutObservedDownDoesNotCreateInteractionLease() throws {
        let mapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(0)), simultaneous: [.mouse(1)]),
            outcomes: .init(shortPress: .arg0(.showDesktop))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(mappings: [mapping]))
        ])
        let manager = EventTransformerManager()

        let dragResolution = try manager.resolve(
            withCGEvent: mouseEvent(type: .leftMouseDragged, button: .left),
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display A"
        )
        let releaseResolution = try manager.resolve(
            withCGEvent: mouseEvent(type: .leftMouseUp, button: .left),
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )

        XCTAssertNotIdentical(
            try buttonMappingTransformer(in: releaseResolution),
            try buttonMappingTransformer(in: dragResolution)
        )
    }

    func testChordFallbackReleaseKeepsDeferredDeliveryAcrossSchemeBoundary() throws {
        let mapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(0)), simultaneous: [.mouse(1)]),
            outcomes: .init(shortPress: .arg0(.showDesktop))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(mappings: [mapping]))
        ])
        let manager = EventTransformerManager()
        var deliveredEventTypes = [CGEventType]()
        let context = EventTransformerContext(device: nil) { deliveredEvent in
            deliveredEventTypes.append(deliveredEvent.type)
        }

        let down = try mouseEvent(type: .leftMouseDown, button: .left)
        let downResolution = manager.resolve(
            withCGEvent: down,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display A"
        )
        XCTAssertNil(try downResolution.transform(down, deferredEventSink: XCTUnwrap(context.deferredEventSink)))

        let drag = try mouseEvent(type: .leftMouseDragged, button: .left)
        drag.setDoubleValueField(.mouseEventDeltaX, value: 20)
        let dragResolution = manager.resolve(
            withCGEvent: drag,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertNil(try dragResolution.transform(drag, deferredEventSink: XCTUnwrap(context.deferredEventSink)))

        let release = try mouseEvent(type: .leftMouseUp, button: .left)
        let releaseResolution = manager.resolve(
            withCGEvent: release,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertNil(try releaseResolution.transform(release, deferredEventSink: XCTUnwrap(context.deferredEventSink)))
        XCTAssertEqual(deliveredEventTypes, [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
    }

    func testShottrSourceApplicationIsBypassed() {
        XCTAssertTrue(EventTransformerManager.shouldBypassSourceApplication("cc.ffitch.shottr"))
    }

    func testHomerowSourceApplicationIsBypassed() {
        XCTAssertTrue(EventTransformerManager.shouldBypassSourceApplication("com.superultra.Homerow"))
    }

    func testUnknownSourceApplicationIsNotBypassed() {
        XCTAssertFalse(EventTransformerManager.shouldBypassSourceApplication("com.example.Unknown"))
    }

    func testEmptySourceApplicationIsNotBypassed() {
        XCTAssertFalse(EventTransformerManager.shouldBypassSourceApplication(""))
    }

    func testOwnedReleaseTakesPriorityOverSourceBypass() throws {
        let mapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(mappings: [mapping]))
        ])
        let manager = EventTransformerManager()
        let previousBypassSetting = manager.bypassEventsFromOtherApplications
        manager.bypassEventsFromOtherApplications = true
        defer {
            manager.bypassEventsFromOtherApplications = previousBypassSetting
        }

        let button = try XCTUnwrap(CGMouseButton(rawValue: 4))
        let down = try mouseEvent(type: .otherMouseDown, button: button)
        let downResolution = manager.resolve(
            withCGEvent: down,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display A"
        )
        XCTAssertNil(downResolution.transform(down) { _ in })

        let release = try mouseEvent(type: .otherMouseUp, button: button)
        let releaseResolution = manager.resolve(
            withCGEvent: release,
            withSourcePid: getpid(),
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )

        XCTAssertIdentical(
            try buttonMappingTransformer(in: releaseResolution),
            try buttonMappingTransformer(in: downResolution)
        )
        XCTAssertNil(releaseResolution.transform(release) { _ in })
    }

    func testSourceBypassIgnoresUnrelatedButtonPairWhileInteractionIsActive() throws {
        let mapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(
                mappings: [mapping],
                switchPrimaryButtonAndSecondaryButtons: true
            ))
        ])
        let manager = EventTransformerManager()
        let previousBypassSetting = manager.bypassEventsFromOtherApplications
        manager.bypassEventsFromOtherApplications = true
        defer {
            manager.bypassEventsFromOtherApplications = previousBypassSetting
        }

        let mappedButton = try XCTUnwrap(CGMouseButton(rawValue: 4))
        let mappedDown = try mouseEvent(type: .otherMouseDown, button: mappedButton)
        let mappedDownResolution = manager.resolve(
            withCGEvent: mappedDown,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: nil
        )
        XCTAssertNil(mappedDownResolution.transform(mappedDown) { _ in })
        let owner = try buttonMappingTransformer(in: mappedDownResolution)
        XCTAssertTrue(owner.hasActiveInteraction)

        let unrelatedDown = try mouseEvent(type: .leftMouseDown, button: .left)
        let unrelatedDownResolution = manager.resolve(
            withCGEvent: unrelatedDown,
            withSourcePid: getpid(),
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: nil
        )
        let transformedDown = try XCTUnwrap(unrelatedDownResolution.transform(unrelatedDown) { _ in })
        XCTAssertEqual(transformedDown.type, .leftMouseDown)
        XCTAssertEqual(MouseEventView(transformedDown).mouseButton, .left)

        let unrelatedUp = try mouseEvent(type: .leftMouseUp, button: .left)
        let unrelatedUpResolution = manager.resolve(
            withCGEvent: unrelatedUp,
            withSourcePid: getpid(),
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: nil
        )
        let transformedUp = try XCTUnwrap(unrelatedUpResolution.transform(unrelatedUp) { _ in })
        XCTAssertEqual(transformedUp.type, .leftMouseUp)
        XCTAssertEqual(MouseEventView(transformedUp).mouseButton, .left)
        XCTAssertTrue(owner.hasActiveInteraction)

        let mappedUp = try mouseEvent(type: .otherMouseUp, button: mappedButton)
        let mappedUpResolution = manager.resolve(
            withCGEvent: mappedUp,
            withSourcePid: getpid(),
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: nil
        )
        XCTAssertNil(mappedUpResolution.transform(mappedUp) { _ in })
        XCTAssertFalse(owner.hasActiveInteraction)
    }

    func testLogitechReleaseUsesRouteThatHandledPressAcrossDisplayBoundary() throws {
        let identity = LogitechControlIdentity(controlID: 0x00C3)
        let mapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.logitechControl(identity))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(mappings: [mapping]))
        ])
        let manager = EventTransformerManager()
        let initialTransformer = try buttonMappingTransformer(in: manager.get(
            withDevice: nil,
            withPid: nil,
            withDisplay: "Display A"
        ))

        XCTAssertEqual(
            manager.handleLogitechControlEvent(logitech(identity, pressed: true, display: "Display A")),
            .handledDeferringSyntheticFallback
        )
        XCTAssertTrue(initialTransformer.hasActiveInteraction)

        XCTAssertEqual(
            manager.handleLogitechControlEvent(logitech(identity, pressed: false, display: "Display B")),
            .handled
        )
        XCTAssertFalse(initialTransformer.hasActiveInteraction)

        let latestTransformer = try buttonMappingTransformer(in: manager.get(
            withDevice: nil,
            withPid: nil,
            withDisplay: "Display B"
        ))
        XCTAssertNotIdentical(latestTransformer, initialTransformer)
    }

    func testLogitechAutoScrollKeepsPriorityWhileAnotherMappingIsActive() throws {
        let autoScrollIdentity = LogitechControlIdentity(controlID: 0x00C4)
        let mappingIdentity = LogitechControlIdentity(controlID: 0x00C5)
        var scheme = Scheme(buttons: .init(mappings: [
            .init(
                trigger: .init(input: .button(.logitechControl(mappingIdentity))),
                outcomes: .init(longPress: .arg0(.none))
            )
        ]))
        scheme.buttons.autoScroll.enabled = true
        scheme.buttons.autoScroll.modes = [.hold]
        scheme.buttons.autoScroll.trigger = .init(button: .logitechControl(autoScrollIdentity))
        ConfigurationState.shared.configuration = .init(schemes: [scheme])
        let manager = EventTransformerManager()
        let route = try XCTUnwrap(manager.get(
            withDevice: nil,
            withPid: nil,
            withDisplay: "Display A"
        ) as? [EventTransformer])
        let autoScroll = try XCTUnwrap(route.compactMap { $0 as? AutoScrollTransformer }.first)

        XCTAssertEqual(
            manager.handleLogitechControlEvent(logitech(mappingIdentity, pressed: true, display: "Display A")),
            .handledDeferringSyntheticFallback
        )
        XCTAssertEqual(
            manager.handleLogitechControlEvent(logitech(autoScrollIdentity, pressed: true, display: "Display A")),
            .handledDeferringSyntheticFallback
        )
        XCTAssertFalse(autoScroll.isAutoscrollActive)

        let move = try mouseEvent(
            type: .mouseMoved,
            button: .center,
            location: CGPoint(x: 11, y: 0)
        )
        XCTAssertNotNil(route.transform(move, in: .init(device: nil)))
        XCTAssertTrue(autoScroll.isAutoscrollActive)

        XCTAssertEqual(
            manager.handleLogitechControlEvent(logitech(autoScrollIdentity, pressed: false, display: "Display A")),
            .handled
        )
        XCTAssertFalse(autoScroll.isAutoscrollActive)

        XCTAssertTrue(manager.cancelLogitechControlInteraction(
            logitech(mappingIdentity, pressed: false, display: "Display A")
        ))
    }

    func testCancelingLostLogitechControlStopsAutoScrollWithoutMappingOwner() throws {
        let identity = LogitechControlIdentity(controlID: 0x00C4)
        var scheme = Scheme()
        scheme.buttons.autoScroll.enabled = true
        scheme.buttons.autoScroll.modes = [.hold]
        scheme.buttons.autoScroll.trigger = .init(button: .logitechControl(identity))
        ConfigurationState.shared.configuration = .init(schemes: [scheme])
        let manager = EventTransformerManager()
        let route = try XCTUnwrap(manager.get(
            withDevice: nil,
            withPid: nil,
            withDisplay: "Display A"
        ) as? [EventTransformer])
        let autoScroll = try XCTUnwrap(route.compactMap { $0 as? AutoScrollTransformer }.first)

        XCTAssertEqual(
            manager.handleLogitechControlEvent(logitech(identity, pressed: true, display: "Display A")),
            .handledDeferringSyntheticFallback
        )
        XCTAssertFalse(autoScroll.isAutoscrollActive)

        let move = try mouseEvent(
            type: .mouseMoved,
            button: .center,
            location: CGPoint(x: 11, y: 0)
        )
        XCTAssertNotNil(route.transform(move, in: .init(device: nil)))
        XCTAssertTrue(autoScroll.isAutoscrollActive)

        XCTAssertTrue(manager.cancelLogitechControlInteraction(
            logitech(identity, pressed: false, display: "Display A")
        ))
        XCTAssertFalse(autoScroll.isAutoscrollActive)
    }

    func testLogitechHeldPrefixAndMouseTriggerShareInteractionRoute() throws {
        let identity = LogitechControlIdentity(controlID: 0x00C3)
        let mapping = Scheme.Buttons.Mapping(
            trigger: .init(
                input: .button(.mouse(4)),
                whileHeld: [.logitechControl(identity)]
            ),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(mappings: [mapping]))
        ])
        let manager = EventTransformerManager()

        XCTAssertEqual(
            manager.handleLogitechControlEvent(logitech(identity, pressed: true, display: "Display A")),
            .handledDeferringSyntheticFallback
        )
        let initialTransformer = try buttonMappingTransformer(in: manager.get(
            withDevice: nil,
            withPid: nil,
            withDisplay: "Display A"
        ))

        let button = try XCTUnwrap(CGMouseButton(rawValue: 4))
        let down = try mouseEvent(type: .otherMouseDown, button: button)
        let downResolution = manager.resolve(
            withCGEvent: down,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertIdentical(try buttonMappingTransformer(in: downResolution), initialTransformer)
        XCTAssertNil(downResolution.transform(down) { _ in })

        let release = try mouseEvent(type: .otherMouseUp, button: button)
        let releaseResolution = manager.resolve(
            withCGEvent: release,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertIdentical(try buttonMappingTransformer(in: releaseResolution), initialTransformer)
        XCTAssertNil(releaseResolution.transform(release) { _ in })
        XCTAssertTrue(initialTransformer.hasActiveInteraction)

        XCTAssertEqual(
            manager.handleLogitechControlEvent(logitech(identity, pressed: false, display: "Display B")),
            .handled
        )
        XCTAssertFalse(initialTransformer.hasActiveInteraction)
    }

    func testMouseHeldPrefixAndLogitechTriggerShareInteractionRoute() throws {
        let identity = LogitechControlIdentity(controlID: 0x00C3)
        let mapping = Scheme.Buttons.Mapping(
            trigger: .init(
                input: .button(.logitechControl(identity)),
                whileHeld: [.mouse(4)]
            ),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(mappings: [mapping]))
        ])
        let manager = EventTransformerManager()
        let button = try XCTUnwrap(CGMouseButton(rawValue: 4))

        let down = try mouseEvent(type: .otherMouseDown, button: button)
        let downResolution = manager.resolve(
            withCGEvent: down,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display A"
        )
        XCTAssertNil(downResolution.transform(down) { _ in })
        let initialTransformer = try buttonMappingTransformer(in: downResolution)

        XCTAssertEqual(
            manager.handleLogitechControlEvent(logitech(identity, pressed: true, display: "Display B")),
            .handledDeferringSyntheticFallback
        )
        XCTAssertTrue(initialTransformer.hasActiveInteraction)
        XCTAssertEqual(
            manager.handleLogitechControlEvent(logitech(identity, pressed: false, display: "Display B")),
            .handled
        )
        XCTAssertTrue(initialTransformer.hasActiveInteraction)

        let release = try mouseEvent(type: .otherMouseUp, button: button)
        let releaseResolution = manager.resolve(
            withCGEvent: release,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertIdentical(try buttonMappingTransformer(in: releaseResolution), initialTransformer)
        XCTAssertNil(releaseResolution.transform(release) { _ in })
        XCTAssertFalse(initialTransformer.hasActiveInteraction)
    }

    func testConfigurationReloadLetsMouseInteractionDrainBeforeUsingNewMapping() throws {
        let originalMapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(mappings: [originalMapping]))
        ])
        let manager = EventTransformerManager()
        let button = try XCTUnwrap(CGMouseButton(rawValue: 4))
        var replayedEvents = [CGEventType]()

        let down = try mouseEvent(type: .otherMouseDown, button: button)
        let downResolution = manager.resolve(
            withCGEvent: down,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display A"
        )
        XCTAssertNil(downResolution.transform(down) { replayedEvents.append($0.type) })
        let originalTransformer = try buttonMappingTransformer(in: downResolution)
        XCTAssertTrue(originalTransformer.hasActiveInteraction)

        let intermediateMapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(5))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(mappings: [intermediateMapping]))
        ])
        let latestMapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(6))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(mappings: [latestMapping]))
        ])
        XCTAssertTrue(originalTransformer.hasActiveInteraction)
        XCTAssertTrue(replayedEvents.isEmpty)

        let release = try mouseEvent(type: .otherMouseUp, button: button)
        let releaseResolution = manager.resolve(
            withCGEvent: release,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertIdentical(try buttonMappingTransformer(in: releaseResolution), originalTransformer)
        XCTAssertNil(releaseResolution.transform(release) { replayedEvents.append($0.type) })
        XCTAssertFalse(originalTransformer.hasActiveInteraction)
        XCTAssertTrue(replayedEvents.isEmpty)

        let updatedTransformer = try buttonMappingTransformer(in: manager.get(
            withDevice: nil,
            withPid: nil,
            withDisplay: "Display B"
        ))
        XCTAssertNotIdentical(updatedTransformer, originalTransformer)
        XCTAssertEqual(updatedTransformer.mappings, [latestMapping])
    }

    func testConfigurationReloadLetsLogitechInteractionDrain() throws {
        let identity = LogitechControlIdentity(controlID: 0x00C3)
        let originalMapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.logitechControl(identity))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(mappings: [originalMapping]))
        ])
        let manager = EventTransformerManager()
        let originalTransformer = try buttonMappingTransformer(in: manager.get(
            withDevice: nil,
            withPid: nil,
            withDisplay: "Display A"
        ))

        XCTAssertEqual(
            manager.handleLogitechControlEvent(logitech(identity, pressed: true, display: "Display A")),
            .handledDeferringSyntheticFallback
        )
        XCTAssertTrue(originalTransformer.hasActiveInteraction)

        let updatedMapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(5))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(mappings: [updatedMapping]))
        ])
        XCTAssertTrue(originalTransformer.hasActiveInteraction)

        XCTAssertEqual(
            manager.handleLogitechControlEvent(logitech(identity, pressed: false, display: "Display B")),
            .handled
        )
        XCTAssertFalse(originalTransformer.hasActiveInteraction)

        let updatedTransformer = try buttonMappingTransformer(in: manager.get(
            withDevice: nil,
            withPid: nil,
            withDisplay: "Display B"
        ))
        XCTAssertNotIdentical(updatedTransformer, originalTransformer)
        XCTAssertEqual(updatedTransformer.mappings, [updatedMapping])
    }

    func testCancelingLostLogitechControlDrainsRetiredTransformerWithoutShortPress() throws {
        let identity = LogitechControlIdentity(controlID: 0x00C3)
        let originalMapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.logitechControl(identity))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(mappings: [originalMapping]))
        ])
        let manager = EventTransformerManager()

        XCTAssertEqual(
            manager.handleLogitechControlEvent(logitech(identity, pressed: true, display: "Display A")),
            .handledDeferringSyntheticFallback
        )
        let originalTransformer = try buttonMappingTransformer(in: manager.get(
            withDevice: nil,
            withPid: nil,
            withDisplay: "Display A"
        ))
        XCTAssertTrue(originalTransformer.hasActiveInteraction)

        let updatedMapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(5))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(mappings: [updatedMapping]))
        ])

        XCTAssertTrue(manager.cancelLogitechControlInteraction(
            logitech(identity, pressed: false, display: "Display B")
        ))
        XCTAssertFalse(originalTransformer.hasActiveInteraction)

        let updatedTransformer = try buttonMappingTransformer(in: manager.get(
            withDevice: nil,
            withPid: nil,
            withDisplay: "Display B"
        ))
        XCTAssertNotIdentical(updatedTransformer, originalTransformer)
        XCTAssertEqual(updatedTransformer.mappings, [updatedMapping])
    }

    func testRestartForcesActiveInteractionToReset() throws {
        let mapping = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(mappings: [mapping]))
        ])
        let manager = EventTransformerManager()
        let button = try XCTUnwrap(CGMouseButton(rawValue: 4))

        let down = try mouseEvent(type: .otherMouseDown, button: button)
        let downResolution = manager.resolve(
            withCGEvent: down,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display A"
        )
        XCTAssertNil(downResolution.transform(down) { _ in })
        let originalTransformer = try buttonMappingTransformer(in: downResolution)
        XCTAssertTrue(originalTransformer.hasActiveInteraction)

        manager.resetForRestart()
        XCTAssertFalse(originalTransformer.hasActiveInteraction)

        let release = try mouseEvent(type: .otherMouseUp, button: button)
        let releaseResolution = manager.resolve(
            withCGEvent: release,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: "Display B"
        )
        XCTAssertNotIdentical(try buttonMappingTransformer(in: releaseResolution), originalTransformer)
        XCTAssertNotNil(releaseResolution.transform(release) { _ in })
    }

    func testSyntheticSmoothedEventStillGetsModifierActions() throws {
        let modifiers = Scheme.Scrolling.Modifiers(option: .changeSpeed(scale: 2))
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(
                scrolling: .init(
                    reverse: .init(vertical: true),
                    acceleration: .init(vertical: 2),
                    smoothed: .init(vertical: .init(enabled: true, preset: .smooth)),
                    modifiers: .init(vertical: modifiers)
                )
            )
        ])

        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 0,
            wheel3: 0
        ))
        let view = ScrollWheelEventView(event)
        view.continuous = true
        view.deltaYPt = 12
        view.deltaYFixedPt = 12
        event.flags = [.maskAlternate]
        event.isLinearMouseSyntheticEvent = true

        let transformer = EventTransformerManager.shared.get(
            withCGEvent: event,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: nil
        )
        let transformedEvent = try XCTUnwrap(transformer.transform(event, in: EventTransformerContext(device: nil)))
        let transformedView = ScrollWheelEventView(transformedEvent)

        XCTAssertEqual(transformedView.deltaYPt, 24, accuracy: 0.001)
        XCTAssertEqual(transformedView.deltaYFixedPt, 24, accuracy: 0.001)
        XCTAssertEqual(transformedEvent.flags, [])
    }

    func testDisabledSmoothedConfigurationFallsBackToLegacyScrolling() throws {
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(scrolling: .init(
                smoothed: .init(vertical: .init(enabled: true, preset: .smooth))
            )),
            Scheme(scrolling: .init(
                distance: .init(vertical: .line(3)),
                smoothed: .init(vertical: .init(enabled: false))
            ))
        ])

        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))

        let transformer = EventTransformerManager.shared.get(
            withCGEvent: event,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: nil
        )
        let transformedEvent = try XCTUnwrap(transformer.transform(event, in: EventTransformerContext(device: nil)))
        let view = ScrollWheelEventView(transformedEvent)

        XCTAssertEqual(view.deltaY, 3)
        XCTAssertNil(view.scrollPhase)
        XCTAssertEqual(view.momentumPhase, .none)
    }

    func testContinuousTrackpadEventStillGetsReverseScrollingWhenSmoothedExists() throws {
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(
                scrolling: .init(
                    reverse: .init(vertical: true),
                    smoothed: .init(vertical: .init(enabled: true, preset: .easeInOut))
                )
            )
        ])

        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 0,
            wheel3: 0
        ))
        let view = ScrollWheelEventView(event)
        view.continuous = true
        view.deltaYPt = 12
        view.deltaYFixedPt = 12
        view.scrollPhase = .began

        let transformer = EventTransformerManager.shared.get(
            withCGEvent: event,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: nil
        )
        let transformedEvent = try XCTUnwrap(transformer.transform(event, in: EventTransformerContext(device: nil)))
        let transformedView = ScrollWheelEventView(transformedEvent)

        XCTAssertEqual(transformedView.deltaYPt, 0, accuracy: 0.001)
        XCTAssertLessThan(transformedView.deltaYFixedPt, 0)
        XCTAssertGreaterThan(transformedView.deltaYFixedPt, -12)
        XCTAssertEqual(transformedView.scrollPhase, .began)
    }

    func testUnifiedButtonMappingTransformerReceivesUniversalBackForwardSetting() throws {
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(
                mappings: [.init(scroll: .left, action: .arg0(.mouseButtonBack))],
                universalBackForward: .both
            ))
        ])

        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 1,
            wheel3: 0
        ))

        let transformer = EventTransformerManager.shared.get(
            withCGEvent: event,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: nil
        )
        let buttonMappingTransformer = try XCTUnwrap((transformer as? [EventTransformer])?
            .compactMap { $0 as? ButtonMappingTransformer }
            .first)

        XCTAssertEqual(buttonMappingTransformer.universalBackForward, .both)
    }

    func testSmoothedScrollingRoutesScrollButtonMappingsBeforeSmoothing() throws {
        let scrollMapping = Scheme.Buttons.Mapping(scroll: .up, control: true, action: .arg0(.none))
        let buttonMapping = Scheme.Buttons.Mapping(button: .mouse(4), action: .arg0(.none))
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(
                scrolling: .init(smoothed: .init(vertical: .init(enabled: true, preset: .smooth))),
                buttons: .init(mappings: [scrollMapping, buttonMapping], universalBackForward: .both)
            )
        ])

        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        event.flags = [.maskControl]

        let transformer = EventTransformerManager.shared.get(
            withCGEvent: event,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: nil
        )
        let transformers = try XCTUnwrap(transformer as? [EventTransformer])
        let smoothedIndex = try XCTUnwrap(transformers.firstIndex { $0 is SmoothedScrollingTransformer })
        let indexedButtonMappingTransformers = transformers.enumerated().compactMap { index, transformer in
            (transformer as? ButtonMappingTransformer).map { (index, $0) }
        }
        let (mappingIndex, mappingTransformer) = try XCTUnwrap(indexedButtonMappingTransformers.first)

        XCTAssertEqual(indexedButtonMappingTransformers.count, 1)
        XCTAssertLessThan(mappingIndex, smoothedIndex)
        XCTAssertEqual(mappingTransformer.mappings.count, 2)
        XCTAssertTrue(mappingTransformer.mappings.allSatisfy(\.isStructured))
        XCTAssertEqual(mappingTransformer.universalBackForward, .both)
    }

    func testLegacyAndStructuredMappingsUseOneUnifiedTransformer() throws {
        let structured = Scheme.Buttons.Mapping(
            trigger: .init(input: .button(.mouse(4))),
            outcomes: .init(shortPress: .arg0(.none))
        )
        let legacyButton = Scheme.Buttons.Mapping(button: .mouse(5), action: .arg0(.none))
        let legacyWheel = Scheme.Buttons.Mapping(scroll: .up, action: .arg0(.none))
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(buttons: .init(mappings: [structured, legacyButton, legacyWheel]))
        ])

        let transformers = try XCTUnwrap(EventTransformerManager.shared.get(
            withDevice: nil,
            withPid: nil,
            withDisplay: nil
        ) as? [EventTransformer])

        let mappingTransformers = transformers.compactMap { $0 as? ButtonMappingTransformer }
        let mappingTransformer = try XCTUnwrap(mappingTransformers.first)
        XCTAssertEqual(mappingTransformers.count, 1)
        XCTAssertEqual(mappingTransformer.mappings.count, 3)
        XCTAssertTrue(mappingTransformer.mappings.allSatisfy(\.isStructured))
    }

    func testStructuredWheelRecognizerRunsBeforeSmoothedScrolling() throws {
        let structuredWheel = Scheme.Buttons.Mapping(
            trigger: .init(input: .wheel(.up)),
            action: .arg0(.none)
        )
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(
                scrolling: .init(smoothed: .init(vertical: .init(enabled: true, preset: .smooth))),
                buttons: .init(mappings: [structuredWheel])
            )
        ])

        let transformers = try XCTUnwrap(EventTransformerManager.shared.get(
            withDevice: nil,
            withPid: nil,
            withDisplay: nil
        ) as? [EventTransformer])
        let mappingIndex = try XCTUnwrap(transformers.firstIndex { $0 is ButtonMappingTransformer })
        let smoothingIndex = try XCTUnwrap(transformers.firstIndex { $0 is SmoothedScrollingTransformer })

        XCTAssertLessThan(mappingIndex, smoothingIndex)
    }

    func testAllButtonMappingsUseUnifiedPipelineWithoutSmoothing() throws {
        let scrollMapping = Scheme.Buttons.Mapping(scroll: .up, control: true, action: .arg0(.none))
        let buttonMapping = Scheme.Buttons.Mapping(button: .mouse(4), action: .arg0(.none))
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(
                buttons: .init(mappings: [scrollMapping, buttonMapping], universalBackForward: .both)
            )
        ])

        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        event.flags = [.maskControl]

        let transformer = EventTransformerManager.shared.get(
            withCGEvent: event,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: nil
        )
        let buttonMappingTransformers = try XCTUnwrap(transformer as? [EventTransformer])
            .compactMap { $0 as? ButtonMappingTransformer }
        let buttonMappingTransformer = try XCTUnwrap(buttonMappingTransformers.first)

        XCTAssertEqual(buttonMappingTransformers.count, 1)
        XCTAssertEqual(buttonMappingTransformer.mappings.count, 2)
        XCTAssertTrue(buttonMappingTransformer.mappings.allSatisfy(\.isStructured))
        XCTAssertEqual(buttonMappingTransformer.universalBackForward, .both)
    }

    func testSmoothedScrollingDoesNotApplyScrollButtonMappingsToSyntheticEvents() throws {
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(
                scrolling: .init(smoothed: .init(vertical: .init(enabled: true, preset: .smooth))),
                buttons: .init(mappings: [
                    .init(scroll: .up, control: true, action: .arg0(.none))
                ])
            )
        ])

        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 0,
            wheel3: 0
        ))
        let view = ScrollWheelEventView(event)
        view.deltaYPt = 12
        view.deltaYFixedPt = 12
        event.flags = [.maskControl]
        event.isLinearMouseSyntheticEvent = true

        let transformer = EventTransformerManager.shared.get(
            withCGEvent: event,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: nil
        )

        XCTAssertNotNil(transformer.transform(event, in: EventTransformerContext(device: nil)))
    }

    func testScrollButtonRecordingUsesReversedDirectionBeforeSmoothing() throws {
        ConfigurationState.shared.configuration = .init(schemes: [
            Scheme(
                scrolling: .init(
                    reverse: .init(vertical: true),
                    smoothed: .init(vertical: .init(enabled: true, preset: .smooth)),
                    modifiers: .init(vertical: .init(command: .preventDefault))
                )
            )
        ])
        let recordingSessionID = UUID()
        SettingsState.shared.beginButtonMappingRecording(sessionID: recordingSessionID)

        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))
        event.flags = [.maskCommand]

        let transformer = EventTransformerManager.shared.get(
            withCGEvent: event,
            withSourcePid: nil,
            withTargetPid: nil,
            withMouseLocationPid: nil,
            withDisplay: nil
        )

        XCTAssertNil(transformer.transform(event, in: EventTransformerContext(device: nil)))

        let recordedExpectation = expectation(description: "Recorded transformed scroll mapping")
        DispatchQueue.main.async {
            let recordedEvent = SettingsState.shared.recordedButtonMappingEvent
            XCTAssertEqual(recordedEvent?.recordingSessionID, recordingSessionID)
            XCTAssertNil(recordedEvent?.button)
            XCTAssertEqual(recordedEvent?.scroll, .down)
            XCTAssertEqual(recordedEvent?.modifierFlags, [.maskCommand])
            recordedExpectation.fulfill()
        }
        wait(for: [recordedExpectation], timeout: 1)
    }

    func testEndingStaleButtonMappingRecordingSessionDoesNotStopCurrentSession() {
        let staleSessionID = UUID()
        let currentSessionID = UUID()

        SettingsState.shared.beginButtonMappingRecording(sessionID: staleSessionID)
        SettingsState.shared.beginButtonMappingRecording(sessionID: currentSessionID)
        SettingsState.shared.endButtonMappingRecording(sessionID: staleSessionID)

        XCTAssertTrue(SettingsState.shared.recording)
        XCTAssertEqual(SettingsState.shared.buttonMappingRecordingSessionID, currentSessionID)

        SettingsState.shared.endButtonMappingRecording(sessionID: currentSessionID)

        XCTAssertFalse(SettingsState.shared.recording)
        XCTAssertNil(SettingsState.shared.buttonMappingRecordingSessionID)
    }

    func testVirtualButtonPreparationIsPartOfButtonMappingRecordingSession() {
        let recordingSessionID = UUID()
        let deviceID: Int32 = 42

        SettingsState.shared.beginButtonMappingRecording(
            sessionID: recordingSessionID,
            pendingVirtualButtonDeviceIDs: [deviceID]
        )

        XCTAssertTrue(SettingsState.shared.recording)
        XCTAssertEqual(SettingsState.shared.buttonMappingRecordingSessionID, recordingSessionID)
        XCTAssertTrue(SettingsState.shared.isPreparingVirtualButtonRecording)

        SettingsState.shared.finishVirtualButtonRecordingPreparation(
            for: deviceID,
            sessionID: recordingSessionID
        )

        XCTAssertTrue(SettingsState.shared.recording)
        XCTAssertEqual(SettingsState.shared.buttonMappingRecordingSessionID, recordingSessionID)
        XCTAssertFalse(SettingsState.shared.isPreparingVirtualButtonRecording)
    }

    func testFinishingCompletedVirtualButtonPreparationDoesNotRepublishSession() {
        let recordingSessionID = UUID()
        let deviceID: Int32 = 42
        var publishedSessions = [SettingsState.ButtonMappingRecordingSession?]()

        SettingsState.shared.beginButtonMappingRecording(
            sessionID: recordingSessionID,
            pendingVirtualButtonDeviceIDs: [deviceID]
        )

        let cancellable = SettingsState.shared
            .$buttonMappingRecordingSession
            .dropFirst()
            .sink { session in
                publishedSessions.append(session)
            }

        SettingsState.shared.finishVirtualButtonRecordingPreparation(
            for: deviceID,
            sessionID: recordingSessionID
        )
        SettingsState.shared.finishVirtualButtonRecordingPreparation(
            for: deviceID,
            sessionID: recordingSessionID
        )

        XCTAssertEqual(publishedSessions.count, 1)
        XCTAssertEqual(publishedSessions.first??.pendingVirtualButtonDeviceIDs, [])

        cancellable.cancel()
    }

    func testEndingPreviousRecordingSessionDuringNewSessionPublishDoesNotClearNewSession() {
        let previousSessionID = UUID()
        let currentSessionID = UUID()
        var publishedSessionIDs = [UUID?]()

        SettingsState.shared.beginButtonMappingRecording(sessionID: previousSessionID)

        let cancellable = SettingsState.shared
            .$buttonMappingRecordingSession
            .dropFirst()
            .sink { session in
                publishedSessionIDs.append(session?.id)

                guard session?.id == currentSessionID else {
                    return
                }

                SettingsState.shared.endButtonMappingRecording(sessionID: previousSessionID)
            }

        SettingsState.shared.beginButtonMappingRecording(sessionID: currentSessionID)

        XCTAssertEqual(SettingsState.shared.buttonMappingRecordingSessionID, currentSessionID)
        XCTAssertEqual(SettingsState.shared.buttonMappingRecordingSession?.id, currentSessionID)
        XCTAssertEqual(publishedSessionIDs, [currentSessionID])

        cancellable.cancel()
    }

    func testScrollButtonRecordingIgnoresStaleAsyncEventAfterSessionChanges() throws {
        let staleSessionID = UUID()
        let currentSessionID = UUID()
        let transformer = ButtonMappingScrollRecordingTransformer()
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: 0,
            wheel3: 0
        ))

        SettingsState.shared.beginButtonMappingRecording(sessionID: staleSessionID)
        XCTAssertNil(transformer.transform(event, in: EventTransformerContext(device: nil)))
        SettingsState.shared.endButtonMappingRecording(sessionID: staleSessionID)
        SettingsState.shared.beginButtonMappingRecording(sessionID: currentSessionID)

        let staleEventExpectation = expectation(description: "Stale scroll recording is ignored")
        DispatchQueue.main.async {
            XCTAssertNil(SettingsState.shared.recordedButtonMappingEvent)
            XCTAssertEqual(SettingsState.shared.buttonMappingRecordingSessionID, currentSessionID)
            staleEventExpectation.fulfill()
        }
        wait(for: [staleEventExpectation], timeout: 1)
    }

    private func buttonMappingTransformer(
        in resolution: EventTransformerResolution
    ) throws -> ButtonMappingTransformer {
        try buttonMappingTransformer(in: resolution.transformer)
    }

    private func buttonMappingTransformer(
        in transformer: EventTransformer
    ) throws -> ButtonMappingTransformer {
        try XCTUnwrap((transformer as? [EventTransformer])?
            .compactMap { $0 as? ButtonMappingTransformer }
            .first)
    }

    private func logitech(
        _ identity: LogitechControlIdentity,
        pressed: Bool,
        display: String
    ) -> LogitechEventContext {
        .init(
            device: nil,
            pid: nil,
            display: display,
            mouseLocation: .zero,
            controlIdentity: identity,
            isPressed: pressed,
            modifierFlags: []
        )
    }

    private func mouseEvent(
        type: CGEventType,
        button: CGMouseButton,
        location: CGPoint = .zero
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        ))
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
        return event
    }
}
