// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct HelpButton: NSViewRepresentable {
    let action: () -> Void

    class Delegate: NSObject {
        let callback: () -> Void

        init(_ callback: @escaping () -> Void) {
            self.callback = callback
        }

        @objc func action() {
            callback()
        }
    }

    func makeCoordinator() -> Delegate {
        Delegate(action)
    }

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Delegate.action))
        button.bezelStyle = .helpButton
        return button
    }

    func updateNSView(_: NSButton, context _: NSViewRepresentableContext<Self>) {}
}
