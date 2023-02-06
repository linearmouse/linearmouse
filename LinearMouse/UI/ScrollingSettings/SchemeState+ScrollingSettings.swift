// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Combine
import Foundation

extension SchemeState {
    var reverseScrollingVertical: Bool {
        get {
            scheme.scrolling.reverse.vertical ?? false
        }
        set {
            scheme.scrolling.reverse.vertical = newValue
        }
    }

    var reverseScrollingHorizontal: Bool {
        get {
            scheme.scrolling.reverse.horizontal ?? false
        }
        set {
            scheme.scrolling.reverse.horizontal = newValue
        }
    }

    enum ScrollingMode {
        case accelerated, byLines, byPixels
    }

    var scrollingModeVertical: ScrollingMode {
        get {
            switch scheme.scrolling.distance.vertical ?? .auto {
            case .auto:
                return .accelerated
            case .line:
                return .byLines
            case .pixel:
                return .byPixels
            }
        }
        set {
            var distance: Scheme.Scrolling.Distance

            switch newValue {
            case .accelerated:
                distance = .auto
            case .byLines:
                distance = .line(3)
            case .byPixels:
                distance = .pixel(36)
            }

            Scheme(
                scrolling: .init(
                    distance: .init(
                        vertical: distance
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
            switch scheme.scrolling.distance.horizontal ?? .auto {
            case .auto:
                return .accelerated
            case .line:
                return .byLines
            case .pixel:
                return .byPixels
            }
        }
        set {
            var distance: Scheme.Scrolling.Distance

            switch newValue {
            case .accelerated:
                distance = .auto
            case .byLines:
                distance = .line(3)
            case .byPixels:
                distance = .pixel(36)
            }

            Scheme(
                scrolling: .init(
                    distance: .init(
                        horizontal: distance
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
            scheme.scrolling.scale.vertical?.asTruncatedDouble ?? 1
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
            scheme.scrolling.scale.horizontal?.asTruncatedDouble ?? 1
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
            scheme.scrolling.distance.vertical ?? .line(3)
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
            scheme.scrolling.distance.horizontal ?? .line(3)
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
