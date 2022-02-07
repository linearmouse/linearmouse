//
//  PreferencesView.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/12.
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject var defaults = AppDefaults.shared

    var body: some View {
        ToolbarTabView(tabs: [
            (
                imageName: "gearshape",
                label: "General",
                identifier: "general",
                content: {
                    AnyView(GeneralView())
                }
            ),
            (
                imageName: "cursorarrow.motionlines",
                label: "Cursor",
                identifier: "cursor",
                content: {
                    AnyView(CursorView())
                }
            ),
            (
                imageName: "command",
                label: "Modifier Keys",
                identifier: "modifier.keys",
                content: {
                    AnyView(ModifierKeysView())
                }
            )
        ])
    }
}

struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView()
    }
}
