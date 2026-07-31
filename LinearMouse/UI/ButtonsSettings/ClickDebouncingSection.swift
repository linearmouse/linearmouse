// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ClickDebouncingSection: View {
    @ObservedObject var state: ButtonsSettingsState = .shared

    var body: some View {
        Section {
            Toggle(isOn: $state.clickDebouncingEnabled.animation()) {
                withDescription {
                    Text("Debounce button clicks")
                    Text(
                        "Suppress unintended clicks caused by a worn or noisy mouse switch."
                    )
                }
            }

            if state.clickDebouncingEnabled {
                Picker("Debouncing method", selection: $state.clickDebouncingMode.animation()) {
                    Text("Classic").tag(Scheme.Buttons.ClickDebouncing.Mode.legacy)
                    Text("libinput (Beta)").tag(Scheme.Buttons.ClickDebouncing.Mode.libinput)
                }
                .pickerStyle(.segmented)

                if state.clickDebouncingMode == .legacy {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Debounce interval")

                        HStack(spacing: 5) {
                            Slider(
                                value: $state.clickDebouncingTimeoutInDouble,
                                in: 5 ... 500
                            )
                            .labelsHidden()
                            TextField(
                                String(""),
                                value: $state.clickDebouncingTimeout,
                                formatter: state.clickDebouncingTimeoutFormatter
                            )
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            Text("ms")
                        }
                    }

                    Toggle(isOn: $state.clickDebouncingResetTimerOnMouseUp.animation()) {
                        Text("Reset timer on mouse up")
                    }

                    classicButtonPicker
                }
            }
        }
        .modifier(SectionViewModifier())
    }

    @ViewBuilder private var classicButtonPicker: some View {
        if #available(macOS 11.0, *) {
            HStack {
                Text("Apply to")

                Spacer()

                Menu {
                    buttonMenuToggle("Left button", for: .left)
                    buttonMenuToggle("Right button", for: .right)
                    buttonMenuToggle("Middle button", for: .center)
                    buttonMenuToggle("Back button", for: .back)
                    buttonMenuToggle("Forward button", for: .forward)
                } label: {
                    Text(buttonSelectionSummary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Apply to")

                HStack(spacing: 16) {
                    buttonCheckbox("Left button", for: .left)
                    buttonCheckbox("Right button", for: .right)
                    buttonCheckbox("Middle button", for: .center)
                }

                HStack(spacing: 16) {
                    buttonCheckbox("Back button", for: .back)
                    buttonCheckbox("Forward button", for: .forward)
                }
            }
        }

        if !state.clickDebouncingHasSelectedButtons {
            Text("Select at least one mouse button.")
                .foregroundColor(.red)
                .controlSize(.small)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func buttonMenuToggle(_ title: LocalizedStringKey, for button: CGMouseButton) -> some View {
        Toggle(title, isOn: state.clickDebouncingButtonEnabledBinding(for: button))
            .disabled(state.clickDebouncingButtonIsOnlySelection(button))
    }

    private func buttonCheckbox(_ title: LocalizedStringKey, for button: CGMouseButton) -> some View {
        Toggle(title, isOn: state.clickDebouncingButtonEnabledBinding(for: button))
            .toggleStyle(.checkbox)
            .fixedSize()
            .disabled(state.clickDebouncingButtonIsOnlySelection(button))
    }

    private var buttonSelectionSummary: LocalizedStringKey {
        let buttons = state.clickDebouncingSelectedButtons

        if buttons.isEmpty {
            return "No buttons"
        }

        if buttons.count == Scheme.Buttons.ClickDebouncing.standardButtons.count,
           Scheme.Buttons.ClickDebouncing.standardButtons.allSatisfy(buttons.contains) {
            return "All buttons"
        }

        if buttons.count == 1, let button = buttons.first {
            switch button {
            case .left:
                return "Left button"
            case .right:
                return "Right button"
            case .center:
                return "Middle button"
            case .back:
                return "Back button"
            case .forward:
                return "Forward button"
            default:
                break
            }
        }

        return "Multiple buttons"
    }
}
