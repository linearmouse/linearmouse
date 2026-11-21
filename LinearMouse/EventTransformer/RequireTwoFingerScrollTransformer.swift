// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import QuartzCore

/// Suppresses Magic Mouse scroll events unless at least two fingers are on
/// the touch surface, mimicking a trackpad's requirement for two-finger
/// scrolling instead of the Magic Mouse's default of scrolling on any single
/// finger contact.
///
/// This must run before any other scroll transformer (smoothing, reverse,
/// acceleration, etc.), since a suppressed one-finger scroll should never
/// reach the rest of the pipeline.
///
/// Gating is based on live finger count for every event - deliberately NOT
/// on `CGMomentumScrollPhase`. A trackpad reserves that field for the
/// post-lift inertial tail, but the Magic Mouse has no real gesture-phase
/// concept: empirically, it tags most actively-touched scroll ticks
/// (not just the glide after lift-off) as "momentum changed". Trusting that
/// field let the vast majority of real one-finger scrolling straight
/// through. Instead, this transformer tracks its own notion of "was the
/// in-flight gesture qualified with two fingers", so a real two-finger
/// scroll still glides to a natural stop after lift-off, without that grace
/// period leaking into unrelated one-finger scrolling later.
/// The live finger-count signal `RequireTwoFingerScrollTransformer` gates
/// on. `MagicMouseTouchTracker` is the real implementation; tests substitute
/// a fake so they don't need a real Magic Mouse or the private
/// `MultitouchSupport.framework` bridge behind it.
protocol MagicMouseTouchProviding {
    var isAvailable: Bool { get }
    var fingerCount: Int { get }
}

extension MagicMouseTouchTracker: MagicMouseTouchProviding {}

class RequireTwoFingerScrollTransformer: EventTransformer {
    /// A gap this long between scroll ticks is treated as the end of one
    /// gesture and the start of another, even if the device never sends an
    /// explicit `.end` momentum phase for the previous one.
    private static let gestureGapThreshold: CFTimeInterval = 0.3

    private let touchTracker: MagicMouseTouchProviding
    private let now: () -> CFTimeInterval

    private var lastGestureQualified = false
    private var lastEventTime: CFTimeInterval?

    init(
        touchTracker: MagicMouseTouchProviding = MagicMouseTouchTracker.shared,
        now: @escaping () -> CFTimeInterval = CACurrentMediaTime
    ) {
        self.touchTracker = touchTracker
        self.now = now
    }

    func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        if event.isLinearMouseSyntheticEvent {
            return event
        }

        // If we don't have a trustworthy finger-count signal (private API
        // unavailable, device not found yet, etc.), fail open rather than
        // silently break scrolling.
        guard touchTracker.isAvailable else {
            return event
        }

        let currentTime = now()
        defer { lastEventTime = currentTime }
        if let lastEventTime, currentTime - lastEventTime > Self.gestureGapThreshold {
            lastGestureQualified = false
        }

        let fingerCount = touchTracker.fingerCount

        if fingerCount >= 2 {
            lastGestureQualified = true
            return event
        }

        if lastGestureQualified {
            // Let this gesture's momentum glide to a stop even though the
            // fingers that started it have now lifted. A genuine explicit
            // "momentum ended" tag closes this out immediately; otherwise
            // the gap-based check above will once ticks stop arriving.
            let momentumPhase = ScrollWheelEventView(event).momentumPhase
            if momentumPhase == .end {
                lastGestureQualified = false
            }
            return event
        }

        return nil
    }
}
