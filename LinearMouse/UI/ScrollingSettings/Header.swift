// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct Header: View {
        var body: some View {
            HStack {
                Spacer()
                DirectionPicker()
                Spacer()
            }
            .padding(.top, 20)
        }
    }

    struct DirectionPicker: View {
        @ObservedObject var state = ScrollingSettingsState.shared

        var body: some View {
            Picker("", selection: directionBinding) {
                ForEach(Scheme.Scrolling.BidirectionalDirection.allCases) { direction in
                    Text(NSLocalizedString(direction.rawValue, comment: "")).tag(direction)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }

        private var directionBinding: Binding<Scheme.Scrolling.BidirectionalDirection> {
            Binding(
                get: { state.direction },
                set: { newValue in
                    DispatchQueue.main.async {
                        state.direction = newValue
                    }
                }
            )
        }
    }
}
