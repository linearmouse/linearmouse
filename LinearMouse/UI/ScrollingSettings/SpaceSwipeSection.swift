// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct SpaceSwipeSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            Section {
                Toggle(isOn: $state.spaceSwipe) {
                    withDescription {
                        Text("Swipe between spaces")
                        Text(
                            "Spaces follow the wheel like a trackpad swipe and snap to the nearest one when the wheel stops. Horizontal scrolling no longer scrolls content."
                        )
                    }
                }

                if state.spaceSwipe {
                    HStack(alignment: .firstTextBaseline) {
                        Slider(
                            value: $state.spaceSwipeDistance,
                            in: 4 ... 60,
                            step: 1
                        ) {
                            labelWithDescription {
                                Text("Wheel steps per space")
                                Text(verbatim: "(4–60)")
                            }
                        } minimumValueLabel: {
                            Text("Fast")
                        } maximumValueLabel: {
                            Text("Slow")
                        }
                        TextField(
                            String(""),
                            value: $state.spaceSwipeDistance,
                            formatter: state.spaceSwipeDistanceFormatter
                        )
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    }
                }
            }
            .modifier(SectionViewModifier())
        }
    }
}
