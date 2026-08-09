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

                    HStack(spacing: 12) {
                        Toggle(
                            "Keep scrolling after release",
                            isOn: $state.autoScrollToggleModeEnabled.animation()
                        )
                        .toggleStyle(.checkbox)
                        .disabled(state.autoScrollToggleModeEnabled && !state.autoScrollHoldModeEnabled)

                        Spacer(minLength: 12)

                        if state.autoScrollToggleModeEnabled {
                            Picker(String(""), selection: $state.autoScrollToggleActivation) {
                                Text("Short press")
                                    .tag(Scheme.Buttons.AutoScroll.ToggleActivation.shortPress)
                                Text("Long press")
                                    .tag(Scheme.Buttons.AutoScroll.ToggleActivation.longPress)
                            }
                            .labelsHidden()
                            .fixedSize()
                            .modifier(PickerViewModifier())
                        }
                    }

                    Toggle("Hold to scroll", isOn: $state.autoScrollHoldModeEnabled.animation())
                        .toggleStyle(.checkbox)
                        .disabled(state.autoScrollHoldModeEnabled && !state.autoScrollToggleModeEnabled)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Trigger")
                        .font(.headline)

                    ButtonMappingButtonRecorder(
                        mapping: state.autoScrollTriggerBinding
                    )

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

                Text(modeDescription)
                    .settingsDescriptionStyle()
                    .padding(.top, 4)

                if state.autoScrollToggleModeEnabled,
                   state.autoScrollToggleActivation == .longPress {
                    Text("Uses the same long-press threshold as button mappings.")
                        .settingsDescriptionStyle()
                }
            }
        }
        .modifier(SectionViewModifier())
    }

    private var modeDescription: LocalizedStringKey {
        let modes = Set(state.autoScrollModes)

        if state.autoScrollToggleModeEnabled,
           state.autoScrollToggleActivation == .longPress {
            if modes == [.toggle] {
                return "Long-press the trigger to enter autoscroll, move in any direction to scroll, then click again to exit."
            }

            return "Long-press and release to keep autoscroll active, or drag beyond the dead zone to scroll only until you let go."
        }

        if modes == [.toggle] {
            return "Click the trigger once to enter autoscroll, move in any direction to scroll, then click again to exit."
        }

        if modes == [.hold] {
            return "Hold the trigger while moving to scroll, then release it to stop."
        }

        return "Click and release to keep autoscroll active, or hold and drag to scroll only until you let go."
    }
}
