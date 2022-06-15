//
//  SidebarItem.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/6/15.
//

import SwiftUI

struct SidebarItem<Destination>: View where Destination: View {
    var imageName: String?
    var text: String
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
