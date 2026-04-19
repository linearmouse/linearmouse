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
            settingsState.beginVirtualButtonRecordingPreparation(for: logitechMonitorDeviceIDs())
        } else {
            settingsState.endVirtualButtonRecordingPreparation()
        }

        settingsState.recording = shouldRecord
    }

    private func recordingUpdated() {
        if let recordingObservationToken {
            recordingObservationToken.cancel()
            self.recordingObservationToken = nil
        }
        recordedButtonCancellable?.cancel()
        recordedButtonCancellable = nil

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
            .scrollWheel,
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

        // Observe Logitech control presses communicated via SettingsState
        // (no synthetic CGEvent needed — the HID++ protocol detects presses directly)
        recordedButtonCancellable = settingsState
            .$recordedVirtualButtonEvent
            .compactMap(\.self)
            .receive(on: DispatchQueue.main)
            .sink { event in
                virtualButtonReceived(event)
            }
    }

    private func cancelObservation() {
        recordedButtonCancellable?.cancel()
        recordedButtonCancellable = nil
    }

    private func logitechMonitorDeviceIDs() -> Set<Int32> {
        guard let currentDevice = DeviceState.shared.currentDeviceRef?.value,
              currentDevice.hasLogitechControlsMonitor else {
            return []
        }

        return [currentDevice.id]
    }

    private func virtualButtonReceived(_ event: SettingsState.RecordedVirtualButtonEvent) {
        mapping.button = event.button
        mapping.modifierFlags = event.modifierFlags
        settingsState.recordedVirtualButtonEvent = nil
        recording = false
    }

    private func eventReceived(_ event: CGEvent) -> CGEvent? {
        mapping.button = nil
        mapping.scroll = nil
        mapping.modifierFlags = event.flags

        switch event.type {
        case .flagsChanged:
            return nil

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            mapping.button = .mouse(Int(event.getIntegerValueField(.mouseEventButtonNumber)))
            return nil

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            mapping.button = .mouse(Int(event.getIntegerValueField(.mouseEventButtonNumber)))

        case .scrollWheel:
            let scrollWheelEventView = ScrollWheelEventView(event)
            if scrollWheelEventView.deltaYSignum < 0 {
                mapping.scroll = .down
            } else if scrollWheelEventView.deltaYSignum > 0 {
                mapping.scroll = .up
            } else if scrollWheelEventView.deltaXSignum < 0 {
                mapping.scroll = .right
            } else if scrollWheelEventView.deltaXSignum > 0 {
                mapping.scroll = .left
            }

        default:
            break
        }

        recording = false
        return nil
    }
}
