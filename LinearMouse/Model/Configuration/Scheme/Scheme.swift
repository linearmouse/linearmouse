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
struct Scheme: Codable {
    /// Defines the conditions under which this scheme is active.
    @SingleValueOrArray var `if`: [If]?

    var scrolling: Scrolling?
}

extension Scheme {
    var isActive: Bool {
        guard let `if` = `if` else {
            return true
        }

        return `if`.contains(where: \.isTruthy)
    }

    /// A scheme is device-specific if and only if a) it has only one `if` and
    /// b) the `if` contains conditions that specifies both vendorID and productID.
    var isDeviceSpecific: Bool {
        guard let conditions = `if` else {
            return false
        }

        guard conditions.count == 1,
              let condition = conditions.first else {
            return false
        }

        guard condition.device?.vendorID != nil,
              condition.device?.productID != nil else {
            return false
        }

        return true
    }

    func merge(into scheme: inout Self) {
        if let scrolling = scrolling {
            scrolling.merge(into: &scheme.scrolling)
        }
    }
}
