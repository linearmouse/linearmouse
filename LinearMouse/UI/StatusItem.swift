// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Combine
import Defaults
import LaunchAtLogin
import SwiftUI

class StatusItem {
    static let shared = StatusItem()

    private lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private var subscriptions = Set<AnyCancellable>()

    private lazy var menu: NSMenu = {
        let menu = NSMenu()

        let openSettingsItem = NSMenuItem(
            title: String(format: NSLocalizedString("%@ Settings…", comment: ""), LinearMouse.appName),
            action: #selector(openSettings),
            keyEquivalent: ","
        )

        let configurationItem = NSMenuItem(title: NSLocalizedString("Config", comment: ""),
                                           action: nil,
                                           keyEquivalent: "")

        configurationItem.submenu = configurationMenu

        let startAtLoginItem = NSMenuItem(
            title: String(format: NSLocalizedString("Start at login", comment: "")),
            action: #selector(toggleStartAtLogin),
            keyEquivalent: ""
        )
        LaunchAtLogin.publisher
            .receive(on: RunLoop.main)
            .sink { value in
                startAtLoginItem.state = value ? .on : .off
            }
            .store(in: &subscriptions)

        let openSettingsForFrontmostApplicationItem = NSMenuItem(
            title: "",
            action: #selector(openSettingsForFrontmostApplication),
            keyEquivalent: ""
        )
        func updateOpenSettingsForFrontmostApplicationItem() {
            guard let url = NSWorkspace.shared.frontmostApplication?.bundleURL,
                  let name = try? readInstalledApp(at: url)?.bundleName else {
                openSettingsForFrontmostApplicationItem.isHidden = true
                return
            }
            openSettingsForFrontmostApplicationItem.isHidden = false
            openSettingsForFrontmostApplicationItem.title = String(
                format: NSLocalizedString("Configure for %@…", comment: ""),
                name
            )
        }
        updateOpenSettingsForFrontmostApplicationItem()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main,
            using: { _ in
                updateOpenSettingsForFrontmostApplicationItem()
            }
        )

        let quitItem = NSMenuItem(title: String(format: NSLocalizedString("Quit %@", comment: ""), LinearMouse.appName),
                                  action: #selector(quit),
                                  keyEquivalent: "q")

        menu.items = [
            openSettingsItem,
            .separator(),
            configurationItem,
            startAtLoginItem,
            .separator(),
            openSettingsForFrontmostApplicationItem,
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
            revealInFinderItem
        ]

        configurationMenu.items.forEach { $0.target = self }

        return configurationMenu
    }()

    init() {
        if let button = statusItem.button {
            button.image = NSImage(named: "MenuIcon")
            button.action = #selector(statusItemAction(sender:))
            button.target = self
        }

        AccessibilityPermission.pollingUntilEnabled { [weak self] in
            self?.setup()
        }
    }

    private func setup() {
        statusItem.menu = menu

        Defaults.observe(.showInMenuBar) { [weak self] change in
            guard let self = self else { return }

            self.statusItem.isVisible = change.newValue
        }.tieToLifetime(of: self)
    }

    @objc private func statusItemAction(sender _: NSStatusBarButton) {
        guard !AccessibilityPermission.enabled else {
            return
        }

        AccessibilityPermissionWindow.shared.bringToFront()
    }

    @objc private func openSettings() {
        SchemeState.shared.currentApp = nil
        SchemeState.shared.currentDisplay = nil
        SettingsWindow.shared.bringToFront()
    }

    @objc private func openSettingsForFrontmostApplication() {
        SchemeState.shared.currentApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        SettingsWindow.shared.bringToFront()
    }

    @objc private func reloadConfiguration() {
        ConfigurationState.shared.load()
    }

    @objc private func revealConfigurationInFinder() {
        ConfigurationState.shared.revealInFinder()
    }

    @objc private func toggleStartAtLogin() {
        LaunchAtLogin.isEnabled.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
