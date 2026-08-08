// MIT License
// Copyright (c) 2021-2026 LinearMouse

import AppKit
import DockKit
import Foundation
import GestureKit
import KeyKit
import os.log

final class ButtonActionExecutor {
    typealias RepeatTimings = (delay: TimeInterval, interval: TimeInterval)
    typealias RepeatTimingProvider = () -> RepeatTimings
    typealias TimerScheduler = (TimeInterval, Bool, @escaping () -> Void) -> TimerToken?

    final class TimerToken {
        private var invalidateHandler: (() -> Void)?

        init(invalidate: @escaping () -> Void) {
            invalidateHandler = invalidate
        }

        deinit {
            invalidate()
        }

        func invalidate() {
            invalidateHandler?()
            invalidateHandler = nil
        }
    }

    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ButtonActions")

    final class RuntimeState {
        var repeatTimers = [Set<Scheme.Buttons.Mapping.Button>: TimerToken]()
        var pendingReleaseActions = [
            Set<Scheme.Buttons.Mapping.Button>: (Scheme.Buttons.Mapping.Action, String?)
        ]()
        var heldKeys = [Set<Scheme.Buttons.Mapping.Button>: [Key]]()
        var heldKeyReferenceCounts = [Key: Int]()
        var heldKeyOrder = [Key]()
    }

    let universalBackForward: Scheme.Buttons.UniversalBackForward?
    let runtimeState: RuntimeState
    private let repeatTimingProvider: RepeatTimingProvider
    private let scheduleTimer: TimerScheduler

    private static let defaultKeySimulator = KeySimulator()
    let keySimulator: KeySimulating

    init(
        universalBackForward: Scheme.Buttons.UniversalBackForward? = nil,
        runtimeState: RuntimeState = .init(),
        keySimulator: KeySimulating? = nil,
        repeatTimingProvider: @escaping RepeatTimingProvider = ButtonActionExecutor.systemRepeatTimings,
        scheduleTimer: @escaping TimerScheduler = ButtonActionExecutor.scheduleEventThreadTimer
    ) {
        self.universalBackForward = universalBackForward
        self.runtimeState = runtimeState
        self.keySimulator = keySimulator ?? Self.defaultKeySimulator
        self.repeatTimingProvider = repeatTimingProvider
        self.scheduleTimer = scheduleTimer
    }

    private static func systemRepeatTimings() -> RepeatTimings {
        (
            delay: KeyboardSettingsSnapshot.shared.keyRepeatDelay,
            interval: KeyboardSettingsSnapshot.shared.keyRepeatInterval
        )
    }

    private static func scheduleEventThreadTimer(
        interval: TimeInterval,
        repeats: Bool,
        handler: @escaping () -> Void
    ) -> TimerToken? {
        guard let timer = EventThread.shared.scheduleTimer(
            interval: interval,
            repeats: repeats,
            handler: handler
        ) else {
            return nil
        }
        return .init {
            timer.invalidate()
        }
    }
}

extension ButtonActionExecutor {
    func perform(
        _ action: Scheme.Buttons.Mapping.Action,
        targetBundleIdentifier: String?
    ) {
        DispatchQueue.main.async { [self] in
            executeIgnoreErrors(action: action, targetBundleIdentifier: targetBundleIdentifier)
        }
    }

    func beginPress(
        _ pressAction: Scheme.Buttons.Mapping.PressAction,
        buttons: Set<Scheme.Buttons.Mapping.Button>,
        targetBundleIdentifier: String?
    ) {
        switch pressAction.behavior {
        case .perform:
            perform(pressAction.action, targetBundleIdentifier: targetBundleIdentifier)

        case .repeat:
            let (delay, interval) = repeatTimingProvider()
            guard delay > 0, interval > 0 else {
                runtimeState.pendingReleaseActions[buttons] = (
                    pressAction.action,
                    targetBundleIdentifier
                )
                return
            }
            scheduleRepeatActions(
                action: pressAction.action,
                buttons: buttons,
                targetBundleIdentifier: targetBundleIdentifier,
                delay: delay,
                interval: interval
            )

        case .hold:
            guard case let .arg1(.keyPress(keys)) = pressAction.action,
                  runtimeState.heldKeys[buttons] == nil else {
                return
            }
            runtimeState.heldKeys[buttons] = keys
            let keysToPress = keys.filter { key in
                let referenceCount = runtimeState.heldKeyReferenceCounts[key, default: 0]
                runtimeState.heldKeyReferenceCounts[key] = referenceCount + 1
                if referenceCount == 0 {
                    runtimeState.heldKeyOrder.append(key)
                    return true
                }
                return false
            }
            if !keysToPress.isEmpty {
                os_log("Down keys: %{public}@", log: Self.log, type: .info, String(describing: keysToPress))
                try? keySimulator.down(keys: keysToPress, tap: .cgSessionEventTap)
            }

        case .remap:
            break
        }
    }

    func endPress(
        _ pressAction: Scheme.Buttons.Mapping.PressAction,
        buttons: Set<Scheme.Buttons.Mapping.Button>
    ) {
        switch pressAction.behavior {
        case .perform, .remap:
            break

        case .repeat:
            runtimeState.repeatTimers.removeValue(forKey: buttons)?.invalidate()
            if let (action, targetBundleIdentifier) = runtimeState.pendingReleaseActions.removeValue(
                forKey: buttons
            ) {
                perform(action, targetBundleIdentifier: targetBundleIdentifier)
            }

        case .hold:
            guard case let .arg1(.keyPress(fallbackKeys)) = pressAction.action else {
                return
            }
            guard let keys = runtimeState.heldKeys.removeValue(forKey: buttons) else {
                os_log("Up keys: %{public}@", log: Self.log, type: .info, String(describing: fallbackKeys))
                try? keySimulator.up(keys: fallbackKeys.reversed(), tap: .cgSessionEventTap)
                resetKeySimulatorIfNothingIsHeld()
                return
            }
            let keysToRelease = keys.reversed().filter { key in
                guard let referenceCount = runtimeState.heldKeyReferenceCounts[key] else {
                    return true
                }
                if referenceCount > 1 {
                    runtimeState.heldKeyReferenceCounts[key] = referenceCount - 1
                    return false
                }
                runtimeState.heldKeyReferenceCounts[key] = nil
                runtimeState.heldKeyOrder.removeAll { $0 == key }
                return true
            }
            if !keysToRelease.isEmpty {
                os_log("Up keys: %{public}@", log: Self.log, type: .info, String(describing: keysToRelease))
                try? keySimulator.up(keys: Array(keysToRelease), tap: .cgSessionEventTap)
            }
            resetKeySimulatorIfNothingIsHeld()
        }
    }

    private func focusedWindow() -> AXUIElement? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &value
        )

        guard result == .success,
              let value else {
            return nil
        }

        return value as! AXUIElement
    }

    private func windowFrame(_ window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
            AXUIElementCopyAttributeValue(
                window,
                kAXSizeAttribute as CFString,
                &sizeValue
            ) == .success,
            let positionValue,
            let sizeValue else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(
            positionValue as! AXValue,
            .cgPoint,
            &position
        ),
            AXValueGetValue(
                sizeValue as! AXValue,
                .cgSize,
                &size
            ) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func screenForWindow(_ window: AXUIElement) -> NSScreen? {
        guard let frame = windowFrame(window) else {
            return NSScreen.main
        }

        return NSScreen.screens.max {
            $0.frame.intersection(frame).area
                < $1.frame.intersection(frame).area
        }
    }

    private func maximizeFocusedWindow() {
        guard let window = focusedWindow(),
              let screen = screenForWindow(window) else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let screenFrame = screen.frame

        var position = CGPoint(
            x: visibleFrame.minX,
            y: screenFrame.maxY - visibleFrame.maxY
        )

        var size = visibleFrame.size

        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return
        }

        AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            positionValue
        )

        AXUIElementSetAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            sizeValue
        )
    }

    private func minimizeFocusedWindow() {
        guard let window = focusedWindow() else {
            return
        }

        AXUIElementSetAttributeValue(
            window,
            kAXMinimizedAttribute as CFString,
            kCFBooleanTrue
        )
    }

    private func scheduleRepeatActions(
        action: Scheme.Buttons.Mapping.Action,
        buttons: Set<Scheme.Buttons.Mapping.Button>,
        targetBundleIdentifier: String?,
        delay: TimeInterval,
        interval: TimeInterval
    ) {
        runtimeState.repeatTimers.removeValue(forKey: buttons)?.invalidate()
        DispatchQueue.main.async { [self] in
            executeIgnoreErrors(action: action, targetBundleIdentifier: targetBundleIdentifier)
        }

        if let timer = scheduleTimer(delay, false, { [weak self] in
            guard let self else {
                return
            }
            DispatchQueue.main.async { [self] in
                self.executeIgnoreErrors(action: action, targetBundleIdentifier: targetBundleIdentifier)
            }
            if let timer = scheduleTimer(interval, true, { [weak self] in
                guard let self else {
                    return
                }
                DispatchQueue.main.async { [self] in
                    self.executeIgnoreErrors(action: action, targetBundleIdentifier: targetBundleIdentifier)
                }
            }) {
                runtimeState.repeatTimers[buttons] = timer
            }
        }) {
            runtimeState.repeatTimers[buttons] = timer
        }
    }

    private func executeIgnoreErrors(
        action: Scheme.Buttons.Mapping.Action,
        targetBundleIdentifier: String?
    ) {
        do {
            os_log(
                "Execute action: %{public}@",
                log: Self.log,
                type: .info,
                String(describing: action)
            )

            try execute(action: action, targetBundleIdentifier: targetBundleIdentifier)
        } catch {
            os_log(
                "Failed to execute: %{public}@: %{public}@",
                log: Self.log,
                type: .error,
                String(describing: action),
                String(describing: error)
            )
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func execute(
        action: Scheme.Buttons.Mapping.Action,
        targetBundleIdentifier: String?
    ) throws {
        switch action {
        case .arg0(.none), .arg0(.auto):
            return

        case .arg0(.missionControlSpaceLeft):
            try postSymbolicHotKey(.spaceLeft)

        case .arg0(.missionControlSpaceRight):
            try postSymbolicHotKey(.spaceRight)

        case .arg0(.missionControl):
            missionControl()

        case .arg0(.appExpose):
            appExpose()

        case .arg0(.launchpad):
            launchpad()

        case .arg0(.showDesktop):
            showDesktop()

        case .arg0(.lookUpAndDataDetectors):
            try postSymbolicHotKey(.lookUpWordInDictionary)

        case .arg0(.smartZoom):
            GestureEvent(zoomToggleSource: nil)?.post(tap: .cgSessionEventTap)

        case .arg0(.windowMaximize):
            maximizeFocusedWindow()

        case .arg0(.windowMinimize):
            minimizeFocusedWindow()

        case .arg0(.displayBrightnessUp):
            postSystemDefinedKey(.brightnessUp)

        case .arg0(.displayBrightnessDown):
            postSystemDefinedKey(.brightnessDown)

        case .arg0(.mediaVolumeUp):
            postSystemDefinedKey(.soundUp)

        case .arg0(.mediaVolumeDown):
            postSystemDefinedKey(.soundDown)

        case .arg0(.mediaMute):
            postSystemDefinedKey(.mute)

        case .arg0(.mediaPlayPause):
            postSystemDefinedKey(.play)

        case .arg0(.mediaNext):
            postSystemDefinedKey(.next)

        case .arg0(.mediaPrevious):
            postSystemDefinedKey(.previous)

        case .arg0(.mediaFastForward):
            postSystemDefinedKey(.fast)

        case .arg0(.mediaRewind):
            postSystemDefinedKey(.rewind)

        case .arg0(.keyboardBrightnessUp):
            postSystemDefinedKey(.illuminationUp)

        case .arg0(.keyboardBrightnessDown):
            postSystemDefinedKey(.illuminationDown)

        case .arg0(.mouseWheelScrollUp):
            postScrollEvent(horizontal: 0, vertical: 3)

        case .arg0(.mouseWheelScrollDown):
            postScrollEvent(horizontal: 0, vertical: -3)

        case .arg0(.mouseWheelScrollLeft):
            postScrollEvent(horizontal: 3, vertical: 0)

        case .arg0(.mouseWheelScrollRight):
            postScrollEvent(horizontal: -3, vertical: 0)

        case .arg0(.mouseButtonLeft):
            postClickEvent(mouseButton: .left)

        case .arg0(.mouseButtonLeftDouble):
            postClickEvent(mouseButton: .left)
            postClickEvent(mouseButton: .left, clickState: 2)

        case .arg0(.mouseButtonMiddle):
            postClickEvent(mouseButton: .center)

        case .arg0(.mouseButtonRight):
            postClickEvent(mouseButton: .right)

        case .arg0(.mouseButtonBack):
            postMouseButtonAction(mouseButton: .back, targetBundleIdentifier: targetBundleIdentifier)

        case .arg0(.mouseButtonForward):
            postMouseButtonAction(mouseButton: .forward, targetBundleIdentifier: targetBundleIdentifier)

        case let .arg1(.run(command)):
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", command]
            task.launch()

        case let .arg1(.mouseWheelScrollUp(distance)):
            postScrollEvent(direction: .up, distance: distance)

        case let .arg1(.mouseWheelScrollDown(distance)):
            postScrollEvent(direction: .down, distance: distance)

        case let .arg1(.mouseWheelScrollLeft(distance)):
            postScrollEvent(direction: .left, distance: distance)

        case let .arg1(.mouseWheelScrollRight(distance)):
            postScrollEvent(direction: .right, distance: distance)

        case let .arg1(.keyPress(keys)):
            try keySimulator.press(keys: keys, tap: .cgSessionEventTap)
            keySimulator.reset()
        }
    }

    private func postMouseButtonAction(
        mouseButton: CGMouseButton,
        targetBundleIdentifier: String?
    ) {
        guard !UniversalBackForwardTransformer.postNavigationSwipeIfNeeded(
            for: mouseButton,
            universalBackForward: universalBackForward,
            targetBundleIdentifier: targetBundleIdentifier
        ) else {
            return
        }

        postClickEvent(mouseButton: mouseButton)
    }

    private func postScrollEvent(horizontal: Int32, vertical: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: vertical,
            wheel2: horizontal,
            wheel3: 0
        ) else {
            return
        }

        event.flags = []
        event.post(tap: .cgSessionEventTap)
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

    private enum ScrollEventDirection {
        case up, down, left, right
    }

    private func postScrollEvent(
        direction: ScrollEventDirection,
        distance: Scheme.Scrolling.Distance
    ) {
        switch distance {
        case .auto:
            switch direction {
            case .up:
                postScrollEvent(horizontal: 0, vertical: 3)
            case .down:
                postScrollEvent(horizontal: 0, vertical: -3)
            case .left:
                postScrollEvent(horizontal: 3, vertical: 0)
            case .right:
                postScrollEvent(horizontal: -3, vertical: 0)
            }

        case let .line(value):
            let value = Int32(value)

            switch direction {
            case .up:
                postScrollEvent(horizontal: 0, vertical: value)
            case .down:
                postScrollEvent(horizontal: 0, vertical: -value)
            case .left:
                postScrollEvent(horizontal: value, vertical: 0)
            case .right:
                postScrollEvent(horizontal: -value, vertical: 0)
            }

        case let .pixel(value):
            let value = value.asTruncatedDouble

            switch direction {
            case .up:
                postContinuousScrollEvent(horizontal: 0, vertical: value)
            case .down:
                postContinuousScrollEvent(horizontal: 0, vertical: -value)
            case .left:
                postContinuousScrollEvent(horizontal: value, vertical: 0)
            case .right:
                postContinuousScrollEvent(horizontal: -value, vertical: 0)
            }
        }
    }

    private func resetKeySimulatorIfNothingIsHeld() {
        if runtimeState.heldKeyReferenceCounts.isEmpty {
            keySimulator.reset()
        }
    }

    private func postClickEvent(mouseButton: CGMouseButton, clickState: Int64? = nil) {
        guard let location = CGEvent(source: nil)?.location else {
            return
        }

        guard let mouseDownEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: mouseButton.fixedCGEventType(of: .leftMouseDown),
            mouseCursorPosition: location,
            mouseButton: mouseButton
        ) else {
            return
        }
        guard let mouseUpEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: mouseButton.fixedCGEventType(of: .leftMouseUp),
            mouseCursorPosition: location,
            mouseButton: mouseButton
        ) else {
            return
        }

        if let clickState {
            mouseDownEvent.setIntegerValueField(.mouseEventClickState, value: clickState)
            mouseUpEvent.setIntegerValueField(.mouseEventClickState, value: clickState)
        }

        mouseDownEvent.post(tap: .cgSessionEventTap)
        mouseUpEvent.post(tap: .cgSessionEventTap)
    }
}

extension ButtonActionExecutor: Deactivatable {
    func deactivate() {
        for timer in runtimeState.repeatTimers.values {
            timer.invalidate()
        }
        runtimeState.repeatTimers.removeAll()
        runtimeState.pendingReleaseActions.removeAll()

        let heldKeys = Array(runtimeState.heldKeyOrder.reversed())
        runtimeState.heldKeys.removeAll()
        runtimeState.heldKeyReferenceCounts.removeAll()
        runtimeState.heldKeyOrder.removeAll()
        if !heldKeys.isEmpty {
            try? keySimulator.up(keys: heldKeys, tap: .cgSessionEventTap)
            keySimulator.reset()
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        width * height
    }
}
