// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct GestureActionPicker: View {
    let label: LocalizedStringKey
    @Binding var selection: Scheme.Buttons.Gesture.GestureAction?

    var body: some View {
        Picker(label, selection: Binding(
            get: { selection ?? .none },
            set: { selection = $0 }
        )) {
            Text("None").tag(Scheme.Buttons.Gesture.GestureAction.none)
            Text("Previous Space").tag(Scheme.Buttons.Gesture.GestureAction.spaceLeft)
            Text("Next Space").tag(Scheme.Buttons.Gesture.GestureAction.spaceRight)
            Text("Mission Control").tag(Scheme.Buttons.Gesture.GestureAction.missionControl)
            Text("App Expose").tag(Scheme.Buttons.Gesture.GestureAction.appExpose)
            Text("Show Desktop").tag(Scheme.Buttons.Gesture.GestureAction.showDesktop)
            Text("Launchpad").tag(Scheme.Buttons.Gesture.GestureAction.launchpad)
        }
        .modifier(PickerViewModifier())
    }
}
