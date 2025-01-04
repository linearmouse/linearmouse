// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct ButtonMappingAction: View {
    @Binding var action: Scheme.Buttons.Mapping.Action

    var body: some View {
        ButtonMappingActionPicker(actionType: actionType)
            .equatable()

        switch action {
        case .arg0:
            EmptyView()
        case .arg1(.run):
            ButtonMappingActionRun(action: $action)
        case .arg1(.mouseWheelScrollUp),
             .arg1(.mouseWheelScrollDown),
             .arg1(.mouseWheelScrollLeft),
             .arg1(.mouseWheelScrollRight):
            ButtonMappingActionScroll(action: $action)
        case .arg1(.keyPress):
            ButtonMappingActionKeyPress(action: $action)
        }
    }
}

extension ButtonMappingAction {
    var actionType: Binding<ButtonMappingActionPicker.ActionType> {
        Binding {
            switch action {
            case let .arg0(value):
                return .arg0(value)
            case .arg1(.run):
                return .run
            case .arg1(.mouseWheelScrollUp):
                return .mouseWheelScrollUp
            case .arg1(.mouseWheelScrollDown):
                return .mouseWheelScrollDown
            case .arg1(.mouseWheelScrollLeft):
                return .mouseWheelScrollLeft
            case .arg1(.mouseWheelScrollRight):
                return .mouseWheelScrollRight
            case .arg1(.keyPress):
                return .keyPress
            }
        } set: { action in
            switch action {
            case let .arg0(value):
                self.action = .arg0(value)
            case .run:
                self.action = .arg1(.run(""))
            case .mouseWheelScrollUp:
                self.action = .arg1(.mouseWheelScrollUp(.line(3)))
            case .mouseWheelScrollDown:
                self.action = .arg1(.mouseWheelScrollDown(.line(3)))
            case .mouseWheelScrollLeft:
                self.action = .arg1(.mouseWheelScrollLeft(.line(3)))
            case .mouseWheelScrollRight:
                self.action = .arg1(.mouseWheelScrollRight(.line(3)))
            case .keyPress:
                self.action = .arg1(.keyPress([]))
            }
        }
    }
}
