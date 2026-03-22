// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import SwiftUI

extension Binding where Value == Scheme.Scrolling.Modifiers.Action? {
    var kind: Binding<Scheme.Scrolling.Modifiers.Action.Kind> {
        Binding<Scheme.Scrolling.Modifiers.Action.Kind>(
            get: {
                wrappedValue?.kind ?? .defaultAction
            },
            set: {
                wrappedValue = Scheme.Scrolling.Modifiers.Action(kind: $0)
            }
        )
    }

    var speedFactor: Binding<Double> {
        Binding<Double>(
            get: {
                guard case let .changeSpeed(speedFactor) = wrappedValue else {
                    return 1
                }

                return speedFactor.asTruncatedDouble
            },
            set: { value in
                if value < 0 {
                    wrappedValue = .changeSpeed(scale: Decimal(value).rounded(0))
                } else if 0 ..< 0.1 ~= value {
                    wrappedValue = .changeSpeed(scale: Decimal(value * 20).rounded(0) / 20)
                } else if 0.1 ..< 1 ~= value {
                    wrappedValue = .changeSpeed(scale: Decimal(value).rounded(1))
                } else {
                    wrappedValue = .changeSpeed(scale: Decimal(value * 2).rounded(0) / 2)
                }
            }
        )
    }
}

extension Scheme.Scrolling.Modifiers.Action.Kind {
    @ViewBuilder
    var label: some View {
        switch self {
        case .defaultAction:
            Text("Default action")
        case .ignore:
            Text("Ignore modifier")
        case .noAction:
            Text("No action")
        case .alterOrientation:
            Text("Alter orientation")
        case .changeSpeed:
            Text("Change speed")
        case .zoom:
            Text("Zoom")
        case .pinchZoom:
            Text("Pinch zoom")
        }
    }
}
