// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation

extension SchemeState {
    var commandAction: Scheme.Scrolling.Modifiers.Action? {
        get {
            scheme.scrolling?.modifiers?.command
        }

        set {
            Scheme(
                scrolling: Scheme.Scrolling(
                    modifiers: Scheme.Scrolling.Modifiers(
                        command: newValue
                    )
                )
            )
            .merge(into: &scheme)

            if newValue == nil {
                scheme.scrolling?.modifiers?.command = nil
            }
        }
    }

    var shiftAction: Scheme.Scrolling.Modifiers.Action? {
        get {
            scheme.scrolling?.modifiers?.shift
        }

        set {
            Scheme(
                scrolling: Scheme.Scrolling(
                    modifiers: Scheme.Scrolling.Modifiers(
                        shift: newValue
                    )
                )
            )
            .merge(into: &scheme)

            if newValue == nil {
                scheme.scrolling?.modifiers?.shift = nil
            }
        }
    }

    var optionAction: Scheme.Scrolling.Modifiers.Action? {
        get {
            scheme.scrolling?.modifiers?.option
        }

        set {
            Scheme(
                scrolling: Scheme.Scrolling(
                    modifiers: Scheme.Scrolling.Modifiers(
                        option: newValue
                    )
                )
            )
            .merge(into: &scheme)

            if newValue == nil {
                scheme.scrolling?.modifiers?.option = nil
            }
        }
    }

    var controlAction: Scheme.Scrolling.Modifiers.Action? {
        get {
            scheme.scrolling?.modifiers?.control
        }

        set {
            Scheme(
                scrolling: Scheme.Scrolling(
                    modifiers: Scheme.Scrolling.Modifiers(
                        control: newValue
                    )
                )
            )
            .merge(into: &scheme)

            if newValue == nil {
                scheme.scrolling?.modifiers?.control = nil
            }
        }
    }
}
