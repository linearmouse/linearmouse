// MIT License
// Copyright (c) 2021-2023 LinearMouse

import KeyKit
import ObservationToken
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

    @State private var recordingObservationToken: ObservationToken?

    @State private var recordingModifiers: CGEventFlags = []

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
        recordingObservationToken = nil

        if recording {
            recordingModifiers = []

            recordingObservationToken = try? EventTap.observe([
                .flagsChanged,
                .keyDown
            ]) { _, event in
                eventReceived(event)
            }

            if recordingObservationToken == nil {
                recording = false
            }
        }
    }

    private func buildKeysFromModifierFlags(_ modifierFlags: CGEventFlags) -> [Key] {
        var keys: [Key] = []

        if modifierFlags.contains(.maskControl) {
            keys
                .append(modifierFlags
                    .contains(.init(rawValue: UInt64(NX_DEVICERCTLKEYMASK))) ? .controlRight : .control)
        }

        if modifierFlags.contains(.maskShift) {
            keys.append(modifierFlags.contains(.init(rawValue: UInt64(NX_DEVICERSHIFTKEYMASK))) ? .shiftRight : .shift)
        }

        if modifierFlags.contains(.maskAlternate) {
            keys.append(modifierFlags.contains(.init(rawValue: UInt64(NX_DEVICERALTKEYMASK))) ? .optionRight : .option)
        }

        if modifierFlags.contains(.maskCommand) {
            keys
                .append(modifierFlags
                    .contains(.init(rawValue: UInt64(NX_DEVICERCMDKEYMASK))) ? .command : .commandRight)
        }

        return keys
    }

    private func eventReceived(_ event: CGEvent) -> CGEvent? {
        switch event.type {
        case .flagsChanged:
            recordingModifiers.insert(event.flags)

            // If all modifier keys are released without and other key pressed,
            // just record the modifier keys.
            if event.flags.intersection([.maskControl, .maskShift, .maskAlternate, .maskCommand]).isEmpty {
                keys = buildKeysFromModifierFlags(recordingModifiers)
                recording = false
            }

        case .keyDown:
            let keyCodeResolver = KeyCodeResolver()
            guard let key = keyCodeResolver.key(from: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)))
            else {
                break
            }
            keys = buildKeysFromModifierFlags(event.flags) + [key]
            recording = false

        default:
            break
        }

        return nil
    }
}
