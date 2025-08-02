// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation

protocol NavigationItem {
    var id: AnyHashable { get }
    var title: String { get }
    var systemImage: String { get }
}

protocol NavigationProvider {
    var items: [NavigationItem] { get }
}

struct SettingsNavigationItem: NavigationItem {
    let navigation: SettingsState.Navigation
    let title: String
    let systemImage: String

    var id: AnyHashable {
        navigation
    }
}

class DefaultNavigationProvider: NavigationProvider {
    lazy var items: [NavigationItem] = [
        SettingsNavigationItem(navigation: .scrolling, title: "Scrolling", systemImage: "scroll.fill"),
        SettingsNavigationItem(navigation: .pointer, title: "Pointer", systemImage: "cursorarrow"),
        SettingsNavigationItem(navigation: .buttons, title: "Buttons", systemImage: "button.programmable"),
        SettingsNavigationItem(navigation: .general, title: "General", systemImage: "gearshape.fill")
    ]
}
