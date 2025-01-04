// MIT License
// Copyright (c) 2021-2025 LinearMouse

import AppKit
import Combine
import Foundation

class DisplayPickerState: ObservableObject {
    static let shared: DisplayPickerState = .init()

    private let screenManager: ScreenManager = .shared

    private let schemeState: SchemeState = .shared
    private let deviceState: DeviceState = .shared

    var allDisplays: [String] {
        screenManager.screens.map(\.nameOrLocalizedName)
    }
}
