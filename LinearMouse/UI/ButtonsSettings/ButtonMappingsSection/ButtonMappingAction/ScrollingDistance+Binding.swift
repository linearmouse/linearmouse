// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import SwiftUI

extension Binding where Value == Scheme.Scrolling.Distance {
    var mode: Binding<Scheme.Scrolling.Distance.Mode> {
        Binding<Scheme.Scrolling.Distance.Mode>(
            get: {
                wrappedValue.mode
            },
            set: {
                switch $0 {
                case .byLines:
                    wrappedValue = .line(3)
                case .byPixels:
                    wrappedValue = .pixel(36)
                }
            }
        )
    }

    var lineCount: Binding<Double> {
        Binding<Double>(
            get: {
                guard case let .line(value) = wrappedValue else {
                    return 3
                }

                return Double(value)
            },
            set: {
                wrappedValue = .line(Int($0))
            }
        )
    }

    var pixelCount: Binding<Double> {
        Binding<Double>(
            get: {
                guard case let .pixel(value) = wrappedValue else {
                    return 36
                }

                return value.asTruncatedDouble
            },
            set: {
                wrappedValue = .pixel(Decimal($0).rounded(1))
            }
        )
    }
}

extension Scheme.Scrolling.Distance.Mode {
    @ViewBuilder
    var label: some View {
        switch self {
        case .byLines:
            Text("By Lines")
        case .byPixels:
            Text("By Pixels")
        }
    }
}
