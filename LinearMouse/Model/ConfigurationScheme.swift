// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

/// A scheme is a set of settings to be applied to LinearMouse, for example,
/// pointer sensitivity.
///
/// A scheme will be active only if its `if` is truthy. If multiple `if`s are
/// provided, the scheme is regarded as active if any one of them is truthy.
///
/// There can be multiple active schemes at the same time. Settings in
/// subsequent schemes will be merged into the previous ones.
struct ConfigurationScheme: Codable {
    /// Defines the conditions under which this scheme is active.
    var `if`: ArrayOrSingleValue<ConfigurationSchemeIf>?

    var scrolling: ConfigurationScrollingSettings?
}

struct ConfigurationSchemeIf: Codable {
    var device: DeviceMatcher?
}

extension ConfigurationScheme {
    var isActive: Bool {
        guard let `if` = `if` else {
            return true
        }

        return `if`.value.contains(where: \.isTruthy)
    }

    func merge(into scheme: inout Self) {
        if let scrolling = scrolling {
            scrolling.merge(into: &scheme.scrolling)
        }
    }
}

extension ConfigurationSchemeIf {
    var isTruthy: Bool {
        if let device = device {
            guard let activeDevice = DeviceManager.shared.lastActiveDevice else {
                return false
            }
            guard device.match(with: activeDevice) else { return false }
        }

        return true
    }
}
