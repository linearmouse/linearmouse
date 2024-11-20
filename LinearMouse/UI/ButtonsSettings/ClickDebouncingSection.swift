// MIT License
// Copyright (c) 2021-2024 LinearMouse

import SwiftUI

struct ClickDebouncingSection: View {
    @ObservedObject var state: ButtonsSettingsState = .shared

    var body: some View {
        Section {
            Toggle(isOn: $state.clickDebouncingEnabled.animation()) {
                withDescription {
                    Text("Debounce button clicks")
                    Text(
                        "Ignore rapid clicks within a certain time period."
                    )
                }
            }

            if state.clickDebouncingEnabled {
                HStack(spacing: 5) {
                    Slider(value: $state.clickDebouncingTimeoutInDouble,
                           in: 5 ... 500)
                        .labelsHidden()
                    TextField("",
                              value: $state.clickDebouncingTimeout,
                              formatter: state.clickDebouncingTimeoutFormatter)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("ms")
                }

                Toggle(isOn: $state.clickDebouncingResetTimerOnMouseUp.animation()) {
                    Text("Reset timer on mouse up")
                }

                VStack(alignment: .leading) {
                    HStack(spacing: 16) {
                        Toggle("Left button", isOn: state.clickDebouncingButtonEnabledBinding(for: .left))
                            .fixedSize()
                        Toggle("Right button", isOn: state.clickDebouncingButtonEnabledBinding(for: .right))
                            .fixedSize()
                        Toggle("Middle button", isOn: state.clickDebouncingButtonEnabledBinding(for: .center))
                            .fixedSize()
                    }
                    .toggleStyle(.checkbox)

                    HStack(spacing: 16) {
                        Toggle("Back button", isOn: state.clickDebouncingButtonEnabledBinding(for: .back))
                            .fixedSize()
                        Toggle("Forward button", isOn: state.clickDebouncingButtonEnabledBinding(for: .forward))
                            .fixedSize()
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
        .modifier(SectionViewModifier())
    }
}
