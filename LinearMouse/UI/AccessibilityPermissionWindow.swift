// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

class AccessibilityPermissionWindow: NSWindow {
    static let shared = AccessibilityPermissionWindow()
    private var guideActive = false
    private var permissionTimer: Timer?
    private var checking = false
    private var authorizationID = 0
    private var authorizationProgress = AccessibilityPermission
        .AuthorizationProgress(accessibilityInitiallyTrusted: true)
    private lazy var dragPanel: PermissionDragPanel = {
        let panel = PermissionDragPanel()
        panel.onCancel = { [weak self] in
            self?.stopGuidance()
            self?.show()
        }
        return panel
    }()

    private lazy var follower: SettingsWindowFollower = {
        let follower = SettingsWindowFollower { [weak self] frame in self?.dragPanel.follow(frame) }
        follower.onUnavailable = { [weak self] in
            guard let self else {
                return
            }
            dragPanel.orderOut(nil)
            // Keep the entry point reachable when Settings is closed or hidden.
            stopGuidance()
            show()
        }
        return follower
    }()

    init() {
        super.init(
            contentRect: .init(x: 0, y: 0, width: 440, height: 260),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        delegate = self
        isReleasedWhenClosed = false
        title = "LinearMouse"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        level = .floating
        render(eventTapFailed: false)
        center()
    }

    func show(eventTapFailed: Bool = false) {
        guard !guideActive else {
            return
        }
        render(eventTapFailed: eventTapFailed)
        if !isVisible {
            bringToFront()
        }
    }

    func beginAuthorization() {
        if !guideActive {
            authorizationProgress = .init(accessibilityInitiallyTrusted: AccessibilityPermission.enabled)
            guideActive = true
            dragPanel.prepare(from: NSEvent.mouseLocation)
            orderOut(nil)
            follower.start()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.checkPermission() }
            RunLoop.main.add(timer, forMode: .common)
            permissionTimer = timer
        }
        AccessibilityPermission.openSettings()
        checkPermission()
    }

    func dismiss() {
        stopGuidance()
        orderOut(nil)
    }

    private func render(eventTapFailed: Bool) {
        let view = NSHostingView(rootView: AccessibilityPermissionView(eventTapFailed: eventTapFailed))
        contentView = view
        setContentSize(view.fittingSize)
    }

    private func checkPermission() {
        guard guideActive, !checking else {
            return
        }
        checking = true
        let expectedAuthorizationID = authorizationID
        AccessibilityPermission.check { [weak self] snapshot in
            guard let self else {
                return
            }
            checking = false
            guard authorizationID == expectedAuthorizationID, guideActive,
                  authorizationProgress.shouldRestart(after: snapshot, isDragging: dragPanel.isDraggingApp)
            else {
                return
            }
            // Restart only after an explicit authorization flow, never from the watchdog.
            stopGuidance()
            Application.restart()
        }
    }

    private func stopGuidance() {
        authorizationID += 1
        guideActive = false
        follower.stop()
        dragPanel.orderOut(nil)
        permissionTimer?.invalidate()
        permissionTimer = nil
    }
}

extension AccessibilityPermissionWindow: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        stopGuidance()
        NSApplication.shared.terminate(nil)
    }
}
