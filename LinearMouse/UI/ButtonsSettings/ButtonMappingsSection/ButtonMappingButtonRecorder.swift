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
    @State private var recordedMappingCancellable: AnyCancellable?
    @State private var recordingSessionID: UUID?

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
        .onReceive(settingsState.$buttonMappingRecordingSession) { session in
            guard recording,
                  let recordingSessionID,
                  session?.id != recordingSessionID else {
                return
            }

            recording = false
        }
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
        if let recordingObservationToken {
            recordingObservationToken.cancel()
            self.recordingObservationToken = nil
        }
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
