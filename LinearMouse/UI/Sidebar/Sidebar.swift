//
//  Sidebar.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/6/15.
//

import Introspect
import SwiftUI

struct Sidebar: View {
    @State var selection: Tag? = .general

    enum Tag {
        case general, cursor, modifierKeys
    }

    var body: some View {
        List(selection: $selection) {
            SidebarItem(imageName: "gearshape.fill",
                        text: "General") {
                GeneralView()
            }
            .tag(Tag.general)

            SidebarItem(imageName: "cursorarrow.motionlines",
                        text: "Cursor") {
                CursorView()
            }
            .tag(Tag.cursor)

            SidebarItem(imageName: "command",
                        text: "Modifier Keys") {
                ModifierKeysView()
            }
            .tag(Tag.modifierKeys)
        }
        .padding(.top)
        .listStyle(SidebarListStyle())
        .buttonStyle(PlainButtonStyle())
        .frame(minWidth: 200, maxWidth: .infinity)
        .preventSidebarCollapse()
    }
}

struct Sidebar_Previews: PreviewProvider {
    static var previews: some View {
        Sidebar()
    }
}
