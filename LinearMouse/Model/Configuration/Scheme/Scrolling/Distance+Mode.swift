// MIT License
// Copyright (c) 2021-2026 LinearMouse

extension Scheme.Scrolling.Distance {
    enum Mode: CaseIterable, Identifiable {
        var id: Self {
            self
        }

        case byLines
        case byPixels
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
