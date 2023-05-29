// MIT License
// Copyright (c) 2021-2023 LinearMouse

import Foundation

extension Scheme.Buttons.Mapping {
    enum Action: Equatable, Hashable {
        case simpleAction(SimpleAction)

        case run(String)

        case mouseWheelScrollUp(Scheme.Scrolling.Distance)
        case mouseWheelScrollDown(Scheme.Scrolling.Distance)
        case mouseWheelScrollLeft(Scheme.Scrolling.Distance)
        case mouseWheelScrollRight(Scheme.Scrolling.Distance)
    }
}
