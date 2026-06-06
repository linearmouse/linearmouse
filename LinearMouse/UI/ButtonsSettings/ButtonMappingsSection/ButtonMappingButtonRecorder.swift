// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import ObservationToken
import SwiftUI

struct ButtonMappingButtonRecorder: View {
    @Binding var mapping: Scheme.Buttons.Mapping

    var autoStartRecording = false

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
    @State private var recordedButtonCancellable: AnyCancellable?
    @State private var recordedMappingCancellable: AnyCancellable?

    var body: some View {
        Button {
            recording.toggle()
        } label: {
            Group {
                if recording {
                    ButtonMappingButtonDescription(mapping: mapping, showPartial: true) {
                        Text(settingsState.isPreparingVirtualButtonRecording ? "Waiting for device…" : "Recording")
                    }
                    .foregroundColor(.orange)
                } else {
                    ButtonMappingButtonDescription(mapping: mapping) {
                        Text("Click to record")
                    }
                }
            }
            .frame(maxWidth: .infinity)
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
    }

    private func updateSharedRecordingState(force: Bool? = nil) {
        let shouldRecord = force ?? recording
        if shouldRecord {
            let monitorDevices = logitechMonitorDevices()
            settingsState.beginVirtualButtonRecordingPreparation(for: Set(monitorDevices.map(\.id)))
            settingsState.recording = shouldRecord
            monitorDevices.forEach { $0.prepareLogitechControlsRecording() }
        } else {
            settingsState.endVirtualButtonRecordingPreparation()
            settingsState.recording = shouldRecord
        }
    }

    private func recordingUpdated() {
        if let recordingObservationToken {
            recordingObservationToken.cancel()
            self.recordingObservationToken = nil
        }
        recordedButtonCancellable?.cancel()
        recordedButtonCancellable = nil
        recordedMappingCancellable?.cancel()
        recordedMappingCancellable = nil

        if recording {
            mapping.modifierFlags = []
            mapping.button = nil
            mapping.repeat = nil
            mapping.hold = nil
            mapping.scroll = nil
            startEventObservation()
        }
    }

    private func startEventObservation() {
        recordingObservationToken = try? EventTap.observe([
            .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp
        ], place: .tailAppendEventTap) { _, event in
            eventReceived(event)
        }

        if recordingObservationToken == nil {
            recording = false
            return
        }

        settingsState.recordedVirtualButtonEvent = nil
        settingsState.recordedButtonMappingEvent = nil

        // Observe Logitech control presses communicated via SettingsState
        // (no synthetic CGEvent needed — the HID++ protocol detects presses directly)
        recordedButtonCancellable = settingsState
            .$recordedVirtualButtonEvent
            .compactMap(\.self)
            .receive(on: DispatchQueue.main)
            .sink { event in
                virtualButtonReceived(event)
            }

        recordedMappingCancellable = settingsState
            .$recordedButtonMappingEvent
            .compactMap(\.self)
            .receive(on: DispatchQueue.main)
            .sink { event in
                recordedMappingReceived(event)
            }
    }

    private func cancelObservation() {
        recordedButtonCancellable?.cancel()
        recordedButtonCancellable = nil
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

    private func virtualButtonReceived(_ event: SettingsState.RecordedVirtualButtonEvent) {
        mapping.button = event.button
        mapping.modifierFlags = event.modifierFlags
        settingsState.recordedVirtualButtonEvent = nil
        recording = false
    }

    private func recordedMappingReceived(_ event: SettingsState.RecordedButtonMappingEvent) {
        mapping.button = event.button
        mapping.scroll = event.scroll
        mapping.modifierFlags = event.modifierFlags
        settingsState.recordedButtonMappingEvent = nil
        recording = false
    }

    private func eventReceived(_ event: CGEvent) -> CGEvent? {
        let result = ButtonMappingButtonRecordingEventHandler.record(event, into: &mapping)
        if result.stopsRecording {
            recording = false
        }

        return result.event
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
