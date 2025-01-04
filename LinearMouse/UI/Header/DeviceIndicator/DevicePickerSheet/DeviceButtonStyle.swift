// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct DeviceButtonStyle: ButtonStyle {
    var isSelected: Bool

    private var textColor: Color {
        isSelected ? .accentColor : .primary
    }

    private var backgroundColor: Color {
        backgroundColorPressed.opacity(0.2)
    }

    private var backgroundColorPressed: Color {
        (isSelected ? Color.accentColor : .gray).opacity(0.2)
    }

    func makeBody(configuration: ButtonStyle.Configuration) -> some View {
        configuration.label
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .foregroundColor(.white)
            .colorMultiply(textColor)
            .background(configuration.isPressed ? backgroundColorPressed : backgroundColor)
            .cornerRadius(5)
            .frame(maxWidth: .infinity, minHeight: 25)
    }
}
