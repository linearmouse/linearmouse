// MIT License
// Copyright (c) 2021-2023 LinearMouse

import Combine
import Foundation
import PublishedObject

class ScrollingSettingsState: ObservableObject {
    static let shared: ScrollingSettingsState = .init()

    @PublishedObject private var schemeState = SchemeState.shared
    var scheme: Scheme {
        get { schemeState.scheme }
        set { schemeState.scheme = newValue }
    }

    var mergedScheme: Scheme { schemeState.mergedScheme }

    @Published var direction: Scheme.Scrolling.BidirectionalDirection = .vertical
}

extension ScrollingSettingsState {
    var reverseScrolling: Bool {
        get { mergedScheme.scrolling.reverse[direction] ?? false }
        set { scheme.scrolling.reverse[direction] = newValue }
    }

    enum ScrollingMode: String, Identifiable, CaseIterable {
        var id: Self { self }

        case accelerated = "Accelerated"
        case byLines = "By Lines"
        case byPixels = "By Pixels"
    }

    var scrollingMode: ScrollingMode {
        get {
            switch mergedScheme.scrolling.distance[direction] ?? .auto {
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

            scheme.scrolling.distance[direction] = distance
            scheme.scrolling.acceleration[direction] = 1
            scheme.scrolling.speed[direction] = 0
        }
    }

    var scrollingAcceleration: Double {
        get { mergedScheme.scrolling.acceleration[direction]?.asTruncatedDouble ?? 1 }
        set { scheme.scrolling.acceleration[direction] = Decimal(newValue).rounded(2) }
    }

    var scrollingAccelerationFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = NumberFormatter.Style.decimal
        formatter.roundingMode = NumberFormatter.RoundingMode.halfUp
        formatter.maximumFractionDigits = 2
        formatter.thousandSeparator = ""
        return formatter
    }

    var scrollingSpeed: Double {
        get { mergedScheme.scrolling.speed[direction]?.asTruncatedDouble ?? 0 }
        set { scheme.scrolling.speed[direction] = Decimal(newValue).rounded(2) }
    }

    var scrollingSpeedFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = NumberFormatter.Style.decimal
        formatter.roundingMode = NumberFormatter.RoundingMode.halfUp
        formatter.maximumFractionDigits = 2
        formatter.thousandSeparator = ""
        return formatter
    }

    var scrollingDistanceInLines: Double {
        get {
            guard case let .line(lines) = mergedScheme.scrolling.distance[direction] else {
                return 3
            }
            return Double(lines)
        }
        set {
            scheme.scrolling.distance[direction] = .line(Int(newValue))
        }
    }

    var scrollingDistanceInPixels: Double {
        get {
            guard case let .pixel(pixels) = mergedScheme.scrolling.distance[direction] else {
                return 36
            }
            return pixels.asTruncatedDouble
        }
        set {
            scheme.scrolling.distance[direction] = .pixel(Decimal(newValue).rounded(1))
        }
    }

    var scrollingDisabled: Bool {
        switch scrollingMode {
        case .accelerated:
            return scrollingAcceleration == 0 && scrollingSpeed == 0
        case .byLines:
            return scrollingDistanceInLines == 0
        case .byPixels:
            return scrollingDistanceInPixels == 0
        }
    }

    var modifiers: Scheme.Scrolling.Modifiers {
        get {
            mergedScheme.scrolling.modifiers[direction] ?? .init()
        }
        set {
            scheme.scrolling.modifiers[direction] = newValue
        }
    }
}
