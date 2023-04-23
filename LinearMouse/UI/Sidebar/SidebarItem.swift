// MIT License
// Copyright (c) 2021-2023 LinearMouse

import SwiftUI

struct SidebarItem: View {
    var imageName: String?
    var text: LocalizedStringKey

    var body: some View {
        if let imageName = imageName {
            if #available(macOS 11.0, *) {
                Label(text, image: imageName)
            } else {
                HStack {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                    Text(text)
                }
            }
        } else {
            Text(text)
        }
    }
}
