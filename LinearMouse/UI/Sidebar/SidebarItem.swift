// MIT License
// Copyright (c) 2021-2024 LinearMouse

import SwiftUI

struct SidebarItem: View {
    @ObservedObject var settingsState = SettingsState.shared

    var id: SettingsState.Navigation
    var imageName: String?
    var text: LocalizedStringKey

    private var isActive: Bool {
        settingsState.navigation == id
    }

    var body: some View {
        Button {
            DispatchQueue.main.async {
                settingsState.navigation = id
            }
        } label: {
            HStack {
                if let imageName = imageName {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundColor(isActive ? .white : .accentColor)
                    Text(text)
                } else {
                    Text(text)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.accentColor.opacity(isActive ? 1 : 0))
        .cornerRadius(5)
        .foregroundColor(isActive ? .white : .primary)
    }
}
