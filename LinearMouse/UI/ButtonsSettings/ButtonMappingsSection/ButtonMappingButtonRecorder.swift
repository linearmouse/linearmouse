// MIT License
// Copyright (c) 2021-2025 LinearMouse

import ObservationToken
import SwiftUI

struct ButtonMappingButtonRecorder: View {
    @Binding var mapping: Scheme.Buttons.Mapping

    var autoStartRecording = false

    @State private var recording = false {
        didSet {
            guard oldValue != recording else {
                return
            }
            SettingsState.shared.recording = recording
            recordingUpdated()
        }
    }

    @State private var recordingObservationToken: ObservationToken?

    var body: some View {
        Button {
            recording.toggle()
        } label: {
            Group {
                if recording {
                    ButtonMappingButtonDescription(mapping: mapping, showPartial: true) {
                        Text("Recording")
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
            if autoStartRecording {
                recording = true
            }
        }
        .onDisappear {
            recording = false
        }
    }

    private func recordingUpdated() {
        if let recordingObservationToken {
            recordingObservationToken.cancel()
            self.recordingObservationToken = nil
        }

        if recording {
            mapping.modifierFlags = []
            mapping.button = nil
            mapping.repeat = nil
            mapping.scroll = nil

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
            }
        }
    }

    private func eventReceived(_ event: CGEvent) -> CGEvent? {
        mapping.button = nil
        mapping.scroll = nil
        mapping.modifierFlags = .init(rawValue: UInt64(event.flags.rawValue))

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
