// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct GestureActionPicker: View {
    typealias GestureAction = Scheme.Buttons.Mapping.Action.Arg0

    let label: LocalizedStringKey
    @Binding var selection: GestureAction?

    var body: some View {
        Picker(label, selection: Binding(
            get: { selection ?? Optional.none },
            set: { selection = $0 }
        )) {
            Text("None").tag(GestureAction.none)
            Text("Previous Space").tag(GestureAction.missionControlSpaceLeft)
            Text("Next Space").tag(GestureAction.missionControlSpaceRight)
            Text("Mission Control").tag(GestureAction.missionControl)
            Text("App Expose").tag(GestureAction.appExpose)
            Text("Show Desktop").tag(GestureAction.showDesktop)
            Text("Launchpad").tag(GestureAction.launchpad)
        }
        .modifier(PickerViewModifier())
    }
}
