// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ButtonMappingActionPicker: View {
    @Binding var action: Scheme.Buttons.Mapping.Action

    var body: some View {
        Picker("Action", selection: category) {
            ForEach(Scheme.Buttons.Mapping.Action.SimpleAction.allCases) { simpleAction in
                Text(String(describing: Scheme.Buttons.Mapping.Action.simpleAction(simpleAction)))
                    .tag(Category.simpleAction(simpleAction))
            }
        }
    }
}

extension ButtonMappingActionPicker {
    var category: Binding<Category> {
        Binding {
            switch action {
            case let .simpleAction(simpleAction):
                return .simpleAction(simpleAction)
            case .run:
                return .run
            case .mouseWheelScrollUp:
                return .mouseWheelScrollUp
            case .mouseWheelScrollDown:
                return .mouseWheelScrollDown
            case .mouseWheelScrollLeft:
                return .mouseWheelScrollLeft
            case .mouseWheelScrollRight:
                return .mouseWheelScrollRight
            }
        } set: { action in
            switch action {
            case let .simpleAction(simpleAction):
                self.action = .simpleAction(simpleAction)
            default:
                // TODO: TBD.
                break
            }
        }
    }

    enum Category: Hashable {
        case simpleAction(Scheme.Buttons.Mapping.Action.SimpleAction)
        case run
        case mouseWheelScrollUp, mouseWheelScrollDown, mouseWheelScrollLeft, mouseWheelScrollRight
    }
}
