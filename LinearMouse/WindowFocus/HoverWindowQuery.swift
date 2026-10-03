// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit

/// Unlike per-app mouse settings, focusing must not look through menus, Dock
/// windows or overlays to an ordinary window underneath them.
struct HoverWindowQuery {
    struct Window {
        let id: CGWindowID
        let pid: pid_t
        let element: AXUIElement
    }

    struct Focus: Equatable {
        let pid: pid_t
        let windowID: CGWindowID
    }

    private let system = AXUIElementCreateSystemWide()

    init() {
        AXUIElementSetMessagingTimeout(system, 0.05)
    }

    func window(at point: CGPoint) -> Window? {
        guard LMWindowFocusAvailable(),
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0)
              as? [[String: Any]],
              let target = Self.hitTest(windows, at: point),
              let app = NSRunningApplication(processIdentifier: target.pid),
              app.activationPolicy == .regular,
              !app.isTerminated, !app.isHidden else {
            return nil
        }

        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else {
            return nil
        }
        AXUIElementSetMessagingTimeout(hit, 0.05)
        let window = string(kAXRoleAttribute, on: hit) == kAXWindowRole
            ? hit : element(kAXWindowAttribute, on: hit)
        guard let window,
              string(kAXSubroleAttribute, on: window) == kAXStandardWindowSubrole,
              (value(kAXMinimizedAttribute, on: window) as? Bool) != true,
              (value(kAXModalAttribute, on: window) as? Bool) != true,
              !hasSheet(on: window) else {
            return nil
        }
        var axID: CGWindowID = 0
        var axPID: pid_t = 0
        guard LMGetWindowID(window, &axID), axID == target.windowID,
              AXUIElementGetPid(window, &axPID) == .success, axPID == target.pid else {
            return nil
        }
        return Window(id: target.windowID, pid: target.pid, element: window)
    }

    func currentFocus() -> Focus? {
        guard let app = element(kAXFocusedApplicationAttribute, on: system) else {
            return nil
        }
        AXUIElementSetMessagingTimeout(app, 0.05)
        var pid: pid_t = 0
        guard AXUIElementGetPid(app, &pid) == .success,
              let runningApp = NSRunningApplication(processIdentifier: pid),
              runningApp.activationPolicy == .regular else {
            return nil
        }
        // Keep menus and transient UI in charge until the user dismisses them.
        if let focused = element(kAXFocusedUIElementAttribute, on: app),
           let role = string(kAXRoleAttribute, on: focused),
           [kAXMenuRole, kAXMenuItemRole, kAXMenuBarItemRole, kAXComboBoxRole].contains(role) {
            return nil
        }
        if let menuBar = element(kAXMenuBarAttribute, on: app),
           let selected = value(kAXSelectedChildrenAttribute, on: menuBar) as? [AXUIElement],
           !selected.isEmpty {
            return nil
        }
        guard let window = element(kAXFocusedWindowAttribute, on: app) else {
            return Focus(pid: pid, windowID: 0)
        }
        guard
            string(kAXSubroleAttribute, on: window) == kAXStandardWindowSubrole,
            (value(kAXModalAttribute, on: window) as? Bool) != true,
            !hasSheet(on: window) else {
            return nil
        }
        var id: CGWindowID = 0
        guard LMGetWindowID(window, &id) else {
            return nil
        }
        return Focus(pid: pid, windowID: id)
    }

    static func hitTest(_ windows: [[String: Any]], at point: CGPoint) -> Focus? {
        guard let top = windows.first(where: { contains($0, point: point) }),
              top[kCGWindowLayer as String] as? Int == 0,
              let id = top[kCGWindowNumber as String] as? CGWindowID,
              let pid = top[kCGWindowOwnerPID as String] as? pid_t else {
            return nil
        }
        return Focus(pid: pid, windowID: id)
    }

    private static func contains(_ window: [String: Any], point: CGPoint) -> Bool {
        guard (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              let bounds = window[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds) else {
            return false
        }
        return rect.contains(point)
    }

    private func hasSheet(on window: AXUIElement) -> Bool {
        let children = value(kAXChildrenAttribute, on: window) as? [AXUIElement] ?? []
        return children.contains { string(kAXRoleAttribute, on: $0) == kAXSheetRole }
    }

    private func value(_ attribute: String, on element: AXUIElement) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.05)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else {
            return nil
        }
        return result
    }

    private func element(_ attribute: String, on element: AXUIElement) -> AXUIElement? {
        guard let result = value(attribute, on: element), CFGetTypeID(result) == AXUIElementGetTypeID() else {
            return nil
        }
        return (result as! AXUIElement)
    }

    private func string(_ attribute: String, on element: AXUIElement) -> String? {
        value(attribute, on: element) as? String
    }
}
