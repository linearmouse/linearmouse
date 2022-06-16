// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct SidebarItem<Destination>: View where Destination: View {
    var imageName: String?
    var text: LocalizedStringKey
    var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            if let imageName = imageName, #available(macOS 11.0, *) {
                Label(text, systemImage: imageName)
            } else {
                Text(text)
            }
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
