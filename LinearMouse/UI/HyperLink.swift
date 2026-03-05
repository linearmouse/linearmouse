// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct HyperLink<Content: View>: View {
    var url: URL
    let content: () -> Content

    init(
        _ url: URL,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.url = url
        self.content = content
    }

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            content()
        }
        .foregroundColor(.accentColor)
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
