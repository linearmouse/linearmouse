// MIT License
// Copyright (c) 2021-2023 LinearMouse

import SwiftUI

struct ButtonMappingActionPickerRun: View {
    @Binding var action: Scheme.Buttons.Mapping.Action

    private var command: Binding<String> {
        Binding<String>(
            get: {
                guard case let .arg1(.run(command)) = action else {
                    return ""
                }
                return command
            },
            set: {
                action = .arg1(.run($0))
            }
        )
    }

    var body: some View {
        TextField("", text: command)
            .labelsHidden()
    }
}
