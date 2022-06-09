//
//  StatusMenu.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/6/12.
//

import Combine
import SwiftUI

fileprivate struct StatusView: View {
    @ObservedObject var defaults = AppDefaults.shared

    var reverseScrollingStatus: some View {
        if defaults.reverseScrollingVerticallyOn && defaults.reverseScrollingHorizontallyOn {
            return Text("on")
        }
        if defaults.reverseScrollingVerticallyOn {
            return Text("vertically only")
        }
        if defaults.reverseScrollingHorizontallyOn {
            return Text("horizontally only")
        }
        return Text("off")
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(LinearMouse.appName)
                .bold()
                .padding(.vertical, 2)
            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                HStack {
                    Text("Reverse scrolling:")
                    reverseScrollingStatus
                }
                HStack {
                    Text("Linear scrolling:")
                    if defaults.linearScrollingOn {
                        Text(String(defaults.scrollLines))
                        Text(defaults.scrollLines == 1
                                ? "line"
                                : "lines")
                    } else {
                        Text("off")
                    }
                }
                HStack {
                    Text("Universal back and forward:")
                    Text(defaults.universalBackForwardOn ? "on" : "off")
                }
            }
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 15)
    }
}

class StatusItem {
    static let shared = StatusItem()

    private lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private lazy var statusView: NSMenuItem = {
        let item = NSMenuItem()
        let view = NSHostingView(rootView: StatusView())
        view.frame.size = view.fittingSize
        item.view = view
        return item
    }()

    private lazy var menu: NSMenu = {
        let menu = NSMenu()
        menu.items = [
            statusView,
            .separator(),
            .init(
                title: String(format: NSLocalizedString("%@ Preferences...", comment: ""), LinearMouse.appName),
                action: #selector(openPreferencesAction),
                keyEquivalent: ","),
            .separator(),
            .init(
                title: String(format: NSLocalizedString("Quit %@", comment: ""), LinearMouse.appName),
                action: #selector(quitAction),
                keyEquivalent: "q")
        ]
        menu.items.forEach { $0.target = self }
        return menu
    }()

    private lazy var accessibilityPermissionWindow = AccessibilityPermissionWindow()

    private lazy var preferencesWindow = PreferencesWindow()

    var defaultsSubscription: AnyCancellable!

    init() {
        if let button = statusItem.button {
            button.image = NSImage(named: "MenuIcon")
            button.action = #selector(self.statusItemAction(sender:))
            button.target = self
        }

        guard AccessibilityPermission.enabled else {
            NSApp.activate(ignoringOtherApps: true)
            self.accessibilityPermissionWindow.makeKeyAndOrderFront(nil)

            AccessibilityPermission.pollingUntilEnabled {
                self.setup()
            }

            return
        }

        setup()
    }

    private func setup() {
        statusItem.menu = menu

        // Subscribe to the user settings and show / hide the menu icon.
        let defaults = AppDefaults.shared
        defaultsSubscription = defaults.objectWillChange.sink { _ in
            DispatchQueue.main.async {
                self.update(defaults)
            }
        }
        self.update(defaults)
    }

    @objc private func statusItemAction(sender: NSStatusBarButton) {
        guard !AccessibilityPermission.enabled else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        accessibilityPermissionWindow.makeKeyAndOrderFront(nil)
    }

    func moveAccessibilityWindowToTheTop() {
        let frame = accessibilityPermissionWindow.frame
        if let screenFrame = accessibilityPermissionWindow.screen?.visibleFrame {
            accessibilityPermissionWindow.setFrame(.init(origin: .init(x: frame.origin.x, y: screenFrame.maxY), size: frame.size),
                                                   display: true, animate: true)
        }
    }

    func openPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func openPreferencesAction() {
        openPreferences()
    }

    @objc func quitAction() {
        // remove the start entry if the user quits LinearMouse manually
        AutoStartManager.disable()

        NSApp.terminate(nil)
    }

    func update(_ defaults: AppDefaults) {
        statusItem.isVisible = defaults.showInMenuBar
    }
}
