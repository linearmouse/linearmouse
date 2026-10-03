// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Compare each consumer's raw configuration, preserving conditions, order and
/// explicit overrides. Rules with no settings for that consumer can be omitted.
struct ConfigurationDiff {
    let previous: Configuration?
    let current: Configuration

    var affectsEventTransformers: Bool {
        changes { scheme in
            var result = Scheme(if: scheme.if)
            result.$scrolling = scheme.$scrolling
            result.$buttons = scheme.$buttons
            result.pointer.redirectsToScroll = scheme.pointer.redirectsToScroll
            result.pointer.redirectsToScrollTrigger = scheme.pointer.redirectsToScrollTrigger
            let hasSettings = scheme.scrolling != Scheme.Scrolling()
                || scheme.buttons != Scheme.Buttons()
                || scheme.pointer.redirectsToScroll != nil
                || scheme.pointer.redirectsToScrollTrigger != nil
            return hasSettings ? result : nil
        }
    }

    var affectsFocusFollowsMouse: Bool {
        changes { scheme in
            var result = Scheme(if: scheme.if)
            result.pointer.focusFollowsMouse = scheme.pointer.focusFollowsMouse
            result.pointer.redirectsToScroll = scheme.pointer.redirectsToScroll
            result.pointer.redirectsToScrollTrigger = scheme.pointer.redirectsToScrollTrigger
            let hasSettings = scheme.pointer.focusFollowsMouse != nil
                || scheme.pointer.redirectsToScroll != nil
                || scheme.pointer.redirectsToScrollTrigger != nil
            return hasSettings ? result : nil
        }
    }

    private func changes(project: (Scheme) -> Scheme?) -> Bool {
        guard let previous else {
            return true
        }
        return previous.schemes.compactMap(project) != current.schemes.compactMap(project)
    }
}
