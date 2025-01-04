// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct ButtonMappingActionScroll: View {
    @Binding var action: Scheme.Buttons.Mapping.Action

    private var distance: Binding<Scheme.Scrolling.Distance> {
        Binding<Scheme.Scrolling.Distance>(
            get: {
                switch action {
                case let .arg1(.mouseWheelScrollUp(distance)):
                    return distance
                case let .arg1(.mouseWheelScrollDown(distance)):
                    return distance
                case let .arg1(.mouseWheelScrollLeft(distance)):
                    return distance
                case let .arg1(.mouseWheelScrollRight(distance)):
                    return distance
                default:
                    return .line(3)
                }
            },
            set: {
                switch action {
                case .arg1(.mouseWheelScrollUp):
                    action = .arg1(.mouseWheelScrollUp($0))
                case .arg1(.mouseWheelScrollDown):
                    action = .arg1(.mouseWheelScrollDown($0))
                case .arg1(.mouseWheelScrollLeft):
                    action = .arg1(.mouseWheelScrollLeft($0))
                case .arg1(.mouseWheelScrollRight):
                    action = .arg1(.mouseWheelScrollRight($0))
                default:
                    return
                }
            }
        )
    }

    var body: some View {
        DistanceInput(distance: distance)
    }
}

extension ButtonMappingActionScroll {
    struct DistanceInput: View {
        @Binding var distance: Scheme.Scrolling.Distance

        enum Mode: LocalizedStringKey, CaseIterable, Identifiable {
            var id: Self { self }

            case byLines = "By Lines"
            case byPixels = "By Pixels"
        }

        var mode: Binding<Mode> {
            Binding<Mode>(
                get: {
                    switch distance {
                    case .auto, .line:
                        return .byLines
                    case .pixel:
                        return .byPixels
                    }
                },
                set: {
                    switch $0 {
                    case .byLines:
                        distance = .line(3)
                    case .byPixels:
                        distance = .pixel(36)
                    }
                }
            )
        }

        var scrollingDistanceInLines: Binding<Double> {
            Binding<Double>(
                get: {
                    switch distance {
                    case let .line(value):
                        return Double(value)
                    default:
                        return 3
                    }
                },
                set: {
                    distance = .line(Int($0))
                }
            )
        }

        var scrollingDistanceInPixels: Binding<Double> {
            Binding<Double>(
                get: {
                    switch distance {
                    case let .pixel(value):
                        return value.asTruncatedDouble
                    default:
                        return 36
                    }
                },
                set: {
                    distance = .pixel(Decimal($0).rounded(1))
                }
            )
        }

        var body: some View {
            HStack {
                Picker("", selection: mode) {
                    ForEach(Mode.allCases) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .modifier(PickerViewModifier())
                .fixedSize()

                switch mode.wrappedValue {
                case .byLines:
                    Slider(
                        value: scrollingDistanceInLines,
                        in: 0 ... 10,
                        step: 1
                    ) {} minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("10")
                    }
                    .labelsHidden()

                case .byPixels:
                    Slider(
                        value: scrollingDistanceInPixels,
                        in: 0 ... 128
                    ) {} minimumValueLabel: {
                        Text("0px")
                    } maximumValueLabel: {
                        Text("128px")
                    }
                    .labelsHidden()
                }
            }
            .padding(.bottom)
        }
    }
}
