// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import Defaults
import Foundation

enum MenuBarBatteryDisplayMode: String, Codable, Defaults.Serializable {
    case off
    case below5
    case below10
    case below15
    case below20
    case always

    var threshold: Int? {
        switch self {
        case .off:
            return nil
        case .below5:
            return 5
        case .below10:
            return 10
        case .below15:
            return 15
        case .below20:
            return 20
        case .always:
            return 100
        }
    }
}

enum MenuBarVisibilityMode: String, Codable, Defaults.Serializable {
    case always
    case whenAttentionNeeded
    case never
}

enum PointerLocationTriggerModifier: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case control
    case option
    case shift
    case command

    var id: Self {
        self
    }

    var flag: CGEventFlags {
        switch self {
        case .control:
            .maskControl
        case .option:
            .maskAlternate
        case .shift:
            .maskShift
        case .command:
            .maskCommand
        }
    }

    var label: String {
        switch self {
        case .control:
            NSLocalizedString("⌃ (Control)", comment: "")
        case .option:
            NSLocalizedString("⌥ (Option)", comment: "")
        case .shift:
            NSLocalizedString("⇧ (Shift)", comment: "")
        case .command:
            NSLocalizedString("⌘ (Command)", comment: "")
        }
    }
}

extension Defaults.Keys {
    static let showInMenuBar = Key<Bool>("showInMenuBar", default: true)
    static let menuBarVisibilityMode = Key<MenuBarVisibilityMode>("menuBarVisibilityMode", default: .always)
    static let menuBarVisibilityModeMigrationCompleted = Key<Bool>(
        "menuBarVisibilityModeMigrationCompleted",
        default: false
    )
    static let menuBarBatteryDisplayMode = Key<MenuBarBatteryDisplayMode>("menuBarBatteryDisplayMode", default: .off)

    static let showInDock = Key<Bool>("showInDock", default: true)

    static let showPointerLocation = Key<Bool>("showPointerLocation", default: false)
    static let pointerLocationTriggerModifier = Key<PointerLocationTriggerModifier>(
        "pointerLocationTriggerModifier",
        default: .control
    )

    static let betaChannelOn = Key("betaChannelOn", default: false)

    static let bypassEventsFromOtherApplications = Key("bypassEventsFromOtherApplications", default: false)

    static let verbosedLoggingOn = Key("verbosedLoggingOn", default: false)
}
