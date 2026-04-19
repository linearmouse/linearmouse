// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import os.log

final class SmoothedScrollingTransformer: EventTransformer, Deactivatable {
    private static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier!, category: "SmoothedScrolling"
    )
    private static let timerInterval: TimeInterval = 1.0 / 120.0
    private let smoothed: Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Smoothed>
    private let now: () -> TimeInterval
    private let eventSink: (CGEvent) -> Void
    private let delivery = SmoothedScrollEventDelivery()

    private var engine: SmoothedScrollingEngine
    private var timer: EventThreadTimer?
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

    func transform(_ event: CGEvent) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        let view = ScrollWheelEventView(event)

        if event.isLinearMouseSyntheticEvent {
            return event
        }

        let deltaX = delivery.deltaXInPixels(from: view)
        let deltaY = delivery.deltaYInPixels(from: view)
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
            delivery.zeroHorizontal(on: passthroughView)
        }
        if interceptsY {
            delivery.zeroVertical(on: passthroughView)
        }

        return delivery.deltaXInPixels(from: passthroughView) == 0
            && delivery.deltaYInPixels(from: passthroughView) == 0
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

        timer = EventThread.shared.scheduleTimer(
            interval: Self.timerInterval,
            repeats: true
        ) { [weak self] in
            self?.tick()
        }
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
            delivery.apply(phases: delivery.phasesFor(emission.phase), to: view)

            if interceptsX {
                delivery.setHorizontal(handlesX ? emission.deltaX : 0, on: view)
            }
            if interceptsY {
                delivery.setVertical(handlesY ? emission.deltaY : 0, on: view)
            }
        } else {
            if interceptsX, !handlesX {
                delivery.zeroHorizontal(on: view)
            }
            if interceptsY, !handlesY {
                delivery.zeroVertical(on: view)
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
        delivery.setHorizontal(emission.deltaX, on: view)
        delivery.setVertical(emission.deltaY, on: view)
        delivery.apply(phases: delivery.phasesFor(emission.phase), to: view)
        event.isLinearMouseSyntheticEvent = true
        event.flags = lastFlags
        eventSink(event)

        os_log(
            "post smoothed scroll deltaX=%{public}.3f deltaY=%{public}.3f phase=%{public}@ momentum=%{public}@",
            log: Self.log,
            type: .info,
            emission.deltaX,
            emission.deltaY,
            String(describing: view.scrollPhase),
            String(describing: view.momentumPhase)
        )
    }
}

private struct SmoothedScrollEventDelivery {
    private static let inputLineStepInPoints = 36.0
    private static let outputLineStepInPoints = 12.0

    func apply(
        phases: (scrollPhase: CGScrollPhase?, momentumPhase: CGMomentumScrollPhase),
        to view: ScrollWheelEventView
    ) {
        view.scrollPhase = phases.scrollPhase
        view.momentumPhase = phases.momentumPhase
    }

    func phasesFor(_ phase: SmoothedScrollingEngine
        .Phase) -> (scrollPhase: CGScrollPhase?, momentumPhase: CGMomentumScrollPhase) {
        switch phase {
        case .touchBegan:
            return (.began, .none)
        case .touchChanged:
            return (.changed, .none)
        case .touchEnded:
            return (.ended, .none)
        case .momentumBegan:
            return (nil, .begin)
        case .momentumChanged:
            return (nil, .continuous)
        case .momentumEnded:
            return (nil, .end)
        }
    }

    func deltaXInPixels(from view: ScrollWheelEventView) -> Double {
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

    func deltaYInPixels(from view: ScrollWheelEventView) -> Double {
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

    func setHorizontal(_ value: Double, on view: ScrollWheelEventView) {
        view.deltaX = integerDelta(for: value)
        view.deltaXPt = pointDelta(for: value)
        view.deltaXFixedPt = value
        view.ioHidScrollX = value
    }

    func setVertical(_ value: Double, on view: ScrollWheelEventView) {
        view.deltaY = integerDelta(for: value)
        view.deltaYPt = pointDelta(for: value)
        view.deltaYFixedPt = value
        view.ioHidScrollY = value
    }

    func zeroHorizontal(on view: ScrollWheelEventView) {
        setHorizontal(0, on: view)
    }

    func zeroVertical(on view: ScrollWheelEventView) {
        setVertical(0, on: view)
    }

    private func integerDelta(for value: Double) -> Int64 {
        Int64((value / Self.outputLineStepInPoints).rounded(.towardZero))
    }

    private func pointDelta(for value: Double) -> Double {
        guard value != 0 else {
            return 0
        }

        return Double(Int64(value.rounded(.towardZero)))
    }
}
