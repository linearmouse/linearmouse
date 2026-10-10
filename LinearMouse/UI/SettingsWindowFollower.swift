// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit

// Portions adapted from PermissionFlow, Copyright (c) 2026 小弟调调.
// Full MIT permission notice: ThirdPartyNotices/PermissionFlow.txt.
// Upstream sources:
// https://github.com/jaywcjlove/PermissionFlow/blob/cb96db4bfd2342e8d8c56f2a7d51ca65b8aed6e2/Sources/PermissionFlow/Tracking/SettingsWindowTracker.swift

/// Reads only window geometry; following Settings must work before AX access is granted.
final class SettingsWindowFollower {
    private var timer: Timer?
    var onUnavailable: () -> Void = {}
    private var misses = 0
    private var hasSeenWindow = false
    private let onFrame: (CGRect) -> Void

    init(onFrame: @escaping (CGRect) -> Void) {
        self.onFrame = onFrame
    }

    func start() {
        stop()
        misses = 0
        hasSeenWindow = false
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.update() }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        update()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { stop() }

    private func update() {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
            .map(\.processIdentifier))
        guard !pids.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
              as? [[String: Any]],
              let mainScreen = NSScreen.screens.first
        else {
            missingWindow()
            return
        }
        let frames = windows.compactMap { info -> CGRect? in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.width > 300, frame.height > 200
            else {
                return nil
            }
            // Window-server coordinates use the primary screen's top-left as their origin.
            return CGRect(
                x: frame.minX,
                y: mainScreen.frame.maxY - frame.maxY,
                width: frame.width,
                height: frame.height
            )
        }
        guard let frame = frames.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            missingWindow()
            return
        }
        misses = 0
        hasSeenWindow = true
        onFrame(frame)
    }

    private func missingWindow() {
        misses += 1
        if misses == (hasSeenWindow ? 30 : 300) {
            onUnavailable()
        }
    }
}

enum PermissionGuidePlacement {
    static func frame(size: CGSize, below target: CGRect, within visible: CGRect) -> CGRect {
        let inset: CGFloat = 12
        return CGRect(
            x: min(max(target.maxX - size.width, visible.minX + inset), visible.maxX - size.width - inset),
            y: min(max(target.minY - size.height - 6, visible.minY + inset), visible.maxY - size.height - inset),
            width: size.width,
            height: size.height
        )
    }
}
