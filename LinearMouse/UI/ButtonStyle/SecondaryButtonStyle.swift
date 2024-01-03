// MIT License
// Copyright (c) 2021-2024 LinearMouse

import SwiftUI

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyle.Configuration) -> some View {
        configuration.label
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(Color.gray.opacity(configuration.isPressed ? 0.3 : 0.1))
            .cornerRadius(3)
    }
}
