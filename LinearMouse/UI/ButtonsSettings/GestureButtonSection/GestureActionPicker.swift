// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct GestureActionPicker: View {
    typealias GestureAction = Scheme.Buttons.Gesture.GestureAction

    let label: LocalizedStringKey
    @Binding var selection: GestureAction

    var body: some View {
        Picker(label, selection: $selection) {
            Text("None").tag(GestureAction.none)
            Text("Previous Space").tag(GestureAction.spaceLeft)
            Text("Next Space").tag(GestureAction.spaceRight)
            Text("Mission Control").tag(GestureAction.missionControl)
            Text("App Expose").tag(GestureAction.appExpose)
            Text("Show Desktop").tag(GestureAction.showDesktop)
            Text("Launchpad").tag(GestureAction.launchpad)
            Text("Play / pause").tag(GestureAction.mediaPlayPause)
            Text("Next").tag(GestureAction.mediaNext)
            Text("Previous").tag(GestureAction.mediaPrevious)
        }
        .modifier(PickerViewModifier())
    }
}
