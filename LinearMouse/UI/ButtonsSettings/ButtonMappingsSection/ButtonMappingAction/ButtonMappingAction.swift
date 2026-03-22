// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ButtonMappingAction: View {
    @Binding var action: Scheme.Buttons.Mapping.Action

    var body: some View {
        ButtonMappingActionPicker(actionType: $action.kind)
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
