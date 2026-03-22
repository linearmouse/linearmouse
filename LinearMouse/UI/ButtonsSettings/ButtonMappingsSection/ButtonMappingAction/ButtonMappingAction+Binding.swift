// MIT License
// Copyright (c) 2021-2026 LinearMouse

import KeyKit
import SwiftUI

extension Binding where Value == Scheme.Buttons.Mapping.Action {
    var kind: Binding<Scheme.Buttons.Mapping.Action.Kind> {
        Binding<Scheme.Buttons.Mapping.Action.Kind>(
            get: {
                wrappedValue.kind
            },
            set: {
                wrappedValue = Scheme.Buttons.Mapping.Action(kind: $0)
            }
        )
    }

    var runCommand: Binding<String> {
        Binding<String>(
            get: {
                guard case let .arg1(.run(command)) = wrappedValue else {
                    return ""
                }

                return command
            },
            set: {
                wrappedValue = .arg1(.run($0))
            }
        )
    }

    var scrollDistance: Binding<Scheme.Scrolling.Distance> {
        Binding<Scheme.Scrolling.Distance>(
            get: {
                switch wrappedValue {
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
                switch wrappedValue {
                case .arg1(.mouseWheelScrollUp):
                    wrappedValue = .arg1(.mouseWheelScrollUp($0))
                case .arg1(.mouseWheelScrollDown):
                    wrappedValue = .arg1(.mouseWheelScrollDown($0))
                case .arg1(.mouseWheelScrollLeft):
                    wrappedValue = .arg1(.mouseWheelScrollLeft($0))
                case .arg1(.mouseWheelScrollRight):
                    wrappedValue = .arg1(.mouseWheelScrollRight($0))
                default:
                    return
                }
            }
        )
    }

    var keyPressKeys: Binding<[Key]> {
        Binding<[Key]>(
            get: {
                guard case let .arg1(.keyPress(keys)) = wrappedValue else {
                    return []
                }

                return keys
            },
            set: {
                wrappedValue = .arg1(.keyPress($0))
            }
        )
    }
}

extension Scheme.Buttons.Mapping.Action.Kind {
    @ViewBuilder
    var label: some View {
        switch self {
        case let .arg0(value):
            Text(value.description.capitalized)
        case .run:
            Text("Run shell command…")
        case .mouseWheelScrollUp:
            Text("Scroll up…")
        case .mouseWheelScrollDown:
            Text("Scroll down…")
        case .mouseWheelScrollLeft:
            Text("Scroll left…")
        case .mouseWheelScrollRight:
            Text("Scroll right…")
        case .keyPress:
            Text("Keyboard shortcut…")
        }
    }
}
