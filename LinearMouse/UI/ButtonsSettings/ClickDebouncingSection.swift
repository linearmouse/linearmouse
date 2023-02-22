// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ClickDebouncingSection: View {
    @ObservedObject var state: ButtonsSettingsState = .shared

    var body: some View {
        Section {
            Toggle(isOn: $state.debounceClicksEnabled.animation()) {
                withDescription {
                    Text("Debounce button clicks")
                    Text(
                        "Ignore rapid clicks within a certain duration."
                    )
                }
            }

            if state.debounceClicksEnabled {
                HStack(spacing: 5) {
                    Slider(value: $state.debounceClicksInDouble,
                           in: 10 ... 500)
                        .labelsHidden()
                    TextField("",
                              value: $state.debounceClicks,
                              formatter: state.debounceClicksFormatter)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("ms")
                }
            }
        }
        .modifier(SectionViewModifier())
    }
}
