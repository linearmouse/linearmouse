// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Defaults

extension Defaults.Keys {
    static let showInMenuBar = Key<Bool>("showInMenuBar", default: true)

    static let showInDock = Key<Bool>("showInDock", default: true)

    static let betaChannelOn = Key("betaChannelOn", default: false)

    static let bypassEventsFromOtherApplications = Key("bypassEventsFromOtherApplications", default: false)

    static let verbosedLoggingOn = Key("verbosedLoggingOn", default: false)
}
