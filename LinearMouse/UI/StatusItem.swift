// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import Defaults
import LaunchAtLogin
import SwiftUI

class StatusItem: NSObject, NSMenuDelegate {
    static let shared = StatusItem()

    private lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private var subscriptions = Set<AnyCancellable>()

    private lazy var menu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self

        menu.items = baseMenuItems()

        return menu
    }()

    private lazy var openSettingsItem: NSMenuItem = {
        let item = NSMenuItem(
            title: String(format: NSLocalizedString("%@ Settings…", comment: ""), LinearMouse.appName),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        item.target = self
        return item
    }()

    private lazy var configurationItem: NSMenuItem = {
        let item = NSMenuItem(
            title: NSLocalizedString("Config", comment: ""),
            action: nil,
            keyEquivalent: ""
        )
        item.submenu = configurationMenu
        return item
    }()

    private lazy var startAtLoginItem: NSMenuItem = {
        let item = NSMenuItem(
            title: String(format: NSLocalizedString("Start at login", comment: "")),
            action: #selector(toggleStartAtLogin),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }()

    private lazy var openSettingsForFrontmostApplicationItem: NSMenuItem = {
        let item = NSMenuItem(
            title: "",
            action: #selector(openSettingsForFrontmostApplication),
            keyEquivalent: ""
        )
        item.target = self
        return item
    }()

    private lazy var quitItem: NSMenuItem = {
        let item = NSMenuItem(
            title: String(format: NSLocalizedString("Quit %@", comment: ""), LinearMouse.appName),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        item.target = self
        return item
    }()

    private lazy var configurationMenu: NSMenu = {
        let configurationMenu = NSMenu()

        let reloadItem = NSMenuItem(
            title: NSLocalizedString("Reload", comment: ""),
            action: #selector(reloadConfiguration),
            keyEquivalent: "r"
        )

        let revealInFinderItem = NSMenuItem(
            title: NSLocalizedString("Reveal in Finder", comment: ""),
            action: #selector(revealConfigurationInFinder),
            keyEquivalent: "r"
        )
        revealInFinderItem.keyEquivalentModifierMask = [.option, .command]

        configurationMenu.items = [
            reloadItem,
            revealInFinderItem
        ]

        configurationMenu.items.forEach { $0.target = self }

        return configurationMenu
    }()

    private var batteryItems = [NSMenuItem]()
    private var batterySeparatorItem: NSMenuItem?
    private var isMenuOpen = false

    override init() {
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(named: "MenuIcon")
            button.action = #selector(statusItemAction(sender:))
            button.target = self
        }

        startAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        LaunchAtLogin.publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.startAtLoginItem.state = value ? .on : .off
            }
            .store(in: &subscriptions)

        updateOpenSettingsForFrontmostApplicationItem()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateOpenSettingsForFrontmostApplicationItem()
        }

        AccessibilityPermission.pollingUntilEnabled { [weak self] in
            self?.setup()
        }
    }

    private func rebuildMenuItems(includeBatteryItems: Bool) {
        guard includeBatteryItems else {
            removeBatteryItems()
            return
        }

        let items = makeBatteryItems()
        updateBatteryItems(items)
    }

    private func baseMenuItems() -> [NSMenuItem] {
        [
            openSettingsItem,
            .separator(),
            configurationItem,
            startAtLoginItem,
            .separator(),
            openSettingsForFrontmostApplicationItem,
            quitItem
        ]
    }

    private func makeBatteryItems() -> [NSMenuItem] {
        BatteryDeviceMonitor.shared
            .devices
            .map { ($0.name, $0.batteryLevel) }
            .sorted { lhs, rhs in
                lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
            }
            .map { name, batteryLevel in
                let item = NSMenuItem(title: "\(name) - \(batteryLevel)%", action: nil, keyEquivalent: "")
                item.isEnabled = false
                return item
            }
    }

    private func updateBatteryItems(_ items: [NSMenuItem]) {
        removeBatteryItems()

        guard !items.isEmpty else {
            return
        }

        let header = makeSectionHeader(title: NSLocalizedString("Batteries", comment: ""))
        let separator = NSMenuItem.separator()
        menu.insertItem(separator, at: 0)
        for item in items.reversed() {
            menu.insertItem(item, at: 0)
        }
        menu.insertItem(header, at: 0)

        batteryItems = [header] + items
        batterySeparatorItem = separator
    }

    private func removeBatteryItems() {
        for item in batteryItems {
            menu.removeItem(item)
        }
        batteryItems.removeAll()

        if let batterySeparatorItem {
            menu.removeItem(batterySeparatorItem)
            self.batterySeparatorItem = nil
        }
    }

    private func makeSectionHeader(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func updateOpenSettingsForFrontmostApplicationItem() {
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

    private func setup() {
        statusItem.menu = menu

        BatteryDeviceMonitor.shared
            .$devices
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.statusItem.menu != nil else {
                    return
                }

                if self.isMenuOpen {
                    self.rebuildMenuItems(includeBatteryItems: true)
                }
            }
            .store(in: &subscriptions)

        Defaults.observe(.showInMenuBar) { [weak self] change in
            guard let self else {
                return
            }

            self.statusItem.isVisible = change.newValue
        }
        .tieToLifetime(of: self)
    }

    func menuWillOpen(_: NSMenu) {
        isMenuOpen = true
        rebuildMenuItems(includeBatteryItems: true)
    }

    func menuDidClose(_: NSMenu) {
        isMenuOpen = false
        rebuildMenuItems(includeBatteryItems: false)
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
        SettingsWindowController.shared.bringToFront()
    }

    @objc private func openSettingsForFrontmostApplication() {
        if let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            SchemeState.shared.currentApp = .bundle(bundleIdentifier)
        } else {
            SchemeState.shared.currentApp = nil
        }
        SettingsWindowController.shared.bringToFront()
    }

    @objc private func reloadConfiguration() {
        ConfigurationState.shared.reloadFromDisk()
    }

    @objc private func revealConfigurationInFinder() {
        ConfigurationState.shared.revealInFinder()
    }

    @objc private func toggleStartAtLogin() {
        LaunchAtLogin.isEnabled.toggle()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
