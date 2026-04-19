// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import Foundation

extension CGPoint {
    /// Returns the owner pid of the topmost normal-level window that contains this point.
    var topmostWindowOwnerPid: pid_t? {
        let options = CGWindowListOption(arrayLiteral: [.excludeDesktopElements, .optionOnScreenOnly])
        guard let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? as? [[String: Any]]
        else {
            return nil
        }

        for windowInfo in windowListInfo {
            // Only consider normal application windows (NSWindow.Level.normal == 0) so that
            // overlays such as the menu bar, Dock, status-bar panels, and click-through HUDs
            // (including our own auto-scroll indicator) don't take precedence.
            guard let layer = windowInfo[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }

            guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.contains(self) else {
                continue
            }

            if let alpha = windowInfo[kCGWindowAlpha as String] as? Double, alpha <= 0 {
                continue
            }

            return windowInfo[kCGWindowOwnerPID as String] as? pid_t
        }

        return nil
    }
}
