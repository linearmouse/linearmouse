// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Scheme.Scrolling.Distance {
    enum Mode: String, CaseIterable, Identifiable {
        var id: Self {
            self
        }

        case byLines = "By Lines"
        case byPixels = "By Pixels"
    }

    var mode: Mode {
        switch self {
        case .auto, .line:
            return .byLines
        case .pixel:
            return .byPixels
        }
    }
}

extension Scheme.Scrolling.Distance.Mode: CustomStringConvertible {
    var description: String {
        NSLocalizedString(rawValue, comment: "")
    }
}
