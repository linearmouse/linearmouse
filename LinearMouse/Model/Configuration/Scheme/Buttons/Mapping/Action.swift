// MIT License
// Copyright (c) 2021-2023 LinearMouse

import Foundation

extension Scheme.Buttons.Mapping {
    enum Action: Equatable, Hashable {
        case arg0(Arg0)
        case arg1(Arg1)
    }
}

extension Scheme.Buttons.Mapping.Action {
    enum Arg0: String, Codable, Identifiable, CaseIterable {
        var id: Self { self }

        case auto
        case none

        case missionControl
        case missionControlSpaceLeft = "missionControl.spaceLeft"
        case missionControlSpaceRight = "missionControl.spaceRight"

        case appExpose
        case launchpad
        case showDesktop
        case lookUpAndDataDetectors
        case smartZoom

        case displayBrightnessUp = "display.brightnessUp"
        case displayBrightnessDown = "display.brightnessDown"

        case mediaVolumeUp = "media.volumeUp"
        case mediaVolumeDown = "media.volumeDown"
        case mediaMute = "media.mute"
        case mediaPlayPause = "media.playPause"
        case mediaNext = "media.next"
        case mediaPrevious = "media.previous"
        case mediaFastForward = "media.fastForward"
        case mediaRewind = "media.rewind"

        case keyboardBrightnessUp = "keyboard.brightnessUp"
        case keyboardBrightnessDown = "keyboard.brightnessDown"

        case mouseWheelScrollUp = "mouse.wheel.scrollUp"
        case mouseWheelScrollDown = "mouse.wheel.scrollDown"
        case mouseWheelScrollLeft = "mouse.wheel.scrollLeft"
        case mouseWheelScrollRight = "mouse.wheel.scrollRight"

        case mouseButtonLeft = "mouse.button.left"
        case mouseButtonMiddle = "mouse.button.middle"
        case mouseButtonRight = "mouse.button.right"
        case mouseButtonBack = "mouse.button.back"
        case mouseButtonForward = "mouse.button.forward"
    }

    enum Arg1: Equatable, Hashable {
        case run(String)

        case mouseWheelScrollUp(Scheme.Scrolling.Distance)
        case mouseWheelScrollDown(Scheme.Scrolling.Distance)
        case mouseWheelScrollLeft(Scheme.Scrolling.Distance)
        case mouseWheelScrollRight(Scheme.Scrolling.Distance)
    }
}
