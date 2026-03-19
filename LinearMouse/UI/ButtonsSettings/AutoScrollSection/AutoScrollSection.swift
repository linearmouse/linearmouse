// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct AutoScrollSection: View {
    @ObservedObject private var state: ButtonsSettingsState = .shared

    var body: some View {
        Section {
            Toggle(isOn: $state.autoScrollEnabled.animation()) {
                withDescription {
                    Text("Enable autoscroll")
                    Text(
                        "Scroll by moving away from an anchor point, similar to Windows middle-click autoscroll."
                    )
                }
            }

            if state.autoScrollEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Modes")
                        .font(.headline)

                    Toggle("Click once to toggle", isOn: $state.autoScrollToggleModeEnabled.animation())
                        .disabled(state.autoScrollToggleModeEnabled && !state.autoScrollHoldModeEnabled)

                    Toggle("Hold to scroll", isOn: $state.autoScrollHoldModeEnabled.animation())
                        .disabled(state.autoScrollHoldModeEnabled && !state.autoScrollToggleModeEnabled)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Trigger")
                        .font(.headline)

                    ButtonMappingButtonRecorder(mapping: state.autoScrollTriggerBinding)

                    if !state.autoScrollTriggerValid {
                        Text("Choose a mouse button trigger. Left click without modifier keys is not allowed.")
                            .foregroundColor(.red)
                            .controlSize(.small)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Speed")
                        Spacer()
                        Text(state.autoScrollSpeedText)
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $state.autoScrollSpeed, in: 0.3 ... 3.0, step: 0.1)
                }

                Toggle(isOn: $state.autoScrollPreserveNativeMiddleClick.animation()) {
                    withDescription {
                        Text("Preserve native middle-click on links and buttons")
                        Text(
                            "When using plain middle click, keep browser-style middle-click behavior on pressable elements instead of entering autoscroll."
                        )
                    }
                }
                .disabled(!state.autoScrollPreserveNativeMiddleClickAvailable)

                if !state.autoScrollUsesPlainMiddleClick {
                    Text(
                        "The native middle-click check only applies when the trigger is middle click without modifier keys."
                    )
                    .foregroundColor(.secondary)
                    .controlSize(.small)
                    .fixedSize(horizontal: false, vertical: true)
                } else if !state.autoScrollToggleModeEnabled {
                    Text("The native middle-click check only applies when click once to toggle is enabled.")
                        .foregroundColor(.secondary)
                        .controlSize(.small)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(modeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .modifier(SectionViewModifier())
    }

    private var modeDescription: LocalizedStringKey {
        let modes = Set(state.autoScrollModes)

        if modes == [.toggle] {
            return "Click the trigger once to enter autoscroll, move in any direction to scroll, then click again to exit."
        }

        if modes == [.hold] {
            return "Hold the trigger while moving to scroll, then release it to stop."
        }

        return "Click and release to keep autoscroll active, or hold and drag to scroll only until you let go."
    }
}
