// MIT License
// Copyright (c) 2021-2025 LinearMouse

import AppKit
import SwiftUI

class ToolbarManager: NSObject, NSToolbarDelegate {
    static let shared = ToolbarManager()

    override private init() {
        super.init()
    }

    // Toolbar item identifiers
    private let deviceIndicatorID = NSToolbarItem.Identifier("DeviceIndicator")
    private let appIndicatorID = NSToolbarItem.Identifier("AppIndicator")
    private let displayIndicatorID = NSToolbarItem.Identifier("DisplayIndicator")
    private let flexibleSpaceID = NSToolbarItem.Identifier.flexibleSpace

    func createToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self

        // Modern macOS 26 styling - fixed display mode
        if #available(macOS 13.0, *) {
            toolbar.displayMode = .iconOnly
        } else {
            toolbar.displayMode = .iconAndLabel
        }

        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false

        // Disable display mode switching
        if #available(macOS 15.0, *) {
            toolbar.allowsDisplayModeCustomization = false
        }

        return toolbar
    }

    // MARK: - NSToolbarDelegate

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case deviceIndicatorID:
            return createDeviceIndicatorItem()
        case appIndicatorID:
            return createAppIndicatorItem()
        case displayIndicatorID:
            return createDisplayIndicatorItem()
        case flexibleSpaceID:
            return NSToolbarItem(itemIdentifier: flexibleSpaceID)
        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Right-aligned layout for all macOS versions (reversed order)
        [flexibleSpaceID, displayIndicatorID, appIndicatorID, deviceIndicatorID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    // MARK: - Private Methods

    private func createDeviceIndicatorItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: deviceIndicatorID)
        item.label = "Device"
        item.paletteLabel = "Device Selection"
        item.toolTip = "Select input device"

        let button = DeviceIndicatorButton()

        // Use textured rounded style for native toolbar appearance
        button.bezelStyle = .texturedRounded
        button.setButtonType(.momentaryPushIn)
        button.showsBorderOnlyWhileMouseInside = true

        // Modern sizing for macOS 26
        if #available(macOS 26.0, *) {
            button.frame = NSRect(x: 0, y: 0, width: 140, height: 32)
        } else {
            button.frame = NSRect(x: 0, y: 0, width: 150, height: 28)
        }

        item.view = button

        return item
    }

    private func createAppIndicatorItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: appIndicatorID)
        item.label = "App"
        item.paletteLabel = "App Selection"
        item.toolTip = "Select target application"

        let button = AppIndicatorButton()

        // Use textured rounded style for native toolbar appearance
        button.bezelStyle = .texturedRounded
        button.setButtonType(.momentaryPushIn)
        button.showsBorderOnlyWhileMouseInside = true

        // Modern sizing for macOS 26
        if #available(macOS 26.0, *) {
            button.frame = NSRect(x: 0, y: 0, width: 140, height: 32)
        } else {
            button.frame = NSRect(x: 0, y: 0, width: 150, height: 28)
        }

        item.view = button

        return item
    }

    private func createDisplayIndicatorItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: displayIndicatorID)
        item.label = "Display"
        item.paletteLabel = "Display Selection"
        item.toolTip = "Select target display"

        let button = DisplayIndicatorButton()

        // Use textured rounded style for native toolbar appearance
        button.bezelStyle = .texturedRounded
        button.setButtonType(.momentaryPushIn)
        button.showsBorderOnlyWhileMouseInside = true

        // Modern sizing for macOS 26
        if #available(macOS 26.0, *) {
            button.frame = NSRect(x: 0, y: 0, width: 140, height: 32)
        } else {
            button.frame = NSRect(x: 0, y: 0, width: 150, height: 28)
        }

        item.view = button

        return item
    }
}
