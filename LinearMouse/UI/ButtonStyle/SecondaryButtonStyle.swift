// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyle.Configuration) -> some View {
        if #available(macOS 26.0, *) {
            configuration.label
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .glassEffect(.regular.interactive())
        } else {
            configuration.label
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(Color.gray.opacity(configuration.isPressed ? 0.3 : 0.1))
                .cornerRadius(3)
        }
    }
}
