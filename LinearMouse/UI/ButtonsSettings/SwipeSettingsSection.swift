// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct SwipeSettingsSection: View {
    @ObservedObject private var state = ButtonsSettingsState.shared

    private static let thresholdFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    var body: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Slider(
                    value: $state.swipeThreshold,
                    in: Scheme.Buttons.Swipe.thresholdRange,
                    step: 5
                ) {
                    Text("Swipe trigger distance")
                }
                DeferredNumberField(
                    value: $state.swipeThreshold,
                    formatter: Self.thresholdFormatter,
                    range: Scheme.Buttons.Swipe.thresholdRange
                )
                .frame(width: 72)
                .accessibility(label: Text("Swipe trigger distance"))
                Text("pixels")
                    .foregroundColor(.secondary)
            }

            Toggle("Lock pointer during swipes", isOn: $state.lockPointerDuringSwipe)

            Button("Reset") {
                state.resetSwipeSettings()
            }
            .disabled(!state.hasSwipeSettingsOverride)
        } header: {
            Text("Swipe Settings")
        }
        .modifier(SectionViewModifier())
    }
}
