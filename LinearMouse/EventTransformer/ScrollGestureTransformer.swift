// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Runs on every route, even when that route has no action mappings. Ownership
/// belongs to the consumed physical gesture, not the current app or modifiers.
final class ScrollGestureTransformer: EventTransformer {
    private let ownership: ScrollGestureOwnership

    init(ownership: ScrollGestureOwnership) {
        self.ownership = ownership
    }

    var handlesPointerMotion: Bool {
        false
    }

    func transform(_ event: CGEvent, in _: EventTransformerContext) -> CGEvent? {
        guard event.type == .scrollWheel, !event.isLinearMouseSyntheticEvent else {
            return event
        }
        if SettingsState.shared.recording {
            ownership.release()
            return event
        }
        let view = ScrollWheelEventView(event)
        if view.momentumPhase != .none {
            let consumed = ownership.consumeMomentum(view)
            if view.momentumPhase == .end {
                ownership.release()
            }
            return consumed ? nil : event
        }
        // A new direct sample chooses its owner in the downstream pipeline.
        // If no mapping consumes it, its future momentum remains native too.
        // Zero-delta end markers must preserve the last sample's ownership.
        if view.scrollPhase == .began || ScrollInput.read(from: view, highResolutionMultiplier: nil) != nil {
            ownership.release()
        }
        return event
    }
}
