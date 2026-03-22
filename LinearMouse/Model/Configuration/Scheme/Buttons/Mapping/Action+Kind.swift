// MIT License
// Copyright (c) 2021-2026 LinearMouse

extension Scheme.Buttons.Mapping.Action {
    enum Kind: Equatable, Hashable {
        case arg0(Arg0)
        case run
        case mouseWheelScrollUp
        case mouseWheelScrollDown
        case mouseWheelScrollLeft
        case mouseWheelScrollRight
        case keyPress
    }

    var kind: Kind {
        switch self {
        case let .arg0(value):
            return .arg0(value)
        case .arg1(.run):
            return .run
        case .arg1(.mouseWheelScrollUp):
            return .mouseWheelScrollUp
        case .arg1(.mouseWheelScrollDown):
            return .mouseWheelScrollDown
        case .arg1(.mouseWheelScrollLeft):
            return .mouseWheelScrollLeft
        case .arg1(.mouseWheelScrollRight):
            return .mouseWheelScrollRight
        case .arg1(.keyPress):
            return .keyPress
        }
    }

    init(kind: Kind) {
        switch kind {
        case let .arg0(value):
            self = .arg0(value)
        case .run:
            self = .arg1(.run(""))
        case .mouseWheelScrollUp:
            self = .arg1(.mouseWheelScrollUp(.line(3)))
        case .mouseWheelScrollDown:
            self = .arg1(.mouseWheelScrollDown(.line(3)))
        case .mouseWheelScrollLeft:
            self = .arg1(.mouseWheelScrollLeft(.line(3)))
        case .mouseWheelScrollRight:
            self = .arg1(.mouseWheelScrollRight(.line(3)))
        case .keyPress:
            self = .arg1(.keyPress([]))
        }
    }
}
