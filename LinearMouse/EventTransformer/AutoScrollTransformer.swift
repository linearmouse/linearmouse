// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import ApplicationServices
import Foundation
import os.log

private let autoScrollIndicatorSize = CGSize(width: 48, height: 48)

final class AutoScrollTransformer {
    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "AutoScroll")

    private static let deadZone: Double = 10
    private static let maxScrollStep: Double = 160
    private static let timerInterval: TimeInterval = 1.0 / 60.0
    private static let maxAccessibilityParentDepth = 20
    private static let accessibilityProbeRadius: CGFloat = 4
    private static let excludedAccessibilityRoles: Set<String> = [
        "AXMenuBar",
        "AXMenuBarItem",
        "AXMenu",
        "AXMenuItem",
        "AXMenuButton",
        "AXPopUpButton",
        "AXTabGroup",
        "AXToolbar"
    ]
    private static let excludedAccessibilitySubroles: Set<String> = [
        "AXTabButton",
        "AXMenuItem",
        "AXSortButton"
    ]
    private static let webContentAccessibilityRoles: Set<String> = [
        "AXWebArea",
        "AXScrollArea"
    ]

    private let trigger: Scheme.Buttons.Mapping
    private let modes: [Scheme.Buttons.AutoScroll.Mode]
    private let speed: Double
    private let preserveNativeMiddleClick: Bool

    private enum Session {
        case toggle
        case hold
        case pendingToggleOrHold
    }

    private enum State {
        case idle
        case pendingPreservedClick(anchor: CGPoint, current: CGPoint, downEvent: CGEvent)
        case active(anchor: CGPoint, current: CGPoint, session: Session)
    }

    private var state: State = .idle
    private var suppressTriggerUp = false
    private var suppressedExitMouseButton: CGMouseButton?
    private var timer: DispatchSourceTimer?
    private let indicatorController = AutoScrollIndicatorWindowController()

    init(
        trigger: Scheme.Buttons.Mapping,
        modes: [Scheme.Buttons.AutoScroll.Mode],
        speed: Double,
        preserveNativeMiddleClick: Bool
    ) {
        self.trigger = trigger
        self.modes = modes
        self.speed = speed
        self.preserveNativeMiddleClick = preserveNativeMiddleClick
    }
}

extension AutoScrollTransformer: EventTransformer {
    func transform(_ event: CGEvent) -> CGEvent? {
        if case let .active(_, _, session) = state,
           session == .toggle,
           isAnyMouseDownEvent(event),
           !matchesTriggerButton(event) {
            suppressedExitMouseButton = MouseEventView(event).mouseButton
            deactivate()
            return nil
        }

        if let suppressedExitMouseButton,
           isMouseUpEvent(event, for: suppressedExitMouseButton) {
            self.suppressedExitMouseButton = nil
            return nil
        }

        switch event.type {
        case triggerMouseDownEventType:
            return handleTriggerDown(event)
        case triggerMouseUpEventType:
            return handleTriggerUp(event)
        case triggerMouseDraggedEventType, .mouseMoved:
            return handlePointerMoved(event)
        default:
            return event
        }
    }

    private var triggerMouseDownEventType: CGEventType {
        triggerMouseButton.fixedCGEventType(of: .otherMouseDown)
    }

    private var triggerMouseUpEventType: CGEventType {
        triggerMouseButton.fixedCGEventType(of: .otherMouseUp)
    }

    private var triggerMouseDraggedEventType: CGEventType {
        triggerMouseButton.fixedCGEventType(of: .otherMouseDragged)
    }

    private var triggerMouseButton: CGMouseButton {
        let defaultButton = UInt32(CGMouseButton.center.rawValue)
        return CGMouseButton(rawValue: UInt32(trigger.button ?? Int(defaultButton))) ?? .center
    }

    private func handleTriggerDown(_ event: CGEvent) -> CGEvent? {
        guard matchesTriggerButton(event) else {
            return event
        }

        if case let .active(_, _, session) = state, session == .toggle {
            guard hasToggleMode else {
                return nil
            }

            deactivate()
            suppressTriggerUp = true
            return nil
        }

        guard matchesActivationTrigger(event) else {
            return event
        }

        let activationHit = activationHit(for: event)
        switch activationHit {
        case .excludedChrome:
            return event
        case .pressable:
            guard shouldPreserveNativeMiddleClick else {
                break
            }

            if hasHoldMode {
                let point = pointerLocation(for: event)
                let downEvent = event.copy() ?? event
                state = .pendingPreservedClick(anchor: point, current: point, downEvent: downEvent)
                suppressTriggerUp = true
                return nil
            }

            return event
        case .nonPressable, .unknown, nil:
            break
        }

        activate(at: pointerLocation(for: event), session: activationSession)
        suppressTriggerUp = true
        return nil
    }

    private func handleTriggerUp(_ event: CGEvent) -> CGEvent? {
        guard matchesTriggerButton(event) else {
            return event
        }

        guard suppressTriggerUp else {
            return event
        }

        switch state {
        case let .pendingPreservedClick(anchor, current, downEvent):
            if !exceedsDeadZone(from: anchor, to: current) {
                postDeferredNativeClick(from: downEvent)
            }
            state = .idle
        case let .active(anchor, current, session):
            switch session {
            case .hold:
                deactivate()
            case .pendingToggleOrHold:
                if exceedsDeadZone(from: anchor, to: current) {
                    deactivate()
                } else {
                    state = .active(anchor: anchor, current: current, session: .toggle)
                }
            case .toggle:
                break
            }
        case .idle:
            break
        }

        suppressTriggerUp = false
        return nil
    }

    private func handlePointerMoved(_ event: CGEvent) -> CGEvent? {
        switch state {
        case let .pendingPreservedClick(anchor, _, downEvent):
            let point = pointerLocation(for: event)

            if event.type == triggerMouseDraggedEventType,
               exceedsDeadZone(from: anchor, to: point) {
                activate(at: anchor, session: .hold)
                state = .active(anchor: anchor, current: point, session: .hold)
                indicatorController.update(delta: CGVector(dx: point.x - anchor.x, dy: point.y - anchor.y))
                return nil
            }

            state = .pendingPreservedClick(anchor: anchor, current: point, downEvent: downEvent)

            if event.type == triggerMouseDraggedEventType, suppressTriggerUp {
                return nil
            }

            return event
        case let .active(anchor, _, session):
            let point = pointerLocation(for: event)
            let resolvedSession: Session
            if session == .pendingToggleOrHold,
               event.type == triggerMouseDraggedEventType,
               exceedsDeadZone(from: anchor, to: point) {
                resolvedSession = .hold
            } else {
                resolvedSession = session
            }

            state = .active(anchor: anchor, current: point, session: resolvedSession)
            indicatorController.update(delta: CGVector(dx: point.x - anchor.x, dy: point.y - anchor.y))

            if event.type == triggerMouseDraggedEventType, suppressTriggerUp {
                return nil
            }

            return event
        case .idle:
            return event
        }
    }

    var isAutoscrollActive: Bool {
        if case .active = state {
            return true
        }
        return false
    }

    private func matchesActivationTrigger(_ event: CGEvent) -> Bool {
        guard matchesTriggerButton(event) else {
            return false
        }

        let eventFlags = EventView(event).modifierFlags
        return eventFlags == trigger.modifierFlags
    }

    private func matchesTriggerButton(_ event: CGEvent) -> Bool {
        guard let eventButton = MouseEventView(event).mouseButton else {
            return false
        }

        return eventButton == triggerMouseButton
    }

    private func isAnyMouseDownEvent(_ event: CGEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            return true
        default:
            return false
        }
    }

    private func isMouseUpEvent(_ event: CGEvent, for button: CGMouseButton) -> Bool {
        guard let eventButton = MouseEventView(event).mouseButton else {
            return false
        }

        switch event.type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            return eventButton == button
        default:
            return false
        }
    }

    private func activate(at point: CGPoint, session: Session) {
        os_log(
            "Auto scroll activated (modes=%{public}@, button=%{public}d)",
            log: Self.log,
            type: .info,
            modes.map(\.rawValue).joined(separator: ","),
            Int(triggerMouseButton.rawValue)
        )

        suppressedExitMouseButton = nil
        state = .active(anchor: point, current: point, session: session)
        indicatorController.show(at: point)
        indicatorController.update(delta: .zero)
        startTimerIfNeeded()
    }

    private func startTimerIfNeeded() {
        guard timer == nil else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: Self.timerInterval)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    private func tick() {
        guard case let .active(anchor, current, _) = state else {
            return
        }

        let horizontal = scrollAmount(for: anchor.x - current.x)
        let vertical = scrollAmount(for: current.y - anchor.y)

        guard horizontal != 0 || vertical != 0 else {
            return
        }

        postContinuousScrollEvent(horizontal: horizontal, vertical: vertical)
    }

    private func scrollAmount(for delta: Double) -> Double {
        let adjusted = abs(delta) - Self.deadZone
        guard adjusted > 0 else {
            return 0
        }

        let base = adjusted * speed * 0.12
        let boost = sqrt(adjusted) * speed * 0.6
        let value = min(Self.maxScrollStep, base + boost)

        return delta.sign == .minus ? -value : value
    }

    private func postContinuousScrollEvent(horizontal: Double, vertical: Double) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: 0,
            wheel2: 0,
            wheel3: 0
        ) else {
            return
        }

        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: vertical)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: vertical)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: horizontal)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: horizontal)
        event.flags = []
        event.post(tap: .cgSessionEventTap)
    }

    private var hasToggleMode: Bool {
        modes.contains(.toggle)
    }

    private var hasHoldMode: Bool {
        modes.contains(.hold)
    }

    private var activationSession: Session {
        switch (hasToggleMode, hasHoldMode) {
        case (true, true):
            .pendingToggleOrHold
        case (false, true):
            .hold
        default:
            .toggle
        }
    }

    private func pointerLocation(for event: CGEvent) -> CGPoint {
        event.unflippedLocation
    }

    private func exceedsDeadZone(from anchor: CGPoint, to point: CGPoint) -> Bool {
        abs(point.x - anchor.x) > Self.deadZone || abs(point.y - anchor.y) > Self.deadZone
    }

    private var shouldPreserveNativeMiddleClick: Bool {
        guard preserveNativeMiddleClick,
              hasToggleMode,
              triggerMouseButton == .center,
              trigger.modifierFlags.isEmpty else {
            return false
        }

        return true
    }

    private func hitTestPoint(for event: CGEvent) -> CGPoint {
        event.location
    }

    private func activationHit(for event: CGEvent) -> ActivationHit? {
        guard AccessibilityPermission.enabled else {
            return nil
        }

        // Use the event snapshot position instead of re-sampling the current cursor location.
        // This keeps the AX hit-test anchored to the original click we are classifying.
        let point = hitTestPoint(for: event)
        let initialProbe = ActivationProbe(point: point, hit: hitAccessibilityElement(at: point))
        let resolvedProbe = refineActivationProbe(from: initialProbe)
        logAccessibilityHit(initial: initialProbe, resolved: resolvedProbe)
        return resolvedProbe.hit
    }

    private func refineActivationProbe(from initialProbe: ActivationProbe) -> ActivationProbe {
        guard initialProbe.hit.requiresAdditionalSampling else {
            return initialProbe
        }

        // Browser accessibility trees can return a generic container chain for a point that
        // is visually still inside a link. Probe a few nearby points and trust any result
        // that clearly says "do not start autoscroll".
        var bestProbe = initialProbe
        for point in accessibilityProbePoints(around: initialProbe.point) {
            let sampledProbe = ActivationProbe(point: point, hit: hitAccessibilityElement(at: point))
            if sampledProbe.hit.suppressesAutoscroll {
                return sampledProbe
            }

            if sampledProbe.hit.priority > bestProbe.hit.priority {
                bestProbe = sampledProbe
            }
        }

        return bestProbe
    }

    private func accessibilityProbePoints(around point: CGPoint) -> [CGPoint] {
        let offsets = [
            CGPoint.zero,
            CGPoint(x: -Self.accessibilityProbeRadius, y: 0),
            CGPoint(x: Self.accessibilityProbeRadius, y: 0),
            CGPoint(x: 0, y: -Self.accessibilityProbeRadius),
            CGPoint(x: 0, y: Self.accessibilityProbeRadius),
            CGPoint(x: -Self.accessibilityProbeRadius, y: -Self.accessibilityProbeRadius),
            CGPoint(x: -Self.accessibilityProbeRadius, y: Self.accessibilityProbeRadius),
            CGPoint(x: Self.accessibilityProbeRadius, y: -Self.accessibilityProbeRadius),
            CGPoint(x: Self.accessibilityProbeRadius, y: Self.accessibilityProbeRadius)
        ]

        return offsets.map { offset in
            CGPoint(x: point.x + offset.x, y: point.y + offset.y)
        }
    }

    private func hitAccessibilityElement(at point: CGPoint) -> ActivationHit {
        let systemWideElement = AXUIElementCreateSystemWide()
        var hitElement: AXUIElement?
        let hitError = AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &hitElement)
        guard hitError == .success else {
            return .unknown(reason: "hitTest.\(describe(error: hitError))", path: [])
        }

        guard let hitElement else {
            return .nonPressable(path: [])
        }

        var currentElement: AXUIElement? = hitElement
        var path: [String] = []
        var isInsideWebContent = false
        for _ in 0 ..< Self.maxAccessibilityParentDepth {
            guard let element = currentElement else {
                return .nonPressable(path: path)
            }

            let role: String?
            switch requiredStringValue(of: kAXRoleAttribute as CFString, on: element) {
            case let .success(value):
                role = value
            case let .failure(error):
                return .unknown(reason: "role.\(describe(error: error))", path: path)
            }

            let subrole: String?
            switch optionalStringValue(of: kAXSubroleAttribute as CFString, on: element) {
            case let .success(value):
                subrole = value
            case let .failure(error):
                return .unknown(reason: "subrole.\(describe(error: error))", path: path)
            }

            let actions: [String]
            switch optionalActionNames(of: element) {
            case let .success(value):
                actions = value
            case let .failure(error):
                return .unknown(reason: "actions.\(describe(error: error))", path: path)
            }

            path.append(accessibilityPathEntry(role: role, subrole: subrole, actions: actions))

            if let role, Self.webContentAccessibilityRoles.contains(role) {
                isInsideWebContent = true
            }

            // Once we have entered web content, ignore higher-level browser chrome ancestors
            // like tab groups or toolbars. Safari and Chromium often expose those above the
            // page content, and treating them as excluded chrome would block autoscroll on
            // normal page clicks.
            if !isInsideWebContent,
               isExcludedActivationElement(role: role, subrole: subrole) {
                return .excludedChrome(path: path)
            }

            if role == "AXLink" || actions.contains(kAXPressAction as String) {
                return .pressable(path: path)
            }

            switch optionalElementValue(of: kAXParentAttribute as CFString, on: element) {
            case let .success(value):
                currentElement = value
            case let .failure(error):
                return .unknown(reason: "parent.\(describe(error: error))", path: path)
            }
        }

        return .unknown(reason: "depthLimit", path: path)
    }

    private func isExcludedActivationElement(role: String?, subrole: String?) -> Bool {
        if let role, Self.excludedAccessibilityRoles.contains(role) {
            return true
        }

        if let subrole, Self.excludedAccessibilitySubroles.contains(subrole) {
            return true
        }

        return false
    }

    private func requiredStringValue(
        of attribute: CFString,
        on element: AXUIElement
    ) -> AccessibilityQueryResult<String?> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else {
            return .failure(error)
        }

        return .success(value as? String)
    }

    private func optionalStringValue(
        of attribute: CFString,
        on element: AXUIElement
    ) -> AccessibilityQueryResult<String?> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        switch error {
        case .success:
            return .success(value as? String)
        case .noValue, .attributeUnsupported:
            return .success(nil)
        default:
            return .failure(error)
        }
    }

    private func optionalElementValue(
        of attribute: CFString,
        on element: AXUIElement
    ) -> AccessibilityQueryResult<AXUIElement?> {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        switch error {
        case .success:
            return .success(value as! AXUIElement?)
        case .noValue, .attributeUnsupported:
            return .success(nil)
        default:
            return .failure(error)
        }
    }

    private func optionalActionNames(of element: AXUIElement) -> AccessibilityQueryResult<[String]> {
        var actions: CFArray?
        let error = AXUIElementCopyActionNames(element, &actions)
        switch error {
        case .success:
            return .success(actions as? [String] ?? [])
        case .noValue, .actionUnsupported, .attributeUnsupported:
            return .success([])
        default:
            return .failure(error)
        }
    }

    private func accessibilityPathEntry(role: String?, subrole: String?, actions: [String]) -> String {
        let roleDescription = role ?? "?"
        let subroleDescription = subrole.map { "/\($0)" } ?? ""
        let pressDescription = actions.contains(kAXPressAction as String) ? "[press]" : ""
        return "\(roleDescription)\(subroleDescription)\(pressDescription)"
    }

    private func describe(error: AXError) -> String {
        switch error {
        case .success:
            "success"
        case .failure:
            "failure"
        case .illegalArgument:
            "illegalArgument"
        case .invalidUIElement:
            "invalidUIElement"
        case .invalidUIElementObserver:
            "invalidUIElementObserver"
        case .cannotComplete:
            "cannotComplete"
        case .attributeUnsupported:
            "attributeUnsupported"
        case .actionUnsupported:
            "actionUnsupported"
        case .notificationUnsupported:
            "notificationUnsupported"
        case .notImplemented:
            "notImplemented"
        case .notificationAlreadyRegistered:
            "notificationAlreadyRegistered"
        case .notificationNotRegistered:
            "notificationNotRegistered"
        case .apiDisabled:
            "apiDisabled"
        case .noValue:
            "noValue"
        case .parameterizedAttributeUnsupported:
            "parameterizedAttributeUnsupported"
        case .notEnoughPrecision:
            "notEnoughPrecision"
        @unknown default:
            "unknown(\(error.rawValue))"
        }
    }

    private func logAccessibilityHit(initial: ActivationProbe, resolved: ActivationProbe) {
        let initialPointDescription = String(format: "(%.1f, %.1f)", initial.point.x, initial.point.y)
        let resolvedPointDescription = String(format: "(%.1f, %.1f)", resolved.point.x, resolved.point.y)
        let initialPathDescription = initial.hit.path.isEmpty ? "-" : initial.hit.path.joined(separator: " -> ")
        let resolvedPathDescription = resolved.hit.path.isEmpty ? "-" : resolved.hit.path.joined(separator: " -> ")

        if initial.hit.summary == resolved.hit.summary,
           initial.hit.path == resolved.hit.path,
           initial.point == resolved.point {
            os_log(
                "Auto scroll AX hit result=%{public}@ point=%{public}@ path=%{public}@",
                log: Self.log,
                type: .info,
                resolved.hit.summary,
                resolvedPointDescription,
                resolvedPathDescription
            )
            return
        }

        os_log(
            "Auto scroll AX hit initial=%{public}@ initialPoint=%{public}@ initialPath=%{public}@ resolved=%{public}@ resolvedPoint=%{public}@ resolvedPath=%{public}@",
            log: Self.log,
            type: .info,
            initial.hit.summary,
            initialPointDescription,
            initialPathDescription,
            resolved.hit.summary,
            resolvedPointDescription,
            resolvedPathDescription
        )
    }

    private func postDeferredNativeClick(from downEvent: CGEvent) {
        guard let eventButton = MouseEventView(downEvent).mouseButton else {
            return
        }

        let location = downEvent.location
        let flags = downEvent.flags

        guard let mouseDownEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: eventButton.fixedCGEventType(of: .leftMouseDown),
            mouseCursorPosition: location,
            mouseButton: eventButton
        ) else {
            return
        }

        guard let mouseUpEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: eventButton.fixedCGEventType(of: .leftMouseUp),
            mouseCursorPosition: location,
            mouseButton: eventButton
        ) else {
            return
        }

        mouseDownEvent.flags = flags
        mouseUpEvent.flags = flags
        mouseDownEvent.post(tap: .cgSessionEventTap)
        mouseUpEvent.post(tap: .cgSessionEventTap)
    }
}

private enum ActivationHit {
    case pressable(path: [String])
    case excludedChrome(path: [String])
    case nonPressable(path: [String])
    case unknown(reason: String, path: [String])

    var path: [String] {
        switch self {
        case let .pressable(path):
            path
        case let .excludedChrome(path):
            path
        case let .nonPressable(path):
            path
        case let .unknown(_, path):
            path
        }
    }

    var summary: String {
        switch self {
        case .pressable:
            "pressable"
        case .excludedChrome:
            "excludedChrome"
        case .nonPressable:
            "nonPressable"
        case let .unknown(reason, _):
            "unknown.\(reason)"
        }
    }

    var suppressesAutoscroll: Bool {
        switch self {
        case .pressable, .excludedChrome:
            true
        case .nonPressable, .unknown:
            false
        }
    }

    var requiresAdditionalSampling: Bool {
        switch self {
        case .nonPressable, .unknown:
            true
        case .pressable, .excludedChrome:
            false
        }
    }

    var priority: Int {
        switch self {
        case .pressable, .excludedChrome:
            3
        case .nonPressable:
            2
        case .unknown:
            1
        }
    }
}

private enum AccessibilityQueryResult<Value> {
    case success(Value)
    case failure(AXError)
}

private struct ActivationProbe {
    let point: CGPoint
    let hit: ActivationHit
}

extension AutoScrollTransformer: Deactivatable {
    func deactivate() {
        if isAutoscrollActive {
            os_log("Auto scroll deactivated", log: Self.log, type: .info)
        }

        state = .idle
        suppressTriggerUp = false
        indicatorController.hide()

        if let timer {
            timer.cancel()
            self.timer = nil
        }
    }
}

extension AutoScrollTransformer {
    func matchesConfiguration(
        trigger: Scheme.Buttons.Mapping,
        modes: [Scheme.Buttons.AutoScroll.Mode],
        speed: Double,
        preserveNativeMiddleClick: Bool
    ) -> Bool {
        self.trigger == trigger &&
            self.modes == modes &&
            abs(self.speed - speed) < 0.0001 &&
            self.preserveNativeMiddleClick == preserveNativeMiddleClick
    }
}

private final class AutoScrollIndicatorWindowController {
    private lazy var window: NSPanel = {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: autoScrollIndicatorSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = AutoScrollIndicatorView(frame: CGRect(origin: .zero, size: autoScrollIndicatorSize))
        return panel
    }()

    func show(at point: CGPoint) {
        let origin = CGPoint(
            x: point.x - autoScrollIndicatorSize.width / 2,
            y: point.y - autoScrollIndicatorSize.height / 2
        )
        window.setFrame(CGRect(origin: origin, size: autoScrollIndicatorSize), display: true)
        window.orderFrontRegardless()
    }

    func update(delta: CGVector) {
        (window.contentView as? AutoScrollIndicatorView)?.delta = delta
    }

    func hide() {
        window.orderOut(nil)
    }
}

private final class AutoScrollIndicatorView: NSView {
    var delta: CGVector = .zero {
        didSet {
            needsDisplay = true
        }
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = bounds
        let circleRect = bounds.insetBy(dx: 4, dy: 4)
        let ringPath = NSBezierPath(ovalIn: circleRect)

        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -1),
                blur: 10,
                color: NSColor.black.withAlphaComponent(0.18).cgColor
            )

            let gradient = NSGradient(
                colors: [
                    NSColor(white: 1.0, alpha: 0.97),
                    NSColor(white: 0.93, alpha: 0.95)
                ]
            )
            gradient?.draw(in: ringPath, angle: 90)
            context.restoreGState()
        }

        NSColor(white: 0.12, alpha: 0.48).setStroke()
        ringPath.lineWidth = 1
        ringPath.stroke()

        let innerRingPath = NSBezierPath(ovalIn: circleRect.insetBy(dx: 1.5, dy: 1.5))
        NSColor.white.withAlphaComponent(0.45).setStroke()
        innerRingPath.lineWidth = 1
        innerRingPath.stroke()

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let horizontalIntensity = CGFloat(min(1, max(0, (abs(delta.dx) - 10) / 44)))
        let verticalIntensity = CGFloat(min(1, max(0, (abs(delta.dy) - 10) / 44)))

        drawArrow(
            at: CGPoint(x: center.x, y: bounds.maxY - 13),
            direction: .up,
            intensity: delta.dy > 0 ? verticalIntensity : 0
        )
        drawArrow(
            at: CGPoint(x: bounds.maxX - 13, y: center.y),
            direction: .right,
            intensity: delta.dx > 0 ? horizontalIntensity : 0
        )
        drawArrow(
            at: CGPoint(x: center.x, y: bounds.minY + 13),
            direction: .down,
            intensity: delta.dy < 0 ? verticalIntensity : 0
        )
        drawArrow(
            at: CGPoint(x: bounds.minX + 13, y: center.y),
            direction: .left,
            intensity: delta.dx < 0 ? horizontalIntensity : 0
        )

        let crosshair = NSBezierPath()
        crosshair.move(to: CGPoint(x: center.x, y: bounds.minY + 11))
        crosshair.line(to: CGPoint(x: center.x, y: bounds.maxY - 11))
        crosshair.move(to: CGPoint(x: bounds.minX + 11, y: center.y))
        crosshair.line(to: CGPoint(x: bounds.maxX - 11, y: center.y))
        NSColor(white: 0.1, alpha: 0.14).setStroke()
        crosshair.lineWidth = 1
        crosshair.stroke()

        let centerShadowRect = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
        let centerShadowPath = NSBezierPath(ovalIn: centerShadowRect)
        NSColor.black.withAlphaComponent(0.14).setFill()
        centerShadowPath.fill()

        let dotRect = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        NSColor(white: 0.07, alpha: 0.96).setFill()
        dotPath.fill()

        let highlightRect = CGRect(x: center.x - 1.5, y: center.y + 1, width: 3, height: 2)
        let highlightPath = NSBezierPath(ovalIn: highlightRect)
        NSColor.white.withAlphaComponent(0.28).setFill()
        highlightPath.fill()
    }

    private func drawArrow(at center: CGPoint, direction: Direction, intensity: CGFloat) {
        let path = NSBezierPath()

        switch direction {
        case .up:
            path.move(to: CGPoint(x: center.x, y: center.y + 6))
            path.line(to: CGPoint(x: center.x - 4.5, y: center.y - 3))
            path.line(to: CGPoint(x: center.x + 4.5, y: center.y - 3))
        case .right:
            path.move(to: CGPoint(x: center.x + 6, y: center.y))
            path.line(to: CGPoint(x: center.x - 3, y: center.y + 4.5))
            path.line(to: CGPoint(x: center.x - 3, y: center.y - 4.5))
        case .down:
            path.move(to: CGPoint(x: center.x, y: center.y - 6))
            path.line(to: CGPoint(x: center.x - 4.5, y: center.y + 3))
            path.line(to: CGPoint(x: center.x + 4.5, y: center.y + 3))
        case .left:
            path.move(to: CGPoint(x: center.x - 6, y: center.y))
            path.line(to: CGPoint(x: center.x + 3, y: center.y + 4.5))
            path.line(to: CGPoint(x: center.x + 3, y: center.y - 4.5))
        }

        path.close()

        let alpha = 0.26 + Double(intensity) * 0.68
        NSColor(white: 0.04, alpha: alpha).setFill()
        path.fill()

        NSColor.white.withAlphaComponent(0.18 + Double(intensity) * 0.12).setStroke()
        path.lineWidth = 0.7
        path.stroke()
    }

    private enum Direction {
        case up
        case right
        case down
        case left
    }
}
