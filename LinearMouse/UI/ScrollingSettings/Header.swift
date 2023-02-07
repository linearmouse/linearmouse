// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

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
            Picker("", selection: $state.direction) {
                ForEach(Scheme.Scrolling.BidirectionalDirection.allCases) { direction in
                    Text(NSLocalizedString(direction.rawValue, comment: "")).tag(direction)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }
}
