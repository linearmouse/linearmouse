// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Combine
import Foundation
import SwiftUI

extension ScrollingSettings {
    class State: ObservableObject {
        static let shared = State()

        enum Orientation {
            case vertical, horizontal
        }

        @Published private var schemeState = SchemeState.shared

        @Published var orientation: Orientation = .vertical

        private var subscriptions = Set<AnyCancellable>()

        init() {
            schemeState.objectWillChange
                .sink { [weak self] in
                    self?.objectWillChange.send()
                }
                .store(in: &subscriptions)
        }
    }
}

extension ScrollingSettings.State {
    var reverseScrolling: Bool {
        get {
            orientation == .vertical ? schemeState.reverseScrollingVertical : schemeState.reverseScrollingHorizontal
        }
        set {
            if orientation == .vertical {
                schemeState.reverseScrollingVertical = newValue
            } else {
                schemeState.reverseScrollingHorizontal = newValue
            }
        }
    }

    var scrollingMode: SchemeState.ScrollingMode {
        get {
            orientation == .vertical ? schemeState.scrollingModeVertical : schemeState.scrollingModeHorizontal
        }
        set {
            if orientation == .vertical {
                schemeState.scrollingModeVertical = newValue
            } else {
                schemeState.scrollingModeHorizontal = newValue
            }
        }
    }

    var scrollingSpeed: Double {
        get {
            orientation == .vertical ? schemeState.scrollingScaleVertical : schemeState.scrollingScaleHorizontal
        }
        set {
            if orientation == .vertical {
                schemeState.scrollingScaleVertical = newValue
            } else {
                schemeState.scrollingScaleHorizontal = newValue
            }
        }
    }

    var linearScrollingUnit: SchemeState.LinearScrollingUnit {
        get {
            orientation == .vertical ? schemeState.linearScrollingVerticalUnit : schemeState
                .linearScrollingHorizontalUnit
        }
        set {
            if orientation == .vertical {
                schemeState.linearScrollingVerticalUnit = newValue
            } else {
                schemeState.linearScrollingHorizontalUnit = newValue
            }
        }
    }

    var linearScrollingLines: Int {
        get {
            orientation == .vertical ? schemeState.linearScrollingVerticalLines : schemeState
                .linearScrollingHorizontalLines
        }
        set {
            if orientation == .vertical {
                schemeState.linearScrollingVerticalLines = newValue
            } else {
                schemeState.linearScrollingHorizontalLines = newValue
            }
        }
    }

    var linearScrollingLinesInDouble: Double {
        get {
            Double(linearScrollingLines)
        }
        set {
            linearScrollingLines = Int(newValue)
        }
    }

    var linearScrollingPixels: Double {
        get {
            orientation == .vertical ? schemeState.linearScrollingVerticalPixels : schemeState
                .linearScrollingHorizontalPixels
        }
        set {
            if orientation == .vertical {
                schemeState.linearScrollingVerticalPixels = newValue
            } else {
                schemeState.linearScrollingHorizontalPixels = newValue
            }
        }
    }
}
