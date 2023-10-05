// MIT License
// Copyright (c) 2021-2023 LinearMouse

import SwiftUI

struct DisplayPicker: View {
    @ObservedObject var state: DisplayPickerState = .shared
    @Binding var selectedDisplay: String

    var body: some View {
        Picker("Configure for", selection: $selectedDisplay) {
            Text("All Displays").frame(minHeight: 24).tag("")
            ForEach(state.allDisplays, id: \.self) { display in
                Text(display).tag(display)
            }
        }
    }
}
