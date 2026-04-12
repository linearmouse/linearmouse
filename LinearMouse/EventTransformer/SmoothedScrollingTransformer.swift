// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import os.log

final class SmoothedScrollingTransformer: EventTransformer, Deactivatable {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier!, category: "SmoothedScrolling"
    )
    private static let timerInterval: TimeInterval = 1.0 / 120.0
    private static let inputLineStepInPoints = 36.0
    private static let outputLineStepInPoints = 12.0

    private let smoothed: Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Smoothed>
    private let now: () -> TimeInterval
    private let eventSink: (CGEvent) -> Void

    private var engine: SmoothedScrollingEngine
    private var timer: Timer?
    private var lastFlags: CGEventFlags = []

    init(
        smoothed: Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Smoothed>,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        eventSink: @escaping (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) }
    ) {
        self.smoothed = smoothed
        self.now = now
        self.eventSink = eventSink
        engine = SmoothedScrollingEngine(smoothed: smoothed)
    }

    deinit {
        // Timer is held by the RunLoop even after this object is released (e.g. cache clear).
        // Dispatch invalidation to the event thread where the timer was created.
        let timer = self.timer
        if let timer {
            GlobalEventTap.performOnEventThread {
                timer.invalidate()
            }
        }
    }

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        let view = ScrollWheelEventView(event)

        if event.isLinearMouseSyntheticEvent {
            return event
        }

        let deltaX = deltaXInPixels(from: view)
        let deltaY = deltaYInPixels(from: view)
        let hasNativePhase = view.scrollPhase != nil
        let hasNativeMomentum = view.momentumPhase != .none

        let smoothsX = smoothed.horizontal != nil
        let smoothsY = smoothed.vertical != nil
        let handlesX = smoothsX && deltaX != 0
        let handlesY = smoothsY && deltaY != 0
        let interceptsX = smoothsX && deltaX != 0
        let interceptsY = smoothsY && deltaY != 0

        if view.continuous, hasNativePhase || hasNativeMomentum {
            return transformNativeContinuousGesture(
                event,
                view: view,
                deltaX: deltaX,
                deltaY: deltaY,
                handlesX: handlesX,
                handlesY: handlesY
            )
        }

        guard interceptsX || interceptsY else {
            return event
        }

        if handlesX || handlesY {
            lastFlags = event.flags
            if handlesX != handlesY {
                engine.resetOtherAxis(ifExclusiveIncomingAxis: handlesX ? .horizontal : .vertical)
            }
            engine.feed(
                deltaX: handlesX ? deltaX : 0,
                deltaY: handlesY ? deltaY : 0,
                timestamp: now()
            )
            startTimerIfNeeded()
        }

        let passthroughEvent = event.copy() ?? event
        let passthroughView = ScrollWheelEventView(passthroughEvent)
        if interceptsX {
            zeroHorizontal(on: passthroughView)
        }
        if interceptsY {
            zeroVertical(on: passthroughView)
        }

        return deltaXInPixels(from: passthroughView) == 0
            && deltaYInPixels(from: passthroughView) == 0
            ? nil
            : passthroughEvent
    }

    func deactivate() {
        stopTimer()
        engine = SmoothedScrollingEngine(smoothed: smoothed)
        lastFlags = []
    }

    private func startTimerIfNeeded() {
        guard timer == nil else {
            return
        }

        guard let runLoop = GlobalEventTap.processingRunLoop else {
            return
        }

        let timer = Timer(timeInterval: Self.timerInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        runLoop.add(timer, forMode: .common)
        self.timer = timer
    }

    private func transformNativeContinuousGesture(
        _ event: CGEvent,
        view: ScrollWheelEventView,
        deltaX: Double,
        deltaY: Double,
        handlesX: Bool,
        handlesY: Bool
    ) -> CGEvent? {
        let interceptsX = smoothed.horizontal != nil
        let interceptsY = smoothed.vertical != nil
        let ensureVisibleTouchDelta = view.scrollPhase == .began || view.scrollPhase == .changed

        guard interceptsX || interceptsY else {
            return event
        }

        lastFlags = event.flags

        if handlesX || handlesY {
            if handlesX != handlesY {
                engine.resetOtherAxis(ifExclusiveIncomingAxis: handlesX ? .horizontal : .vertical)
            }
            engine.feed(
                deltaX: handlesX ? deltaX : 0,
                deltaY: handlesY ? deltaY : 0,
                timestamp: now()
            )
        }

        if let emission = engine.advance(to: now()) {
            if interceptsX {
                setHorizontal(
                    handlesX ? emission.deltaX : 0,
                    on: view,
                    ensureVisiblePointDelta: ensureVisibleTouchDelta
                )
            }
            if interceptsY {
                setVertical(
                    handlesY ? emission.deltaY : 0,
                    on: view,
                    ensureVisiblePointDelta: ensureVisibleTouchDelta
                )
            }
        } else {
            if interceptsX, !handlesX {
                zeroHorizontal(on: view)
            }
            if interceptsY, !handlesY {
                zeroVertical(on: view)
            }
        }

        let shouldReset = view.scrollPhase == .ended || view.momentumPhase == .end
        if shouldReset {
            engine = SmoothedScrollingEngine(smoothed: smoothed)
            stopTimer()
        }

        return event
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func tick() {
        guard let emission = engine.advance(to: now()) else {
            if !engine.isRunning {
                stopTimer()
            }
            return
        }

        post(emission: emission)

        if !engine.isRunning {
            stopTimer()
        }
    }

    private func post(emission: SmoothedScrollingEngine.Emission) {
        guard
            let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: 0,
                wheel2: 0,
                wheel3: 0
            )
        else {
            return
        }

        let view = ScrollWheelEventView(event)
        view.continuous = true
        setHorizontal(emission.deltaX, on: view)
        setVertical(emission.deltaY, on: view)
        view.scrollPhase = emission.scrollPhase
        view.momentumPhase = emission.momentumPhase
        event.isLinearMouseSyntheticEvent = true
        event.flags = lastFlags
        eventSink(event)

        os_log(
            "post smoothed scroll deltaX=%{public}.3f deltaY=%{public}.3f phase=%{public}@ momentum=%{public}@",
            log: Self.log,
            type: .info,
            emission.deltaX,
            emission.deltaY,
            String(describing: emission.scrollPhase),
            String(describing: emission.momentumPhase)
        )
    }

    private func deltaXInPixels(from view: ScrollWheelEventView) -> Double {
        if !view.continuous {
            if view.deltaX != 0 {
                return Double(view.deltaX) * Self.inputLineStepInPoints
            }
            if view.deltaXPt != 0 {
                return view.deltaXPt * Self.inputLineStepInPoints
            }
            if view.deltaXFixedPt != 0 {
                return view.deltaXFixedPt * Self.inputLineStepInPoints * 10
            }
        }
        if view.deltaXPt != 0 {
            return view.deltaXPt
        }
        if view.deltaXFixedPt != 0 {
            return view.deltaXFixedPt
        }
        return Double(view.deltaX) * Self.inputLineStepInPoints
    }

    private func deltaYInPixels(from view: ScrollWheelEventView) -> Double {
        if !view.continuous {
            if view.deltaY != 0 {
                return Double(view.deltaY) * Self.inputLineStepInPoints
            }
            if view.deltaYPt != 0 {
                return view.deltaYPt * Self.inputLineStepInPoints
            }
            if view.deltaYFixedPt != 0 {
                return view.deltaYFixedPt * Self.inputLineStepInPoints * 10
            }
        }
        if view.deltaYPt != 0 {
            return view.deltaYPt
        }
        if view.deltaYFixedPt != 0 {
            return view.deltaYFixedPt
        }
        return Double(view.deltaY) * Self.inputLineStepInPoints
    }

    private func setHorizontal(
        _ value: Double,
        on view: ScrollWheelEventView,
        ensureVisiblePointDelta: Bool = false
    ) {
        view.deltaX = integerDelta(for: value)
        view.deltaXPt = pointDelta(for: value, ensureVisible: ensureVisiblePointDelta)
        view.deltaXFixedPt = value
        view.ioHidScrollX = value
    }

    private func setVertical(
        _ value: Double,
        on view: ScrollWheelEventView,
        ensureVisiblePointDelta: Bool = false
    ) {
        view.deltaY = integerDelta(for: value)
        view.deltaYPt = pointDelta(for: value, ensureVisible: ensureVisiblePointDelta)
        view.deltaYFixedPt = value
        view.ioHidScrollY = value
    }

    private func zeroHorizontal(on view: ScrollWheelEventView) {
        setHorizontal(0, on: view)
    }

    private func zeroVertical(on view: ScrollWheelEventView) {
        setVertical(0, on: view)
    }

    private func integerDelta(for value: Double) -> Int64 {
        Int64((value / Self.outputLineStepInPoints).rounded(.towardZero))
    }

    private func pointDelta(for value: Double, ensureVisible: Bool) -> Double {
        guard value != 0 else {
            return 0
        }

        let truncated = Double(Int64(value.rounded(.towardZero)))
        if truncated != 0 {
            return truncated
        }

        return ensureVisible ? (value.sign == .minus ? -1 : 1) : 0
    }
}
