// MIT License
// Copyright (c) 2021-2023 LinearMouse

import Foundation

extension Scheme.Buttons.Mapping.Action: CustomStringConvertible {
    var description: String {
        switch self {
        case let .arg0(value):
            return value.description
        case let .arg1(value):
            return value.description
        }
    }
}

extension Scheme.Buttons.Mapping.Action.Arg0: CustomStringConvertible {
    var description: String {
        switch self {
        case .auto:
            return NSLocalizedString("Default action", comment: "")
        case .none:
            return NSLocalizedString("No action", comment: "")
        case .missionControl:
            return NSLocalizedString("Mission Control", comment: "")
        case .missionControlSpaceLeft:
            return NSLocalizedString("Move left a space", comment: "")
        case .missionControlSpaceRight:
            return NSLocalizedString("Move right a space", comment: "")
        case .appExpose:
            return NSLocalizedString("Application windows", comment: "")
        case .launchpad:
            return NSLocalizedString("Launchpad", comment: "")
        case .showDesktop:
            return NSLocalizedString("Show desktop", comment: "")
        case .lookUpAndDataDetectors:
            return NSLocalizedString("Look up & data detectors", comment: "")
        case .smartZoom:
            return NSLocalizedString("Smart zoom", comment: "")
        case .displayBrightnessUp:
            return NSLocalizedString("Increase display brightness", comment: "")
        case .displayBrightnessDown:
            return NSLocalizedString("Decrease display brightness", comment: "")
        case .mediaVolumeUp:
            return NSLocalizedString("Increase volume", comment: "")
        case .mediaVolumeDown:
            return NSLocalizedString("Decrease volume", comment: "")
        case .mediaMute:
            return NSLocalizedString("Mute / unmute", comment: "")
        case .mediaPlayPause:
            return NSLocalizedString("Play / pause", comment: "")
        case .mediaNext:
            return NSLocalizedString("Next", comment: "")
        case .mediaPrevious:
            return NSLocalizedString("Previous", comment: "")
        case .mediaFastForward:
            return NSLocalizedString("Fast forward", comment: "")
        case .mediaRewind:
            return NSLocalizedString("Rewind", comment: "")
        case .keyboardBrightnessUp:
            return NSLocalizedString("Increase keyboard brightness", comment: "")
        case .keyboardBrightnessDown:
            return NSLocalizedString("Decrease keyboard brightness", comment: "")
        case .mouseWheelScrollUp:
            return NSLocalizedString("Scroll up", comment: "")
        case .mouseWheelScrollDown:
            return NSLocalizedString("Scroll down", comment: "")
        case .mouseWheelScrollLeft:
            return NSLocalizedString("Scroll left", comment: "")
        case .mouseWheelScrollRight:
            return NSLocalizedString("Scroll right", comment: "")
        case .mouseButtonLeft:
            return NSLocalizedString("Left click", comment: "")
        case .mouseButtonMiddle:
            return NSLocalizedString("Middle click", comment: "")
        case .mouseButtonRight:
            return NSLocalizedString("Right click", comment: "")
        case .mouseButtonBack:
            return NSLocalizedString("Back", comment: "")
        case .mouseButtonForward:
            return NSLocalizedString("Forward", comment: "")
        }
    }
}

extension Scheme.Buttons.Mapping.Action.Arg1: CustomStringConvertible {
    var description: String {
        switch self {
        case let .run(command):
            return String(format: NSLocalizedString("Run: %@", comment: ""), command)
        case let .mouseWheelScrollUp(distance):
            return String(format: NSLocalizedString("Scroll up %@", comment: ""), String(describing: distance))
        case let .mouseWheelScrollDown(distance):
            return String(format: NSLocalizedString("Scroll down %@", comment: ""), String(describing: distance))
        case let .mouseWheelScrollLeft(distance):
            return String(format: NSLocalizedString("Scroll left %@", comment: ""), String(describing: distance))
        case let .mouseWheelScrollRight(distance):
            return String(format: NSLocalizedString("Scroll right %@", comment: ""), String(describing: distance))
        case let .keyPress(keys):
            return String(format: NSLocalizedString("Key press: %@", comment: ""), keys.map(\.rawValue).joined())
        }
    }
}
