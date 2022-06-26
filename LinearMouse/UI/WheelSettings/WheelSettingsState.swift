// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Combine

class WheelSettingsState: CurrentConfigurationState {}

extension WheelSettingsState {
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
                    distance: LinesOrPixels(value: 3)
                )
            )
            .merge(into: &scheme)
        }
    }

    var linearScrollingLines: Int {
        get {
            scheme.scrolling?.distance?.value ?? 3
        }
        set {
            Scheme(
                scrolling: Scheme.Scrolling(
                    distance: LinesOrPixels(value: newValue)
                )
            )
            .merge(into: &scheme)
        }
    }
}
