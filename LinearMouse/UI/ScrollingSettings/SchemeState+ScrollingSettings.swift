// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Combine
import Foundation

extension SchemeState {
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

    enum ScrollingMode {
        case accelerated, linear
    }

    var scrollingModeVertical: ScrollingMode {
        get {
            if case .auto = scheme.scrolling?.distance?.vertical ?? .auto {
                return .accelerated
            }

            return .linear
        }
        set {
            Scheme(
                scrolling: .init(
                    distance: .init(
                        vertical: newValue == .linear ? .line(3) : .auto
                    ),
                    scale: .init(
                        vertical: 1
                    )
                )
            )
            .merge(into: &scheme)
        }
    }

    var scrollingModeHorizontal: ScrollingMode {
        get {
            if case .auto = scheme.scrolling?.distance?.horizontal ?? .auto {
                return .accelerated
            }

            return .linear
        }
        set {
            Scheme(
                scrolling: .init(
                    distance: .init(
                        horizontal: newValue == .linear ? .line(3) : .auto
                    ),
                    scale: .init(
                        horizontal: 1
                    )
                )
            )
            .merge(into: &scheme)
        }
    }

    var scrollingScaleVertical: Double {
        get {
            scheme.scrolling?.scale?.vertical?.asTruncatedDouble ?? 1
        }

        set {
            Scheme(
                scrolling: .init(
                    scale: .init(
                        vertical: Decimal(newValue).rounded(2)
                    )
                )
            )
            .merge(into: &scheme)
        }
    }

    var scrollingScaleHorizontal: Double {
        get {
            scheme.scrolling?.scale?.horizontal?.asTruncatedDouble ?? 1
        }

        set {
            Scheme(
                scrolling: .init(
                    scale: .init(
                        horizontal: Decimal(newValue).rounded(2)
                    )
                )
            )
            .merge(into: &scheme)
        }
    }

    var linearScrollingVerticalDistance: Scheme.Scrolling.Distance {
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

    var linearScrollingHorizontalDistance: Scheme.Scrolling.Distance {
        get {
            scheme.scrolling?.distance?.horizontal ?? .line(3)
        }
        set {
            Scheme(
                scrolling: .init(
                    distance: .init(
                        horizontal: newValue
                    )
                )
            )
            .merge(into: &scheme)
        }
    }

    enum LinearScrollingUnit {
        case line, pixel
    }

    var linearScrollingVerticalUnit: LinearScrollingUnit {
        get {
            switch linearScrollingVerticalDistance {
            case .auto, .line: return .line
            case .pixel: return .pixel
            }
        }

        set {
            switch newValue {
            case .line:
                linearScrollingVerticalDistance = .line(3)
            case .pixel:
                linearScrollingVerticalDistance = .pixel(36)
            }
        }
    }

    var linearScrollingVerticalLines: Int {
        get {
            guard case let .line(value) = linearScrollingVerticalDistance else {
                return 3
            }

            return value
        }

        set {
            linearScrollingVerticalDistance = .line(newValue)
        }
    }

    var linearScrollingHorizontalUnit: LinearScrollingUnit {
        get {
            switch linearScrollingHorizontalDistance {
            case .auto, .line: return .line
            case .pixel: return .pixel
            }
        }

        set {
            switch newValue {
            case .line:
                linearScrollingHorizontalDistance = .line(3)
            case .pixel:
                linearScrollingHorizontalDistance = .pixel(36)
            }
        }
    }

    var linearScrollingHorizontalLines: Int {
        get {
            guard case let .line(value) = linearScrollingHorizontalDistance else {
                return 3
            }

            return value
        }

        set {
            linearScrollingHorizontalDistance = .line(newValue)
        }
    }

    var linearScrollingVerticalPixels: Double {
        get {
            guard case let .pixel(value) = linearScrollingVerticalDistance else {
                return 36
            }

            return value.asTruncatedDouble
        }

        set {
            linearScrollingVerticalDistance = .pixel(Decimal(newValue).rounded(1))
        }
    }

    var linearScrollingHorizontalPixels: Double {
        get {
            guard case let .pixel(value) = linearScrollingHorizontalDistance else {
                return 36
            }

            return value.asTruncatedDouble
        }

        set {
            linearScrollingHorizontalDistance = .pixel(Decimal(newValue).rounded(1))
        }
    }
}
