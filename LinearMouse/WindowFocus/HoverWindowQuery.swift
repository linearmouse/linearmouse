// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit

/// WindowServer identifies the input window; AX checks eligibility only before focusing.
struct HoverWindowQuery {
    typealias Focus = WindowFocus.Target

    private let system = AXUIElementCreateSystemWide()

    init() {
        AXUIElementSetMessagingTimeout(system, 0.05)
    }

    func window(at point: CGPoint) -> Focus? {
        WindowFocus.shared.window(at: point)
    }

    func canFocus(_ target: Focus, at point: CGPoint) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: target.pid),
              app.activationPolicy == .regular,
              !app.isTerminated, !app.isHidden,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0)
              as? [[String: Any]],
              Self.validateWindow(target, in: windows, at: point) != nil else {
            return false
        }
        let application = AXUIElementCreateApplication(target.pid)
        guard let axWindows = value(kAXWindowsAttribute, on: application) as? [AXUIElement],
              let window = Self.matchingWindow(in: axWindows, targetID: target.windowID, windowID: { element in
                  windowID(of: element)
              }),
              string(kAXRoleAttribute, on: window) == kAXWindowRole,
              string(kAXSubroleAttribute, on: window) == kAXStandardWindowSubrole,
              (value(kAXMinimizedAttribute, on: window) as? Bool) == false,
              (value(kAXModalAttribute, on: window) as? Bool) != true,
              !hasSheet(on: window) else {
            return false
        }
        return true
    }

    /// Never substitute another window from the same application when the hit
    /// is a menu, transient surface, or a window that disappeared during lookup.
    static func matchingWindow<Element>(
        in windows: [Element],
        targetID: CGWindowID,
        windowID: (Element) -> CGWindowID?
    ) -> Element? {
        windows.first { windowID($0) == targetID }
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
        guard let id = windowID(of: window) else {
            return nil
        }
        return Focus(pid: pid, windowID: id)
    }

    /// Validate the exact WindowServer hit, without falling through to another
    /// window based on overlapping rectangles or special application names.
    static func validateWindow(
        _ target: Focus,
        in windows: [[String: Any]],
        at point: CGPoint
    ) -> Focus? {
        guard let window = windows.first(where: { $0[kCGWindowNumber as String] as? CGWindowID == target.windowID }),
              window[kCGWindowOwnerPID as String] as? pid_t == target.pid,
              window[kCGWindowLayer as String] as? Int == 0,
              contains(window, point: point) else {
            return nil
        }
        return target
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

    /// AX queries for our own elements call AppKit directly on the caller's thread.
    /// Keep those calls on main, including window-ID lookup, while remote IPC stays
    /// on the hover worker. The main thread must not wait synchronously for that worker.
    static func performAXQuery<Result>(on element: AXUIElement, _ query: () -> Result) -> Result {
        var pid: pid_t = 0
        if AXUIElementGetPid(element, &pid) == .success,
           pid == ProcessInfo.processInfo.processIdentifier,
           !Thread.isMainThread {
            return DispatchQueue.main.sync(execute: query)
        }
        return query()
    }

    private func windowID(of window: AXUIElement) -> CGWindowID? {
        Self.performAXQuery(on: window) {
            WindowFocus.shared.windowID(of: window)
        }
    }

    private func value(_ attribute: String, on element: AXUIElement) -> CFTypeRef? {
        Self.performAXQuery(on: element) {
            AXUIElementSetMessagingTimeout(element, 0.05)
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else {
                return nil
            }
            return result
        }
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
