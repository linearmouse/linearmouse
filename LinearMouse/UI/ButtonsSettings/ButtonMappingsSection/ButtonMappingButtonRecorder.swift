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
            recordingUpdated()
        }
    }

    @State private var recordingMonitor: Any?

    var body: some View {
        Button(action: { recording.toggle() }) {
            Group {
                if recording {
                    Text("Recording")
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
            let eventsOfInterest: NSEvent.EventTypeMask = [
                .leftMouseDown,
                .rightMouseDown,
                .otherMouseDown,
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
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
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
