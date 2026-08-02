// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import Foundation
import ObservationToken
import SwiftUI

struct ButtonMappingButtonRecorder: View {
    enum Mode {
        case simple
        case advanced
    }

    @Binding var mapping: Scheme.Buttons.Mapping

    var autoStartRecording = false
    var mode: Mode = .simple

    @ObservedObject private var settingsState = SettingsState.shared

    @State private var recording = false {
        didSet {
            guard oldValue != recording else {
                return
            }
            updateSharedRecordingState()
            recordingUpdated()
        }
    }

    @State private var recordingObservationToken: ObservationToken?
    @State private var recordedMappingCancellable: AnyCancellable?
    @State private var recordingSessionID: UUID?
    @State private var advancedEngine = ButtonMappingRecordingEngine()
    @State private var advancedSnapshot = ButtonMappingRecordingEngine.Snapshot()

    private let recordingTicker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            switch mode {
            case .simple:
                simpleRecorder
            case .advanced:
                advancedRecorder
            }
        }
        .onAppear {
            updateSharedRecordingState()
            if autoStartRecording {
                recording = true
            }
        }
        .onDisappear {
            cancelObservation()
            recording = false
            updateSharedRecordingState(force: false)
        }
        .onReceive(settingsState.$buttonMappingRecordingSession) { session in
            guard recording,
                  let recordingSessionID,
                  session?.id != recordingSessionID else {
                return
            }

            recording = false
        }
        .onReceive(recordingTicker) { _ in
            guard recording, mode == .advanced else {
                return
            }
            advancedEngine.advance(to: DispatchTime.now().uptimeNanoseconds)
            synchronizeAdvancedSnapshot()
        }
    }

    private var simpleRecorder: some View {
        Button {
            recording.toggle()
        } label: {
            Group {
                if recording {
                    ButtonMappingButtonDescription(mapping: mapping, showPartial: true) {
                        Text(settingsState.isPreparingVirtualButtonRecording ? "Waiting for device…" : "Recording")
                    }
                } else {
                    ButtonMappingButtonDescription(mapping: mapping) {
                        Text("Click to record")
                    }
                }
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
        }
    }

    private var advancedRecorder: some View {
        Button {
            recording.toggle()
        } label: {
            ButtonMappingRecordingPreview(
                mapping: mapping,
                snapshot: advancedSnapshot,
                isRecording: recording,
                isPreparingDevice: settingsState.isPreparingVirtualButtonRecording
            )
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
            .contentShape(Rectangle())
        }
        .accessibility(label: recording ? Text("Recording") : Text("Click to record"))
        .accessibility(
            hint: recording
                ? Text("Press, hold, combine buttons, drag, or scroll; the recognized trigger updates live.")
                : Text("Start recording a button gesture.")
        )
    }

    private func updateSharedRecordingState(force: Bool? = nil) {
        let shouldRecord = force ?? recording
        if shouldRecord {
            let sessionID = currentRecordingSessionID()
            let monitorDevices = logitechMonitorDevices()
            settingsState.beginButtonMappingRecording(
                sessionID: sessionID,
                pendingVirtualButtonDeviceIDs: Set(monitorDevices.map(\.id))
            )
            monitorDevices.forEach { $0.prepareLogitechControlsRecording() }
        } else {
            guard let recordingSessionID else {
                return
            }

            settingsState.endButtonMappingRecording(sessionID: recordingSessionID)
            self.recordingSessionID = nil
        }
    }

    private func currentRecordingSessionID() -> UUID {
        if let recordingSessionID {
            return recordingSessionID
        }

        let recordingSessionID = UUID()
        self.recordingSessionID = recordingSessionID
        return recordingSessionID
    }

    private func recordingUpdated() {
        recordingObservationToken?.cancel()
        recordingObservationToken = nil
        recordedMappingCancellable?.cancel()
        recordedMappingCancellable = nil

        if recording {
            mapping = .init()
            advancedEngine.reset()
            advancedSnapshot = advancedEngine.snapshot
            startEventObservation()
        }
    }

    private func startEventObservation() {
        var eventTypes: [CGEventType] = [
            .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp
        ]
        if mode == .advanced {
            eventTypes += [
                .leftMouseDragged,
                .rightMouseDragged,
                .otherMouseDragged,
                .mouseMoved
            ]
        }

        recordingObservationToken = try? EventTap.observe(
            eventTypes,
            place: .tailAppendEventTap
        ) { _, event in
            eventReceived(event)
        }

        if recordingObservationToken == nil {
            recording = false
            return
        }

        guard let recordingSessionID else {
            recording = false
            return
        }

        settingsState.recordedButtonMappingEvent = nil

        recordedMappingCancellable = settingsState
            .$recordedButtonMappingEvent
            .compactMap { event in
                guard event?.recordingSessionID == recordingSessionID else {
                    return nil
                }
                return event
            }
            .receive(on: DispatchQueue.main)
            .sink { event in
                recordedMappingReceived(event)
            }
    }

    private func cancelObservation() {
        recordingObservationToken?.cancel()
        recordingObservationToken = nil
        recordedMappingCancellable?.cancel()
        recordedMappingCancellable = nil
    }

    private func logitechMonitorDevices() -> [Device] {
        guard let currentDevice = DeviceState.shared.currentDeviceRef?.value,
              currentDevice.hasLogitechControlsMonitor else {
            return []
        }

        return [currentDevice]
    }

    private func recordedMappingReceived(_ event: SettingsState.RecordedButtonMappingEvent) {
        defer {
            settingsState.recordedButtonMappingEvent = nil
        }

        guard mode == .advanced else {
            mapping.button = event.button
            mapping.scroll = event.scroll
            mapping.modifierFlags = event.modifierFlags
            recording = false
            return
        }

        let now = DispatchTime.now().uptimeNanoseconds
        if let button = event.button {
            if event.isPressed == false {
                advancedEngine.buttonUp(button, at: now)
            } else {
                advancedEngine.buttonDown(button, modifierFlags: event.modifierFlags, at: now)
                if event.isPressed == nil {
                    advancedEngine.buttonUp(button, at: now)
                }
            }
        } else if let scroll = event.scroll {
            advancedEngine.wheel(scroll, modifierFlags: event.modifierFlags, at: now)
        }
        synchronizeAdvancedSnapshot()
    }

    private func eventReceived(_ event: CGEvent) -> CGEvent? {
        guard mode == .advanced else {
            let result = ButtonMappingButtonRecordingEventHandler.record(event, into: &mapping)
            if result.stopsRecording {
                recording = false
            }
            return result.event
        }

        let now = DispatchTime.now().uptimeNanoseconds
        switch event.type {
        case .flagsChanged:
            advancedEngine.modifierFlagsChanged(event.flags)
            synchronizeAdvancedSnapshot()
            return nil
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            advancedEngine.buttonDown(
                .mouse(Int(event.getIntegerValueField(.mouseEventButtonNumber))),
                modifierFlags: event.flags,
                at: now
            )
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            advancedEngine.buttonUp(
                .mouse(Int(event.getIntegerValueField(.mouseEventButtonNumber))),
                at: now
            )
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .mouseMoved:
            advancedEngine.pointerMoved(
                deltaX: event.getDoubleValueField(.mouseEventDeltaX),
                deltaY: event.getDoubleValueField(.mouseEventDeltaY),
                at: now
            )
        default:
            return event
        }

        synchronizeAdvancedSnapshot()
        return event.type == .mouseMoved ? event : nil
    }

    private func synchronizeAdvancedSnapshot() {
        let snapshot = advancedEngine.snapshot
        guard snapshot != advancedSnapshot else {
            return
        }

        advancedSnapshot = snapshot
        if let mapping = advancedSnapshot.mapping {
            self.mapping = mapping
        }
        if advancedSnapshot.isComplete {
            recording = false
        }
    }
}

private struct ButtonMappingRecordingPreview: View {
    typealias Mapping = Scheme.Buttons.Mapping

    var mapping: Mapping
    var snapshot: ButtonMappingRecordingEngine.Snapshot
    var isRecording: Bool
    var isPreparingDevice: Bool

    var body: some View {
        HStack(spacing: 8) {
            if tokens.isEmpty, !isRecording {
                Text("Click to record")
                    .allowsHitTesting(false)
                Spacer(minLength: 0)
            } else {
                if tokens.isEmpty {
                    Group {
                        if isPreparingDevice {
                            Text("Waiting for device…")
                        } else {
                            Text("Press a button or scroll")
                        }
                    }
                    .foregroundColor(.orange)
                } else {
                    if let relationshipDescription {
                        ScrollView(.horizontal, showsIndicators: false) {
                            relationshipDescriptionView(relationshipDescription)
                        }
                        .allowsHitTesting(false)
                        .frame(height: 18)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            tokenRow
                        }
                        .allowsHitTesting(false)
                        .frame(height: 18)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .font(.body)
        .foregroundColor(.primary)
        .padding(.horizontal, 10)
    }

    private func relationshipDescriptionView(_ description: String) -> some View {
        Text(description)
            .allowsHitTesting(false)
    }

    private var tokenRow: some View {
        HStack(spacing: 5) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                Text(token.text)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayedMapping: Mapping {
        isRecording ? snapshot.mapping ?? mapping : mapping
    }

    private var relationshipDescription: String? {
        guard let trigger = displayedMapping.trigger,
              trigger.whileHeld?.isEmpty == false || trigger.simultaneous?.isEmpty == false else {
            return nil
        }
        return ButtonMappingTriggerText.description(for: trigger, buttonDescription: buttonDescription)
    }

    private var tokens: [Token] {
        var result = [Token]()
        let modifierText = modifierDescription(
            displayedMapping.effectiveTrigger?.modifierFlags ?? snapshot.modifierFlags
        )
        if !modifierText.isEmpty {
            result.append(.init(text: modifierText))
        }

        guard let trigger = displayedMapping.effectiveTrigger else {
            return result
        }

        let swipeDirection: ButtonMappingEngine.SwipeDirection? = switch snapshot.recognition {
        case let .swipe(direction):
            direction
        default:
            isRecording ? snapshot.movementDirection : nil
        }
        if let swipeDirection, case let .button(button) = trigger.input {
            result.append(.init(
                text: String(
                    format: NSLocalizedString(
                        "Hold %@, then %@",
                        comment: "Localized swipe trigger"
                    ),
                    buttonDescription(button),
                    swipeDirectionDescription(swipeDirection)
                )
            ))
            return result
        }

        switch trigger.input {
        case let .button(button):
            result.append(.init(text: triggerButtonDescription(button)))
        case let .wheel(direction):
            result.append(.init(text: wheelDescription(direction)))
        }
        return result
    }

    private func triggerButtonDescription(_ button: Mapping.Button) -> String {
        let format: String
        switch snapshot.recognition {
        case .longPress:
            format = NSLocalizedString("Long Press %@", comment: "Recorded gesture token")
        case .swipe:
            format = NSLocalizedString("Hold %@", comment: "Recorded gesture token")
        default:
            if isRecording, snapshot.movementDirection != nil {
                format = NSLocalizedString("Hold %@", comment: "Recorded gesture token")
            } else {
                format = NSLocalizedString("Press %@", comment: "Recorded gesture token")
            }
        }
        return String(format: format, buttonDescription(button))
    }

    private func modifierDescription(_ flags: CGEventFlags) -> String {
        [
            (flags.contains(.maskControl), "⌃"),
            (flags.contains(.maskAlternate), "⌥"),
            (flags.contains(.maskShift), "⇧"),
            (flags.contains(.maskCommand), "⌘")
        ]
        .compactMap { $0.0 ? $0.1 : nil }
        .joined()
    }

    private func buttonDescription(_ button: Mapping.Button) -> String {
        switch button {
        case let .mouse(number):
            switch number {
            case 0:
                return NSLocalizedString("Primary", comment: "Primary mouse button")
            case 1:
                return NSLocalizedString("Secondary", comment: "Secondary mouse button")
            case 2:
                return NSLocalizedString("Middle", comment: "Middle mouse button")
            default:
                return String(
                    format: NSLocalizedString("Button %d", comment: "Mouse button token"),
                    number
                )
            }
        case let .logitechControl(identity):
            return identity.userVisibleName
        }
    }

    private func wheelDescription(_ direction: Mapping.ScrollDirection) -> String {
        String(
            format: NSLocalizedString("Scroll %@", comment: "Recorded gesture token"),
            wheelArrow(direction)
        )
    }

    private func wheelArrow(_ direction: Mapping.ScrollDirection) -> String {
        switch direction {
        case .up:
            return "↑"
        case .down:
            return "↓"
        case .left:
            return "←"
        case .right:
            return "→"
        }
    }

    private func swipeDirectionDescription(_ direction: ButtonMappingEngine.SwipeDirection) -> String {
        switch direction {
        case .up:
            return NSLocalizedString("Swipe up", comment: "Swipe direction")
        case .down:
            return NSLocalizedString("Swipe down", comment: "Swipe direction")
        case .left:
            return NSLocalizedString("Swipe left", comment: "Swipe direction")
        case .right:
            return NSLocalizedString("Swipe right", comment: "Swipe direction")
        }
    }

    private struct Token {
        var text: String
    }
}

enum ButtonMappingButtonRecordingEventHandler {
    struct Result {
        var event: CGEvent?
        var stopsRecording: Bool
    }

    static func record(_ event: CGEvent, into mapping: inout Scheme.Buttons.Mapping) -> Result {
        mapping.button = nil
        mapping.scroll = nil
        mapping.modifierFlags = event.flags

        switch event.type {
        case .flagsChanged:
            return .init(event: nil, stopsRecording: false)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            mapping.button = .mouse(Int(event.getIntegerValueField(.mouseEventButtonNumber)))
            return .init(event: nil, stopsRecording: false)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            mapping.button = .mouse(Int(event.getIntegerValueField(.mouseEventButtonNumber)))
        default:
            break
        }

        return .init(event: nil, stopsRecording: true)
    }
}
