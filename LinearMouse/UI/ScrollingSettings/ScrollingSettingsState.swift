// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Combine
import Foundation
import SwiftUI

extension ScrollingSettings {
    class State: SchemeStateWrapper {
        static let shared = State()

        enum Orientation {
            case vertical, horizontal
        }

        @Published var orientation: Orientation = .vertical {
            willSet {
                objectWillChange.send()
            }
        }

        private var subscriptions = Set<AnyCancellable>()
    }
}

extension ScrollingSettings.State {
    private func v<T>(_ vertical: T, _ horizontal: T) -> T {
        orientation == .vertical ? vertical : horizontal
    }

    var reverseScrollingBinding: Binding<Bool> {
        v($schemeState.reverseScrollingVertical, $schemeState.reverseScrollingHorizontal)
    }

    var linearScrollingBinding: Binding<Bool> {
        v($schemeState.linearScrollingVertical, $schemeState.linearScrollingHorizontal)
    }

    var linearScrolling: Bool {
        linearScrollingBinding.wrappedValue
    }

    var linearScrollingUnitBinding: Binding<SchemeState.LinearScrollingUnit> {
        v($schemeState.linearScrollingVerticalUnit, $schemeState.linearScrollingHorizontalUnit)
    }

    var linearScrollingUnit: SchemeState.LinearScrollingUnit {
        linearScrollingUnitBinding.wrappedValue
    }

    var linearScrollingLinesBinding: Binding<Int> {
        v($schemeState.linearScrollingVerticalLines, $schemeState.linearScrollingHorizontalLines)
    }

    var linearScrollingLines: Int {
        linearScrollingLinesBinding.wrappedValue
    }

    var linearScrollingPixelsBinding: Binding<Double> {
        v($schemeState.linearScrollingVerticalPixels, $schemeState.linearScrollingHorizontalPixels)
    }

    var linearScrollingPixels: Double {
        linearScrollingPixelsBinding.wrappedValue
    }
}
