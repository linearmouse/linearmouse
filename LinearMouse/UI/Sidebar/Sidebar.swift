// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct Sidebar: View {
    @ObservedObject var settingsState = SettingsState.shared

    var body: some View {
        List(selection: $settingsState.navigation) {
            SidebarItem(imageName: "Scrolling",
                        text: "Scrolling")
                .tag(SettingsState.Navigation.scrolling)

            SidebarItem(imageName: "Pointer",
                        text: "Pointer")
                .tag(SettingsState.Navigation.pointer)

            SidebarItem(imageName: "Buttons",
                        text: "Buttons")
                .tag(SettingsState.Navigation.buttons)

            SidebarItem(imageName: "Modifier Keys",
                        text: "Modifier Keys")
                .tag(SettingsState.Navigation.modifierKeys)

            Spacer()

            SidebarItem(imageName: "General",
                        text: "General")
                .tag(SettingsState.Navigation.general)
        }
        .listStyle(SidebarListStyle())
        .frame(width: 220)
    }
}
