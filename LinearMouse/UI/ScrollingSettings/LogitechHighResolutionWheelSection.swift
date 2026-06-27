// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct LogitechHighResolutionWheelSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared

        var body: some View {
            Section {
                Toggle(isOn: $state.highResolutionWheel) {
                    withDescription {
                        Text("High resolution wheel")
                        Text("Use finer vertical wheel steps on supported Logitech mice.")
                    }
                }
            }
            .modifier(SectionViewModifier())
        }
    }
}
