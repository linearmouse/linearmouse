// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

extension ScrollingSettings {
    struct ScrollingModeSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            Section {
                Picker("Mode", selection: $state.scrollingMode) {
                    ForEach(ScrollingSettingsState.ScrollingMode.allCases) { scrollingMode in
                        Text(NSLocalizedString(scrollingMode.rawValue, comment: "")).tag(scrollingMode)
                    }
                }
                .modifier(PickerViewModifier())

                switch state.scrollingMode {
                case .accelerated:
                    Slider(value: $state.scrollingAcceleration,
                           in: 0.0 ... 10.0) {
                        Text("Acceleration")
                    } minimumValueLabel: {
                        Text("Linear")
                    } maximumValueLabel: {
                        Text("Accelerated")
                    }

                    Slider(value: $state.scrollingSpeed,
                           in: 0.0 ... 128.0) {
                        Text("Speed")
                    } minimumValueLabel: {
                        Text("Slower")
                    } maximumValueLabel: {
                        Text("Faster")
                    }

                case .byLines:
                    Slider(
                        value: $state.scrollingDistanceInLines,
                        in: 0 ... 10,
                        step: 1
                    ) {
                        Text("Distance")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("10")
                    }

                case .byPixels:
                    Slider(
                        value: $state.scrollingDistanceInPixels,
                        in: 0 ... 128
                    ) {
                        Text("Distance")
                    } minimumValueLabel: {
                        Text("0px")
                    } maximumValueLabel: {
                        Text("128px")
                    }
                }
            }
            .modifier(SectionViewModifier())
        }
    }
}
