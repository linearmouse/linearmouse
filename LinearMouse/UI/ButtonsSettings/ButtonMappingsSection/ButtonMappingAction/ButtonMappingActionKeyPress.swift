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

    @State private var recordingModifiers: NSEvent.ModifierFlags = []

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
            recordingModifiers = []
            let eventsOfInterest: NSEvent.EventTypeMask = [
                .flagsChanged,
                .keyDown
            ]
            recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: eventsOfInterest,
                                                                handler: eventReceived)
        }
    }

    private func buildKeysFromModifierFlags(_ modifierFlags: NSEvent.ModifierFlags) -> [Key] {
        var keys: [Key] = []
        if modifierFlags.contains(.control) {
            keys.append(modifierFlags.contains(.init(rawValue: UInt(NX_DEVICERCTLKEYMASK))) ? .controlRight : .control)
        }
        if modifierFlags.contains(.shift) {
            keys.append(modifierFlags.contains(.init(rawValue: UInt(NX_DEVICERSHIFTKEYMASK))) ? .shiftRight : .shift)
        }
        if modifierFlags.contains(.option) {
            keys.append(modifierFlags.contains(.init(rawValue: UInt(NX_DEVICERALTKEYMASK))) ? .optionRight : .option)
        }
        if modifierFlags.contains(.command) {
            keys.append(modifierFlags.contains(.init(rawValue: UInt(NX_DEVICERCMDKEYMASK))) ? .command : .commandRight)
        }
        return keys
    }

    private func eventReceived(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .flagsChanged:
            recordingModifiers.insert(event.modifierFlags)
            // If all modifier keys are released without and other key pressed,
            // just record the modifier keys.
            if event.modifierFlags.intersection([.control, .shift, .option, .command]).isEmpty {
                keys = buildKeysFromModifierFlags(recordingModifiers)
                recording = false
            }
        case .keyDown:
            let keyCodeResolver = KeyCodeResolver()
            guard let key = keyCodeResolver.key(from: event.keyCode) else {
                break
            }
            keys = buildKeysFromModifierFlags(event.modifierFlags) + [key]
            recording = false
        default:
            break
        }

        return nil
    }
}
