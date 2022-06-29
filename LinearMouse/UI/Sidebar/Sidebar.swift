// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Introspect
import SwiftUI

struct Sidebar: View {
    @State var selection: Tag? = .wheel

    enum Tag {
        case wheel, cursor, buttons, modifierKeys, general
    }

    var body: some View {
        List(selection: $selection) {
            SidebarItem(imageName: "arrow.up.and.down",
                        text: "Scrolling") {
                ScrollingSettings()
            }
            .tag(Tag.wheel)

            SidebarItem(imageName: "cursorarrow.motionlines",
                        text: "Pointer") {
                PointerSettings()
            }
            .tag(Tag.cursor)

            SidebarItem(imageName: "computermouse.fill",
                        text: "Buttons") {
                ButtonsSettings()
            }
            .tag(Tag.buttons)

            SidebarItem(imageName: "command",
                        text: "Modifier Keys") {
                ModifierKeysSettings()
            }
            .tag(Tag.modifierKeys)

            Spacer()

            SidebarItem(imageName: "gearshape.fill",
                        text: "General") {
                GeneralSettings()
            }
            .tag(Tag.general)
        }
        .padding(.top)
        .listStyle(SidebarListStyle())
        .frame(minWidth: 200, maxWidth: .infinity)
        .preventSidebarCollapse()
    }
}

struct Sidebar_Previews: PreviewProvider {
    static var previews: some View {
        Sidebar()
    }
}
