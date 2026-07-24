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

    func testButtonActionTransformerReceivesUniversalBackForwardSetting() throws {
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
        let buttonActionsTransformer = try XCTUnwrap((transformer as? [EventTransformer])?
            .compactMap { $0 as? ButtonActionsTransformer }
            .first)

        XCTAssertEqual(buttonActionsTransformer.universalBackForward, .both)
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
        let buttonActionsTransformers = transformers.enumerated().compactMap { index, transformer in
            (transformer as? ButtonActionsTransformer).map { (index, $0) }
        }

        let earlyButtonActionsTransformer = try XCTUnwrap(buttonActionsTransformers
            .first { index, _ in index < smoothedIndex }?
            .1)
        let lateButtonActionsTransformer = try XCTUnwrap(buttonActionsTransformers
            .first { index, _ in index > smoothedIndex }?
            .1)

        XCTAssertEqual(earlyButtonActionsTransformer.mappings, [scrollMapping])
        XCTAssertEqual(earlyButtonActionsTransformer.universalBackForward, .both)
        XCTAssertTrue(earlyButtonActionsTransformer.ignoresLinearMouseSyntheticScrollEvents)
        XCTAssertEqual(lateButtonActionsTransformer.mappings, [buttonMapping])
        XCTAssertEqual(lateButtonActionsTransformer.universalBackForward, .both)
        XCTAssertFalse(lateButtonActionsTransformer.ignoresLinearMouseSyntheticScrollEvents)
        XCTAssertIdentical(earlyButtonActionsTransformer.runtimeState, lateButtonActionsTransformer.runtimeState)
    }

    func testScrollButtonMappingsUseScrollPipelineWithoutSmoothing() throws {
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
        let buttonActionsTransformers = try XCTUnwrap(transformer as? [EventTransformer])
            .compactMap { $0 as? ButtonActionsTransformer }

        XCTAssertEqual(buttonActionsTransformers.map(\.mappings), [[scrollMapping], [buttonMapping]])
        XCTAssertEqual(buttonActionsTransformers.map(\.universalBackForward), [.both, .both])
        XCTAssertEqual(buttonActionsTransformers.map(\.ignoresLinearMouseSyntheticScrollEvents), [true, false])
        XCTAssertIdentical(buttonActionsTransformers[0].runtimeState, buttonActionsTransformers[1].runtimeState)
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
                    smoothed: .init(vertical: .init(enabled: true, preset: .smooth))
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
        event.flags = [.maskControl]

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
            XCTAssertEqual(recordedEvent?.modifierFlags, [.maskControl])
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
}
