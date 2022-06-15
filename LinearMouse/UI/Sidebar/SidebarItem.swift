// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct SidebarItem<Destination>: View where Destination: View {
    var imageName: String?
    var text: LocalizedStringKey
    var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            if let imageName = imageName {
                if #available(macOS 11.0, *) {
                    Image(systemName: imageName)
                }
            }
            Text(text)
        }
    }
}

struct SidebarItem_Previews: PreviewProvider {
    static var previews: some View {
        SidebarItem(imageName: "gear", text: "General") {
            Text("Destination")
        }
    }
}
