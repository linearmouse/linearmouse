// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

protocol ViewProvider {
    func createView(for navigation: SettingsState.Navigation) -> AnyView?
}

class ContentViewFactory: ViewProvider {
    static let shared = ContentViewFactory()

    private init() {}

    func createView(for navigation: SettingsState.Navigation) -> AnyView? {
        switch navigation {
        case .scrolling:
            return AnyView(ScrollingSettings())
        case .pointer:
            return AnyView(PointerSettings())
        case .buttons:
            return AnyView(ButtonsSettings())
        case .general:
            return AnyView(GeneralSettings())
        }
    }
}

// MARK: - Protocol Extension for Convenience

extension ViewProvider {
    func createHostingView(for navigation: SettingsState.Navigation) -> NSHostingView<AnyView>? {
        guard let contentView = createView(for: navigation) else {
            return nil
        }
        return NSHostingView(rootView: contentView)
    }
}
