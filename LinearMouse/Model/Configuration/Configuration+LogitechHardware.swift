// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

extension Configuration {
    /// The settings written into a Logitech device: those of the physical
    /// device, overridden by those of the device behind it that is currently
    /// in use, plus the vertical reverse scrolling that holds in every app and
    /// on every display, which reversing in the mouse refines. The apply path
    /// and the settings UI both read this, so they agree on what the mouse does.
    func logitechHardwareScheme(for device: Device) -> Scheme {
        logitechHardwareScheme(forCandidates: DeviceMatcher.candidates(of: device))
    }

    /// - Parameter candidates: Every identity of the device, most specific
    ///   first. See `DeviceMatcher.candidates(of:)`.
    func logitechHardwareScheme(forCandidates candidates: [DeviceMatcher]) -> Scheme {
        var scheme = Scheme()
        for matcher in candidates.reversed() {
            guard case let .at(index) = schemes.schemeIndex(
                ofDeviceMatcher: matcher,
                ofApp: nil,
                ofProcessPath: nil,
                ofProcessName: nil,
                ofDisplay: nil
            ) else {
                continue
            }

            schemes[index].merge(into: &scheme)
        }

        // App and display schemes cannot reach the mouse; the scroll pipeline
        // corrects for them.
        var everyApp = Scheme.MatchContext()
        everyApp.devices = candidates
        scheme.scrolling.reverse.vertical = matchScheme(in: everyApp).scrolling.reverse.vertical

        return scheme
    }
}
