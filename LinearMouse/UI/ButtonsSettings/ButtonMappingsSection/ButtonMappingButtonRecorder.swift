// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

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

    @State private var recordingMonitor: Any?

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
        if let recordingMonitor = recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
            self.recordingMonitor = nil
        }
        if recording {
            mapping.modifierFlags = []
            mapping.button = nil
            mapping.repeat = nil
            mapping.scroll = nil
            let eventsOfInterest: NSEvent.EventTypeMask = [
                .flagsChanged,
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown,
                .leftMouseUp,
                .rightMouseUp,
                .otherMouseUp,
                .scrollWheel
            ]
            recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: eventsOfInterest) { event in
                eventReceived(event)
            }
        }
    }

    private func eventReceived(_ event: NSEvent) -> NSEvent? {
        mapping.button = nil
        mapping.scroll = nil
        mapping.modifierFlags = .init(rawValue: UInt64(event.modifierFlags.rawValue))

        switch event.type {
        case .flagsChanged:
            return nil

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            mapping.button = event.buttonNumber
            return nil

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            mapping.button = event.buttonNumber

        case .scrollWheel:
            if event.deltaY > 0 {
                mapping.scroll = .up
            } else if event.deltaY < 0 {
                mapping.scroll = .down
            } else if event.deltaX > 0 {
                mapping.scroll = .left
            } else if event.deltaX < 0 {
                mapping.scroll = .right
            }

        default:
            break
        }

        recording = false
        return nil
    }
}
