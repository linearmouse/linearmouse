// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ButtonMappingActionRun: View {
    @Binding var action: Scheme.Buttons.Mapping.Action

    var body: some View {
        TextField(String(""), text: $action.runCommand)
            .labelsHidden()
    }
}
