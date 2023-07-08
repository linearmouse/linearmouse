// MIT License
// Copyright (c) 2021-2023 LinearMouse

import KeyKit
import SwiftUI

struct ButtonMappingActionKeyPress: View {
    @Binding var action: Scheme.Buttons.Mapping.Action

    var body: some View {
        KeyboardShortcutRecorder(keys: keys)
    }

    private var keys: Binding<[Key]> {
        Binding<[Key]>(
            get: {
                guard case let .arg1(.keyPress(keys)) = action else {
                    return []
                }
                return keys
            },
            set: {
                action = .arg1(.keyPress($0))
            }
        )
    }
}

struct KeyboardShortcutRecorder: View {
    @Binding var keys: [Key]

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
        Button {
            recording.toggle()
        } label: {
            Group {
                if recording {
                    Text("Recording")
                        .foregroundColor(.orange)
                } else {
                    if keys.isEmpty {
                        Text("Click to record")
                    } else {
                        Text(keys.map(\.description).joined())
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func recordingUpdated() {
        if let recordingMonitor = recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
            self.recordingMonitor = nil
        }
        if recording {
            let eventsOfInterest: NSEvent.EventTypeMask = [
                .flagsChanged,
                .keyDown
            ]
            recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: eventsOfInterest,
                                                                handler: eventReceived)
        }
    }

    private func eventReceived(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            let keyCodeResolver = KeyCodeResolver()
            guard let key = keyCodeResolver.key(from: event.keyCode) else {
                break
            }

            var keys: [Key] = []
            let modifiers = event.modifierFlags
            if modifiers.contains(.control) {
                keys.append(modifiers.contains(.init(rawValue: UInt(NX_DEVICERCTLKEYMASK))) ? .controlRight : .control)
            }
            if modifiers.contains(.shift) {
                keys.append(modifiers.contains(.init(rawValue: UInt(NX_DEVICERSHIFTKEYMASK))) ? .shiftRight : .shift)
            }
            if modifiers.contains(.option) {
                keys.append(modifiers.contains(.init(rawValue: UInt(NX_DEVICERALTKEYMASK))) ? .optionRight : .option)
            }
            if modifiers.contains(.command) {
                keys.append(modifiers.contains(.init(rawValue: UInt(NX_DEVICERCMDKEYMASK))) ? .command : .commandRight)
            }
            keys.append(key)

            recording = false
            self.keys = keys
        default:
            break
        }

        return nil
    }
}
