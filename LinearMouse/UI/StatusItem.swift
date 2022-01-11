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
                    Text(defaults.reverseScrollingOn ? "on" : "off")
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

    lazy var statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    lazy var statusView: NSMenuItem = {
        let item = NSMenuItem()
        let view = NSHostingView(rootView: StatusView())
        view.frame.size = view.fittingSize
        item.view = view
        return item
    }()

    lazy var menu: NSMenu = {
        let menu = NSMenu()
        menu.items = [
            statusView,
            .separator(),
            .init(
                title: String(format: NSLocalizedString("%@ Preferences...", comment: ""), LinearMouse.appName),
                action: #selector(openPreferencesAction),
                keyEquivalent: ""),
            .separator(),
            .init(
                title: String(format: NSLocalizedString("Quit %@", comment: ""), LinearMouse.appName),
                action: #selector(quitAction),
                keyEquivalent: "q")
        ]
        menu.items.forEach { $0.target = self }
        return menu
    }()

    lazy var preferencesWindow = PreferencesWindow()

    var defaultsSubscription: AnyCancellable!

    init() {
        statusItem.button?.image = NSImage(named: "MenuIcon")
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

    @objc func openPreferencesAction() {
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow.makeKeyAndOrderFront(nil)
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
