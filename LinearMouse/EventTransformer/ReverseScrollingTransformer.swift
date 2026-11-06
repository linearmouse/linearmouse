// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

class ReverseScrollingTransformer: EventTransformer {
    var handlesPointerMotion: Bool {
        false
    }

    private let vertically: Bool
    private let horizontally: Bool
    private let mouseReversesVertically: (EventTransformerContext) -> Bool

    /// - Parameter mouseReversesVertically: Whether the device already reverses
    ///   its vertical wheel itself. The vertical reversal is then applied only
    ///   where this scheme does not want it, which undoes the mouse's.
    init(
        vertically: Bool = false,
        horizontally: Bool = false,
        mouseReversesVertically: @escaping (EventTransformerContext) -> Bool = { _ in false }
    ) {
        self.vertically = vertically
        self.horizontally = horizontally
        self.mouseReversesVertically = mouseReversesVertically
    }

    func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? {
        guard event.type == .scrollWheel else {
            return event
        }

        if event.isLinearMouseSyntheticEvent {
            return event
        }

        let vertically = vertically != mouseReversesVertically(context)
        guard vertically || horizontally else {
            return event
        }

        let view = ScrollWheelEventView(event)
        view.negate(vertically: vertically, horizontally: horizontally)
        return event
    }
}

extension ReverseScrollingTransformer {
    /// Reads the confirmed in-mouse reversal of the event's Logitech device.
    static func logitechMouseReversesVertically(in context: EventTransformerContext) -> Bool {
        guard let device = context.device,
              device.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID else {
            return false
        }

        return device.confirmedLogitechWheelInvert == true
    }
}
