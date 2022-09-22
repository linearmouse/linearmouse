// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Combine
import Foundation

class ScrollingSettingsState: SchemeState {}

extension ScrollingSettingsState {
    var reverseScrollingVertical: Bool {
        get {
            scheme.scrolling?.reverse?.vertical ?? false
        }
        set {
            Scheme(
                scrolling: .init(
                    reverse: .init(
                        vertical: newValue
                    )
                )
            )
            .merge(into: &scheme)
        }
    }

    var reverseScrollingHorizontal: Bool {
        get {
            scheme.scrolling?.reverse?.horizontal ?? false
        }
        set {
            Scheme(
                scrolling: .init(
                    reverse: .init(
                        horizontal: newValue
                    )
                )
            )
            .merge(into: &scheme)
        }
    }

    var linearScrollingEnabled: Bool {
        get {
            if case .auto = scheme.scrolling?.distance?.vertical ?? .auto {
                return false
            }

            return true
        }
        set {
            Scheme(
                scrolling: .init(
                    distance: .init(
                        vertical: newValue ? .line(3) : .auto
                    )
                )
            )
            .merge(into: &scheme)
        }
    }

    var linearScrollingDistance: Scheme.Scrolling.Distance {
        get {
            scheme.scrolling?.distance?.vertical ?? .line(3)
        }
        set {
            Scheme(
                scrolling: .init(
                    distance: .init(
                        vertical: newValue
                    )
                )
            )
            .merge(into: &scheme)
        }
    }

    enum LinearScrollingUnit: String, CaseIterable, Identifiable {
        var id: Self { self }

        case line = "By lines"
        case pixel = "By pixels"
    }

    var linearScrollingUnit: LinearScrollingUnit {
        get {
            switch linearScrollingDistance {
            case .auto, .line: return .line
            case .pixel: return .pixel
            }
        }

        set {
            switch newValue {
            case .line:
                linearScrollingDistance = .line(3)
            case .pixel:
                linearScrollingDistance = .pixel(36)
            }
        }
    }

    var linearScrollingLines: Int {
        get {
            guard case let .line(value) = linearScrollingDistance else {
                return 3
            }

            return value
        }

        set {
            linearScrollingDistance = .line(newValue)
        }
    }

    var linearScrollingPixels: Double {
        get {
            guard case let .pixel(value) = linearScrollingDistance else {
                return 36
            }

            return value.asTruncatedDouble
        }

        set {
            linearScrollingDistance = .pixel(Decimal(newValue).rounded(1))
        }
    }
}
