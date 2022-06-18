//
//  DeviceButtonStyle.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/6/18.
//

import SwiftUI

struct DeviceButtonStyle: ButtonStyle {
    var isActive: Bool

    private var textColor: Color {
        isActive ? .accentColor : .primary
    }

    private var backgroundColor: Color {
        backgroundColorPressed.opacity(0.3)
    }

    private var backgroundColorPressed: Color {
        (isActive ? Color.accentColor : .gray).opacity(0.3)
    }

    func makeBody(configuration: Configuration) -> some View {
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
