// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct ButtonMappingActionRun: View {
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
        TextField(String(""), text: command)
            .labelsHidden()
    }
}
