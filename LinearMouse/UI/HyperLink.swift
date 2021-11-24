//
//  HyperLink.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/12.
//

import SwiftUI

struct HyperLink<Content>: View where Content: View {
    var url: URL
    let content: () -> Content

    init(_ url: URL,
         @ViewBuilder content: @escaping () -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        Button(action: {
            NSWorkspace.shared.open(url)
        }) {
            content()
        }
        .foregroundColor(.accentColor)
        .buttonStyle(PlainButtonStyle())
        .onHover(perform: { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        })
    }
}

struct HyperLink_Previews: PreviewProvider {
    static var previews: some View {
        HyperLink(URL(string: "https://linearmouse.lujjjh.com/")!) {
            Text("LinearMouse")
        }
    }
}
