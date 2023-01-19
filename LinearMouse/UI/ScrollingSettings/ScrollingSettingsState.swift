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
    private func getValue<T>(_ vertical: T, _ horizontal: T) -> T {
        orientation == .vertical ? vertical : horizontal
    }

    private func setValue<T>(_ vertical: inout T, _ horizontal: inout T, value: T) {
        if orientation == .vertical {
            vertical = value
        } else {
            horizontal = value
        }
    }

    var reverseScrolling: Bool {
        get {
            getValue(schemeState.reverseScrollingVertical, schemeState.reverseScrollingHorizontal)
        }
        set {
            setValue(&schemeState.reverseScrollingVertical, &schemeState.reverseScrollingHorizontal, value: newValue)
        }
    }

    var linearScrolling: Bool {
        get {
            getValue(schemeState.linearScrollingVertical, schemeState.linearScrollingHorizontal)
        }
        set {
            setValue(&schemeState.linearScrollingVertical, &schemeState.linearScrollingHorizontal, value: newValue)
        }
    }

    var linearScrollingUnit: SchemeState.LinearScrollingUnit {
        get {
            getValue(schemeState.linearScrollingVerticalUnit, schemeState.linearScrollingHorizontalUnit)
        }
        set {
            setValue(
                &schemeState.linearScrollingVerticalUnit,
                &schemeState.linearScrollingHorizontalUnit,
                value: newValue
            )
        }
    }

    var linearScrollingLines: Int {
        get {
            getValue(schemeState.linearScrollingVerticalLines, schemeState.linearScrollingHorizontalLines)
        }
        set {
            setValue(
                &schemeState.linearScrollingVerticalLines,
                &schemeState.linearScrollingHorizontalLines,
                value: newValue
            )
        }
    }

    var linearScrollingPixels: Double {
        get {
            getValue(schemeState.linearScrollingVerticalPixels, schemeState.linearScrollingHorizontalPixels)
        }
        set {
            setValue(
                &schemeState.linearScrollingVerticalPixels,
                &schemeState.linearScrollingHorizontalPixels,
                value: newValue
            )
        }
    }
}
