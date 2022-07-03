// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Combine
import SwiftUI

class StatusItem {
    static let shared = StatusItem()

    private lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private lazy var menu: NSMenu = {
        let menu = NSMenu()

        let openPreferenceItem = NSMenuItem(
            title: String(format: NSLocalizedString("%@ Preferences...", comment: ""), LinearMouse.appName),
            action: #selector(openPreferences),
            keyEquivalent: ","
        )

        let configurationItem = NSMenuItem(title: NSLocalizedString("Config", comment: ""),
                                           action: nil,
                                           keyEquivalent: "")

        configurationItem.submenu = configurationMenu

        let quitItem = NSMenuItem(title: String(format: NSLocalizedString("Quit %@", comment: ""), LinearMouse.appName),
                                  action: #selector(quit),
                                  keyEquivalent: "q")

        menu.items = [
            openPreferenceItem,
            .separator(),
            configurationItem,
            .separator(),
            quitItem
        ]

        menu.items.forEach { $0.target = self }

        return menu
    }()

    private lazy var configurationMenu: NSMenu = {
        let configurationMenu = NSMenu()

        let reloadItem = NSMenuItem(title: NSLocalizedString("Reload", comment: ""),
                                    action: #selector(reloadConfiguration), keyEquivalent: "r")

        let revealInFinderItem = NSMenuItem(title: NSLocalizedString("Reveal in Finder", comment: ""),
                                            action: #selector(revealConfigurationInFinder),
                                            keyEquivalent: "r")
        revealInFinderItem.keyEquivalentModifierMask = [.option, .command]

        configurationMenu.items = [
            reloadItem,
            .separator(),
            revealInFinderItem
        ]

        configurationMenu.items.forEach { $0.target = self }

        return configurationMenu
    }()

    var defaultsSubscription: AnyCancellable!

    init() {
        if let button = statusItem.button {
            button.image = NSImage(named: "MenuIcon")
            button.action = #selector(statusItemAction(sender:))
            button.target = self
        }

        AccessibilityPermission.pollingUntilEnabled {
            self.initMenu()
        }
    }

    private func initMenu() {
        statusItem.menu = menu

        // Subscribe to the user settings and show / hide the menu icon.
        let defaults = AppDefaults.shared
        defaultsSubscription = defaults.objectWillChange.sink { _ in
            DispatchQueue.main.async {
                self.update(defaults)
            }
        }
        update(defaults)
    }

    @objc private func statusItemAction(sender _: NSStatusBarButton) {
        guard !AccessibilityPermission.enabled else {
            return
        }

        AccessibilityPermissionWindow.shared.bringToFront()
    }

    @objc private func openPreferences() {
        PreferencesWindow.shared.bringToFront()
    }

    @objc private func reloadConfiguration() {
        ConfigurationState.shared.load()
    }

    @objc private func revealConfigurationInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([ConfigurationState.shared.configurationPath.absoluteURL])
    }

    @objc func quit() {
        // remove the start entry if the user quits LinearMouse manually
        AutoStartManager.disable()

        NSApp.terminate(nil)
    }

    func update(_ defaults: AppDefaults) {
        statusItem.isVisible = defaults.showInMenuBar
    }
}
