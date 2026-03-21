// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension CGEvent {
    private static let linearMouseSyntheticEventUserData: Int64 = 0x534D_4F4F_5448

    var isLinearMouseSyntheticEvent: Bool {
        get {
            getIntegerValueField(.eventSourceUserData) == Self.linearMouseSyntheticEventUserData
        }
        set {
            setIntegerValueField(
                .eventSourceUserData,
                value: newValue ? Self.linearMouseSyntheticEventUserData : 0
            )
        }
    }
}
