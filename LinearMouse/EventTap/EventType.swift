// MIT License
// Copyright (c) 2021-2026 LinearMouse

class EventType {
    static let all: [CGEventType] = [
        .scrollWheel,
        .leftMouseDown,
        .leftMouseUp,
        .leftMouseDragged,
        .rightMouseDown,
        .rightMouseUp,
        .rightMouseDragged,
        .otherMouseDown,
        .otherMouseUp,
        .otherMouseDragged,
        .keyDown,
        .keyUp,
        .flagsChanged
    ]

    static let mouseMoved: CGEventType = .mouseMoved
}

extension CGEventType {
    var isPointerMotion: Bool {
        switch self {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return true
        default:
            return false
        }
    }
}

/// Requirements that cannot wait for a trigger press. Held features acquire
/// motion through their actual interaction state in EventTransformerManager.
/// Union across schemes so entering another app/display can activate its rule.
struct PointerMotionRequirements: OptionSet {
    let rawValue: UInt8
    static let moved = Self(rawValue: 1 << 0)
    static let dragged = Self(rawValue: 1 << 1)
    static let all: Self = [.moved, .dragged]

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    init(configuration: Configuration) {
        self = []
        for scheme in configuration.schemes {
            if scheme.pointer.redirectsToScroll == true,
               scheme.pointer.redirectsToScrollTrigger == nil {
                formUnion(.all)
            }
            if scheme.buttons.switchPrimaryButtonAndSecondaryButtons == true {
                insert(.dragged)
            }
        }
    }

    func contains(eventType: CGEventType) -> Bool {
        switch eventType {
        case .mouseMoved:
            contains(.moved)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            contains(.dragged)
        default:
            false
        }
    }
}
