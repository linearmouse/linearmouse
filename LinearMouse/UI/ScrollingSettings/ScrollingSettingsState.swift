// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

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

    @Published var direction: Scheme.Scrolling.BidirectionalDirection = .vertical
}

extension ScrollingSettingsState {
    var reverseScrolling: Bool {
        get { scheme.scrolling.reverse[direction] ?? false }
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
            switch scheme.scrolling.distance[direction] ?? .auto {
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
            scheme.scrolling.scale[direction] = nil
        }
    }

    var scrollingScale: Double {
        get { scheme.scrolling.scale[direction]?.asTruncatedDouble ?? 1 }
        set { scheme.scrolling.scale[direction] = Decimal(newValue).rounded(2) }
    }

    var scrollingDistanceInLines: Double {
        get {
            guard case let .line(lines) = scheme.scrolling.distance[direction] else {
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
            guard case let .pixel(pixels) = scheme.scrolling.distance[direction] else {
                return 36
            }
            return pixels.asTruncatedDouble
        }
        set {
            scheme.scrolling.distance[direction] = .pixel(Decimal(newValue).rounded(1))
        }
    }
}
