// MIT License
// Copyright (c) 2021-2026 LinearMouse

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

    @ImplicitOptional var logitech: Logitech

    init(
        if: [If]? = nil,
        scrolling: Scrolling? = nil,
        pointer: Pointer? = nil,
        buttons: Buttons? = nil,
        logitech: Logitech? = nil
    ) {
        self.if = `if`
        $scrolling = scrolling
        $pointer = pointer
        $buttons = buttons
        $logitech = logitech
    }
}

extension Scheme {
    struct MatchContext {
        var device: DeviceMatcher?
        var app: String?
        var parentApp: String?
        var groupApp: String?
        var display: String?
        var processName: String?
        var processPath: String?

        init(
            deviceMatcher: DeviceMatcher? = nil,
            app: String? = nil,
            parentApp: String? = nil,
            groupApp: String? = nil,
            display: String? = nil,
            processName: String? = nil,
            processPath: String? = nil
        ) {
            device = deviceMatcher
            self.app = app
            self.parentApp = parentApp
            self.groupApp = groupApp
            self.display = display
            self.processName = processName
            self.processPath = processPath
        }

        init(
            device: Device?,
            app: String? = nil,
            parentApp: String? = nil,
            groupApp: String? = nil,
            display: String? = nil,
            processName: String? = nil,
            processPath: String? = nil
        ) {
            self.init(
                deviceMatcher: device.map { DeviceMatcher(of: $0) },
                app: app,
                parentApp: parentApp,
                groupApp: groupApp,
                display: display,
                processName: processName,
                processPath: processPath
            )
        }
    }
}

extension Scheme {
    func isActive(in context: MatchContext) -> Bool {
        guard let `if` else {
            return true
        }

        return `if`.contains {
            $0.isSatisfied(in: context)
        }
    }

    func isActive(
        withDevice device: Device? = nil,
        withApp app: String? = nil,
        withParentApp parentApp: String? = nil,
        withGroupApp groupApp: String? = nil,
        withDisplay display: String? = nil,
        withProcessName processName: String? = nil,
        withProcessPath processPath: String? = nil
    ) -> Bool {
        isActive(
            in: MatchContext(
                device: device,
                app: app,
                parentApp: parentApp,
                groupApp: groupApp,
                display: display,
                processName: processName,
                processPath: processPath
            )
        )
    }

    func isActive(
        withDeviceMatcher deviceMatcher: DeviceMatcher? = nil,
        withApp app: String? = nil,
        withParentApp parentApp: String? = nil,
        withGroupApp groupApp: String? = nil,
        withDisplay display: String? = nil,
        withProcessName processName: String? = nil,
        withProcessPath processPath: String? = nil
    ) -> Bool {
        isActive(
            in: MatchContext(
                deviceMatcher: deviceMatcher,
                app: app,
                parentApp: parentApp,
                groupApp: groupApp,
                display: display,
                processName: processName,
                processPath: processPath
            )
        )
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

    var isDeviceCategorySpecific: Bool {
        guard let conditions = `if` else {
            return false
        }

        guard conditions.count == 1,
              let condition = conditions.first else {
            return false
        }

        return condition.device?.categoryOnlyValue != nil
    }

    var isDisplaySpecific: Bool {
        `if`?.contains { $0.display != nil } ?? false
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
        $logitech?.merge(into: &scheme.logitech)
    }
}

extension Scheme: CustomStringConvertible {
    var description: String {
        do {
            return try String(data: JSONEncoder().encode(self), encoding: .utf8) ?? "<Scheme>"
        } catch {
            return "<Scheme>"
        }
    }
}

extension [Scheme] {
    func allDeviceSpecficSchemes(of device: Device) -> [EnumeratedSequence<[Scheme]>.Element] {
        allDeviceMatcherSpecificSchemes(of: DeviceMatcher(of: device))
    }

    func allDeviceMatcherSpecificSchemes(of matcher: DeviceMatcher) -> [EnumeratedSequence<[Scheme]>.Element] {
        self.enumerated().filter { _, scheme in
            guard scheme.isDeviceSpecific else {
                return false
            }
            guard scheme.if?.count == 1, let `if` = scheme.if?.first else {
                return false
            }
            guard `if`.device?.isSatisfied(by: matcher) == true else {
                return false
            }
            return true
        }
    }

    func allDeviceCategorySpecificSchemes(
        of category: DeviceMatcher.Category
    ) -> [EnumeratedSequence<[Scheme]>.Element] {
        self.enumerated().filter { _, scheme in
            guard scheme.isDeviceCategorySpecific else {
                return false
            }
            guard scheme.if?.first?.device?.categoryOnlyValue == category else {
                return false
            }
            return true
        }
    }

    enum SchemeIndex {
        case at(Int)
        case insertAt(Int)
    }

    func schemeIndex(
        ofDevice device: Device,
        ofApp app: String?,
        ofProcessPath processPath: String?,
        ofDisplay display: String?
    ) -> SchemeIndex {
        schemeIndex(
            among: allDeviceSpecficSchemes(of: device),
            emptyInsertionIndex: endIndex,
            ofApp: app,
            ofProcessPath: processPath,
            ofDisplay: display
        )
    }

    func schemeIndex(
        ofDeviceMatcher matcher: DeviceMatcher,
        ofApp app: String?,
        ofProcessPath processPath: String?,
        ofDisplay display: String?
    ) -> SchemeIndex {
        if let category = matcher.categoryOnlyValue {
            return schemeIndex(
                ofDeviceCategory: category,
                ofApp: app,
                ofProcessPath: processPath,
                ofDisplay: display
            )
        }

        return schemeIndex(
            among: allDeviceMatcherSpecificSchemes(of: matcher),
            emptyInsertionIndex: endIndex,
            ofApp: app,
            ofProcessPath: processPath,
            ofDisplay: display
        )
    }

    func schemeIndex(
        ofDeviceCategory category: DeviceMatcher.Category,
        ofApp app: String?,
        ofProcessPath processPath: String?,
        ofDisplay display: String?
    ) -> SchemeIndex {
        schemeIndex(
            among: allDeviceCategorySpecificSchemes(of: category),
            emptyInsertionIndex: firstDeviceSpecificSchemeIndex(of: category) ?? endIndex,
            ofApp: app,
            ofProcessPath: processPath,
            ofDisplay: display
        )
    }

    private func schemeIndex(
        among matchingSchemes: [EnumeratedSequence<[Scheme]>.Element],
        emptyInsertionIndex: Int,
        ofApp app: String?,
        ofProcessPath processPath: String?,
        ofDisplay display: String?
    ) -> SchemeIndex {
        guard let first = matchingSchemes.first,
              let last = matchingSchemes.last else {
            return .insertAt(emptyInsertionIndex)
        }

        if let (index, _) = matchingSchemes
            .first(where: { _, scheme in
                scheme.if?.first?.app == app &&
                    scheme.if?.first?.processPath == processPath &&
                    scheme.if?.first?.display == display
            }) {
            return .at(index)
        }

        if app == nil, processPath == nil, display == nil {
            return .insertAt(first.offset)
        }

        if app != nil || processPath != nil, display != nil {
            return .insertAt(last.offset + 1)
        }

        if app != nil {
            if let (index, _) = matchingSchemes
                .first(where: { _, scheme in scheme.if?.first?.app == app }) {
                return .insertAt(index)
            }
        }

        if processPath != nil {
            if let (index, _) = matchingSchemes
                .first(where: { _, scheme in scheme.if?.first?.processPath == processPath }) {
                return .insertAt(index)
            }
        }

        if display != nil {
            if let (index, _) = matchingSchemes
                .first(where: { _, scheme in scheme.if?.first?.display == display }) {
                return .insertAt(index)
            }
        }

        return .insertAt(last.offset + 1)
    }

    private func firstDeviceSpecificSchemeIndex(of category: DeviceMatcher.Category) -> Int? {
        enumerated()
            .first { _, scheme in
                guard scheme.isDeviceSpecific,
                      let matcher = scheme.if?.first?.device else {
                    return false
                }

                if matcher.category?.contains(category) == true {
                    return true
                }

                return scheme.matchedDevices.contains { $0.category == category.deviceCategory }
            }?
            .offset
    }
}
