// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct SidebarItem: View {
    var imageName: String?
    var text: LocalizedStringKey

    var body: some View {
        if let imageName = imageName, #available(macOS 11.0, *) {
            Label(text, systemImage: imageName)
        } else {
            Text(text)
        }
    }
}
