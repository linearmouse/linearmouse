// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ButtonMappingActionScroll: View {
    @Binding var action: Scheme.Buttons.Mapping.Action

    var body: some View {
        DistanceInput(distance: $action.scrollDistance)
    }
}

extension ButtonMappingActionScroll {
    struct DistanceInput: View {
        @Binding var distance: Scheme.Scrolling.Distance

        typealias Mode = Scheme.Scrolling.Distance.Mode

        var body: some View {
            HStack {
                Picker(String(""), selection: $distance.mode) {
                    ForEach(Mode.allCases) {
                        $0.label.tag($0)
                    }
                }
                .modifier(PickerViewModifier())
                .fixedSize()

                switch $distance.mode.wrappedValue {
                case .byLines:
                    Slider(
                        value: $distance.lineCount,
                        in: 0 ... 10,
                        step: 1
                    ) {} minimumValueLabel: {
                        Text(verbatim: "0")
                    } maximumValueLabel: {
                        Text(verbatim: "10")
                    }
                    .labelsHidden()

                case .byPixels:
                    Slider(
                        value: $distance.pixelCount,
                        in: 0 ... 128
                    ) {} minimumValueLabel: {
                        Text(verbatim: "0px")
                    } maximumValueLabel: {
                        Text(verbatim: "128px")
                    }
                    .labelsHidden()
                }
            }
            .padding(.bottom)
        }
    }
}
