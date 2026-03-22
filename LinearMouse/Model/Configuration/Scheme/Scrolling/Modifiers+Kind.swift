// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Scheme.Scrolling.Modifiers.Action {
    enum Kind: String, CaseIterable, Identifiable {
        var id: Self {
            self
        }

        case defaultAction = "Default action"
        case ignore = "Ignore modifier"
        case noAction = "No action"
        case alterOrientation = "Alter orientation"
        case changeSpeed = "Change speed"
        case zoom = "Zoom"
        case pinchZoom = "Pinch zoom"
    }

    var kind: Kind {
        switch self {
        case .auto:
            return .defaultAction
        case .ignore:
            return .ignore
        case .preventDefault:
            return .noAction
        case .alterOrientation:
            return .alterOrientation
        case .changeSpeed:
            return .changeSpeed
        case .zoom:
            return .zoom
        case .pinchZoom:
            return .pinchZoom
        }
    }

    init(kind: Kind) {
        switch kind {
        case .defaultAction:
            self = .auto
        case .ignore:
            self = .ignore
        case .noAction:
            self = .preventDefault
        case .alterOrientation:
            self = .alterOrientation
        case .changeSpeed:
            self = .changeSpeed(scale: 1)
        case .zoom:
            self = .zoom
        case .pinchZoom:
            self = .pinchZoom
        }
    }
}

extension Scheme.Scrolling.Modifiers.Action.Kind: CustomStringConvertible {
    var description: String {
        NSLocalizedString(rawValue, comment: "").capitalized
    }
}
