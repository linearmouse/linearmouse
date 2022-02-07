//
//  ToolbarTabView.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/2/6.
//

import SwiftUI

// https://stackoverflow.com/a/58829155/3410836
struct ToolbarTabView: NSViewControllerRepresentable {
    let tabs: [(imageName: String, label: String, identifier: String, content: () -> AnyView)]

    init(tabs: [(imageName: String, label: String, identifier: String, content: () -> AnyView)]) {
        self.tabs = tabs
    }

    func makeNSViewController(context: NSViewControllerRepresentableContext<ToolbarTabView>) -> NSTabViewController {
        let vc = NSTabViewController()
        vc.tabStyle = .toolbar

        for item in tabs {
            let t = NSTabViewItem(viewController: NSHostingController(rootView: item.content()))
            if #available(macOS 11.0, *) {
                t.image = NSImage(systemSymbolName: item.imageName, accessibilityDescription: nil)
            }
            t.label = NSLocalizedString(item.label, comment: "")
            t.identifier = item.identifier
            vc.addTabViewItem(t)
        }

        return vc
    }

    func updateNSViewController(_ nsViewController: NSTabViewController, context: NSViewControllerRepresentableContext<ToolbarTabView>) {
    }

    typealias NSViewControllerType = NSTabViewController
}
