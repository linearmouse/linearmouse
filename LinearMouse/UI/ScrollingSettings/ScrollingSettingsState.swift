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
                scrolling: Scheme.Scrolling(
                    reverse: Scheme.Scrolling.Reverse(
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
                scrolling: Scheme.Scrolling(
                    reverse: Scheme.Scrolling.Reverse(
                        horizontal: newValue
                    )
                )
            )
            .merge(into: &scheme)
        }
    }

    var linearScrollingEnabled: Bool {
        get {
            scheme.scrolling?.distance != nil
        }
        set {
            guard newValue else {
                scheme.scrolling?.distance = nil
                return
            }

            Scheme(
                scrolling: Scheme.Scrolling(
                    distance: .line(3)
                )
            )
            .merge(into: &scheme)
        }
    }

    var linearScrollingDistance: LinesOrPixels {
        get {
            scheme.scrolling?.distance ?? .line(3)
        }
        set {
            Scheme(
                scrolling: Scheme.Scrolling(
                    distance: newValue
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
            case .line: return .line
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
