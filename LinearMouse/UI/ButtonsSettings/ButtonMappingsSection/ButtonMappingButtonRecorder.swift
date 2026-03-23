// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import ObservationToken
import SwiftUI

struct ButtonMappingButtonRecorder: View {
    @Binding var mapping: Scheme.Buttons.Mapping

    var autoStartRecording = false
    var keepGlobalRecordingActiveWhilePresented = false

    @State private var recording = false {
        didSet {
            guard oldValue != recording else {
                return
            }
            updateSharedRecordingState()
            recordingUpdated()
        }
    }

    @State private var divertReady = false
    @State private var recordingObservationToken: ObservationToken?
    @State private var divertReadyCancellable: AnyCancellable?
    @State private var logitechControlCancellable: AnyCancellable?

    private var waitingForDivert: Bool {
        hasLogitechDevice() && !divertReady
    }

    var body: some View {
        Button {
            recording.toggle()
        } label: {
            Group {
                if recording {
                    if waitingForDivert {
                        Text("Waiting for device…")
                    } else {
                        ButtonMappingButtonDescription(mapping: mapping, showPartial: true) {
                            Text("Recording")
                        }
                        .foregroundColor(.orange)
                    }
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
            beginDivertIfNeeded()
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
        let shouldRecord = force ?? (recording || keepGlobalRecordingActiveWhilePresented)
        SettingsState.shared.recording = shouldRecord
        if !shouldRecord {
            SettingsState.shared.recordingDivertReady = false
            divertReady = false
        }
    }

    /// Start listening for divert readiness as soon as the view appears,
    /// so the diversion completes before the user starts recording.
    private func beginDivertIfNeeded() {
        guard hasLogitechDevice(), divertReadyCancellable == nil else {
            return
        }

        SettingsState.shared.recordingDivertReady = false
        divertReadyCancellable = SettingsState.shared
            .$recordingDivertReady
            .filter(\.self)
            .first()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                divertReady = true
                if recording {
                    startEventObservation()
                }
            }
    }

    private func recordingUpdated() {
        if let recordingObservationToken {
            recordingObservationToken.cancel()
            self.recordingObservationToken = nil
        }
        logitechControlCancellable?.cancel()
        logitechControlCancellable = nil

        if recording {
            mapping.modifierFlags = []
            mapping.button = nil
            mapping.logiButton = nil
            mapping.repeat = nil
            mapping.scroll = nil

            if !waitingForDivert {
                startEventObservation()
            }
            // Otherwise, the divertReady callback will call startEventObservation.
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

        // Observe Logitech control presses communicated via SettingsState
        // (no synthetic CGEvent needed — the HID++ protocol detects presses directly)
        logitechControlCancellable = SettingsState.shared
            .$recordedLogitechControl
            .compactMap(\.self)
            .receive(on: DispatchQueue.main)
            .sink { identity in
                logitechControlReceived(identity)
            }
    }

    private func cancelObservation() {
        divertReadyCancellable?.cancel()
        divertReadyCancellable = nil
        logitechControlCancellable?.cancel()
        logitechControlCancellable = nil
        divertReady = false
    }

    private func hasLogitechDevice() -> Bool {
        DeviceManager.shared.devices.contains(where: \.hasLogitechControlsMonitor)
    }

    private func logitechControlReceived(_ identity: LogitechControlIdentity) {
        mapping.button = LogitechHIDPPDeviceMetadataProvider.ReprogControlsV4.reservedVirtualButtonNumber
        mapping.logiButton = identity
        mapping.rawModifierFlags = ModifierState.normalize(ModifierState.shared.currentFlags)
        SettingsState.shared.recordedLogitechControl = nil
        recording = false
    }

    private func eventReceived(_ event: CGEvent) -> CGEvent? {
        mapping.button = nil
        mapping.scroll = nil
        mapping.rawModifierFlags = ModifierState.normalize(event.flags)

        switch event.type {
        case .flagsChanged:
            return nil

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            mapping.button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            return nil

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            mapping.button = Int(event.getIntegerValueField(.mouseEventButtonNumber))

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
