// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import Foundation

final class WindowInfoCache {
    static let shared = WindowInfoCache()

    private struct WindowInfo {
        let ownerPid: pid_t
        let bounds: CGRect
        let alpha: Double
    }

    private static let cacheLifetime: TimeInterval = 0.05

    private let lock = NSLock()
    private var cachedAt: TimeInterval?
    private var cachedWindows = [WindowInfo]()
    private var generation = 0

    func topmostWindowOwnerPid(at point: CGPoint) -> pid_t? {
        for window in windowListSnapshot() {
            guard window.alpha > 0, window.bounds.contains(point) else {
                continue
            }
            return window.ownerPid
        }

        return nil
    }

    func invalidate() {
        lock.lock()
        generation += 1
        cachedAt = nil
        cachedWindows.removeAll()
        lock.unlock()
    }

    private func windowListSnapshot() -> [WindowInfo] {
        let now = ProcessInfo.processInfo.systemUptime

        lock.lock()
        if let cachedAt, now - cachedAt < Self.cacheLifetime {
            let cachedWindows = cachedWindows
            lock.unlock()
            return cachedWindows
        }
        let generation = generation
        lock.unlock()

        let windows = Self.copyWindowList()
        let updatedAt = ProcessInfo.processInfo.systemUptime

        lock.lock()
        if self.generation == generation {
            cachedAt = updatedAt
            cachedWindows = windows
        }
        lock.unlock()

        return windows
    }

    private static func copyWindowList() -> [WindowInfo] {
        let options = CGWindowListOption(arrayLiteral: [.excludeDesktopElements, .optionOnScreenOnly])
        guard let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? as? [[String: Any]]
        else {
            return []
        }

        return windowListInfo.compactMap { windowInfo in
            // Only consider normal application windows (NSWindow.Level.normal == 0) so that
            // overlays such as the menu bar, Dock, status-bar panels, and click-through HUDs
            // (including our own auto-scroll indicator) don't take precedence.
            guard let layer = windowInfo[kCGWindowLayer as String] as? Int, layer == 0 else {
                return nil
            }

            guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
                return nil
            }

            guard let ownerPid = windowInfo[kCGWindowOwnerPID as String] as? pid_t else {
                return nil
            }

            let alpha = windowInfo[kCGWindowAlpha as String] as? Double ?? 1
            return WindowInfo(ownerPid: ownerPid, bounds: bounds, alpha: alpha)
        }
    }
}

extension CGPoint {
    /// Returns the owner pid of the topmost normal-level window that contains this point.
    var topmostWindowOwnerPid: pid_t? {
        WindowInfoCache.shared.topmostWindowOwnerPid(at: self)
    }
}
