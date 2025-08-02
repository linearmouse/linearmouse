// MIT License
// Copyright (c) 2021-2025 LinearMouse

import AppKit
import Combine
import SwiftUI

class ContentViewController: NSViewController {
    private var hostingView: NSHostingView<AnyView>?
    private var cancellables = Set<AnyCancellable>()

    private let contentFactory: ViewProvider

    init(contentFactory: ViewProvider = ContentViewFactory.shared) {
        self.contentFactory = contentFactory
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        contentFactory = ContentViewFactory.shared
        super.init(coder: coder)
    }

    override func loadView() {
        if #available(macOS 26, *) {
            view = NSBackgroundExtensionView(frame: NSRect(x: 0, y: 0, width: 650, height: 600))
        } else {
            view = NSView(frame: NSRect(x: 0, y: 0, width: 650, height: 600))
        }
        view.wantsLayer = true

        // Set initial content based on current navigation
        updateContent(for: SettingsState.shared.navigation)
    }

    func updateContent(for navigation: SettingsState.Navigation?) {
        // Remove existing hosting view
        hostingView?.removeFromSuperview()

        guard let navigation else {
            hostingView = nil
            return
        }

        // Use factory to create content view
        hostingView = contentFactory.createHostingView(for: navigation)

        guard let hostingView else {
            return
        }

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)

        // Set up constraints
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
