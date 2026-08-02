// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
@testable import LinearMouse
import XCTest

final class SettingsToolbarTests: XCTestCase {
    func testLeavingButtonsClearsDestinationPath() {
        let state = SettingsState()
        state.navigation = .buttons
        state.buttonsNavigationPath = [.autoScroll]

        state.navigation = .pointer

        XCTAssertTrue(state.buttonsNavigationPath.isEmpty)
    }

    func testButtonsDestinationUsesNativeToolbarNavigation() {
        let state = SettingsState()
        state.navigation = .buttons

        let splitViewController = SettingsSplitViewController()
        let toolbar = SettingsToolbar(
            splitViewController: splitViewController,
            settingsState: state
        )
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 850, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = LinearMouse.appName
        window.contentViewController = splitViewController
        window.toolbar = toolbar

        let expectation = expectation(description: "Toolbar navigation updates")
        state.buttonsNavigationPath = [.autoScroll]

        DispatchQueue.main.async {
            guard let backItem = toolbar.items.first(where: {
                $0.itemIdentifier == SettingsToolbar.buttonsBackItemIdentifier
            }) else {
                XCTFail("Expected a native toolbar back item")
                expectation.fulfill()
                return
            }

            XCTAssertTrue(backItem.isEnabled)
            XCTAssertEqual(
                window.title,
                NSLocalizedString("Autoscroll", comment: "Buttons settings destination")
            )
            XCTAssertTrue(NSApp.sendAction(backItem.action!, to: backItem.target, from: backItem))

            DispatchQueue.main.async {
                XCTAssertTrue(state.buttonsNavigationPath.isEmpty)
                XCTAssertFalse(toolbar.items.contains {
                    $0.itemIdentifier == SettingsToolbar.buttonsBackItemIdentifier
                })
                XCTAssertEqual(window.title, LinearMouse.appName)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 1)
    }
}
