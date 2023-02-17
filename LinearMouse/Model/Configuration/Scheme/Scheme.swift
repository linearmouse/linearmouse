// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation

/// A scheme is a set of settings to be applied to LinearMouse, for example,
/// pointer speed.
///
/// A scheme will be active only if its `if` is truthy. If multiple `if`s are
/// provided, the scheme is regarded as active if any one of them is truthy.
///
/// There can be multiple active schemes at the same time. Settings in
/// subsequent schemes will be merged into the previous ones.
struct Scheme: Codable, Equatable {
    /// Defines the conditions under which this scheme is active.
    @SingleValueOrArray var `if`: [If]?

    @ImplicitOptional var scrolling: Scrolling

    @ImplicitOptional var pointer: Pointer

    @ImplicitOptional var buttons: Buttons

    init(if: [If]? = nil,
         scrolling: Scrolling? = nil,
         pointer: Pointer? = nil,
         buttons: Buttons? = nil) {
        self.if = `if`
        $scrolling = scrolling
        $pointer = pointer
        $buttons = buttons
    }
}

extension Scheme {
    func isActive(withDevice device: Device? = nil,
                  withApp app: String? = nil,
                  withParentApp parentApp: String? = nil,
                  withGroupApp groupApp: String? = nil) -> Bool {
        guard let `if` = `if` else {
            return true
        }

        return `if`.contains {
            $0.isSatisfied(withDevice: device,
                           withApp: app,
                           withParentApp: parentApp,
                           withGroupApp: groupApp)
        }
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

    var matchedDevices: [Device] {
        DeviceManager.shared.devices.filter { isActive(withDevice: $0) }
    }

    var firstMatchedDevice: Device? {
        DeviceManager.shared.devices.first { isActive(withDevice: $0) }
    }

    func merge(into scheme: inout Self) {
        $scrolling?.merge(into: &scheme.scrolling)
        $pointer?.merge(into: &scheme.pointer)
        $buttons?.merge(into: &scheme.buttons)
    }
}

extension Scheme: CustomStringConvertible {
    var description: String {
        do {
            return String(data: try JSONEncoder().encode(self), encoding: .utf8) ?? "<Scheme>"
        } catch {
            return "<Scheme>"
        }
    }
}
