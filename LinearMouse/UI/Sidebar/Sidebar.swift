// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct Sidebar: View {
    @ObservedObject var state = SettingsState.shared

    var body: some View {
        List(SettingsState.Navigation.allCases, id: \.self, selection: $state.navigation) { item in
            SidebarRow(item: item)
                .tag(item)
        }
        .listStyle(SidebarListStyle())
    }
}

private struct SidebarRow: View {
    let item: SettingsState.Navigation

    var body: some View {
        if #available(macOS 11.0, *) {
            Label {
                Text(item.title)
            } icon: {
                Image(item.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            }
        } else {
            HStack {
                Image(item.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                Text(item.title)
            }
        }
    }
}
