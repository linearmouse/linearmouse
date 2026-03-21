// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Defaults

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

extension Defaults.Keys {
    static let showInMenuBar = Key<Bool>("showInMenuBar", default: true)
    static let menuBarBatteryDisplayMode = Key<MenuBarBatteryDisplayMode>("menuBarBatteryDisplayMode", default: .off)

    static let showInDock = Key<Bool>("showInDock", default: true)

    static let betaChannelOn = Key("betaChannelOn", default: false)

    static let bypassEventsFromOtherApplications = Key("bypassEventsFromOtherApplications", default: false)

    static let verbosedLoggingOn = Key("verbosedLoggingOn", default: false)
}
