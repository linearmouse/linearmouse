// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Turns horizontal wheel movement into the Dock's interactive swipe between
/// spaces, so the space follows the wheel like a trackpad swipe and snaps to
/// the nearest space once the wheel stops.
///
/// Each route applies its own scheme's settings, but feeds the device's shared
/// `SpaceSwipeSession`, so a swipe continues when it changes the app under the
/// pointer. The transformer itself is stateless and claims no interaction.
final class SpaceSwipeTransformer: EventTransformer {
    /// Line-equivalent of continuous (pixel) horizontal scrolling.
    private static let pointsPerLine = 10.0
    /// Positive wheel deltas mean "left"; the Dock moves left on negative progress.
    private static let progressSign = -1.0

    private let distance: Double
    private let releaseDelay: TimeInterval
    private let session: SpaceSwipeSession
    private let isRecording: () -> Bool

    init(
        distance: Double,
        releaseDelay: TimeInterval,
        session: SpaceSwipeSession,
        isRecording: @escaping () -> Bool = { SettingsState.shared.recording }
    ) {
        self.distance = distance
        self.releaseDelay = releaseDelay
        self.session = session
        self.isRecording = isRecording
    }

    var handlesPointerMotion: Bool {
        false
    }

    func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
        guard event.type == .scrollWheel, !event.isLinearMouseSyntheticEvent else {
            return event
        }

        // Let button mapping recording see the wheel. A swipe already in
        // progress still eases to its target and releases on its own, so the
        // space never stays half-switched.
        if isRecording() {
            return event
        }

        let view = ScrollWheelEventView(event)

        // Trackpads already swipe between spaces natively.
        if view.scrollPhase != nil || view.momentumPhase != .none {
            return event
        }

        guard let input = ScrollInput.read(from: view, highResolutionMultiplier: nil),
              input.axis == .horizontal
        else {
            return event
        }

        let steps = Self.steps(of: input, rawDelta: view.ioHidScrollX)
        session.move(by: Self.progressSign * steps / distance, releaseDelay: releaseDelay)
        return nil
    }

    /// Prefer the device's raw value: the system accelerates horizontal lines,
    /// which turns a steady spin into uneven jumps. The selected delta still
    /// decides the direction, since it already reflects reversing.
    static func steps(of input: ScrollInput, rawDelta: Double) -> Double {
        let magnitude: Double
        if rawDelta.isFinite, rawDelta != 0 {
            magnitude = abs(rawDelta)
        } else if input.units == .points {
            magnitude = abs(input.delta) / pointsPerLine
        } else {
            magnitude = abs(input.delta)
        }
        return input.delta > 0 ? magnitude : -magnitude
    }
}
