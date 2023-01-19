// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct Sidebar: View {
    @ObservedObject var settingsState = SettingsState.shared

    var body: some View {
        List(selection: $settingsState.navigation) {
            SidebarItem(imageName: "arrow.up.and.down",
                        text: "Scrolling")
                .tag(SettingsState.Navigation.scrolling)

            SidebarItem(imageName: "cursorarrow.motionlines",
                        text: "Pointer")
                .tag(SettingsState.Navigation.pointer)

            SidebarItem(imageName: "computermouse.fill",
                        text: "Buttons")
                .tag(SettingsState.Navigation.buttons)

            SidebarItem(imageName: "command",
                        text: "Modifier Keys")
                .tag(SettingsState.Navigation.modifierKeys)

            Spacer()

            SidebarItem(imageName: "gearshape.fill",
                        text: "General")
                .tag(SettingsState.Navigation.general)
        }
        .listStyle(SidebarListStyle())
        .frame(width: 220)
    }
}
