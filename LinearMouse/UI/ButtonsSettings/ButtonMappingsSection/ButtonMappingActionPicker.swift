// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ButtonMappingActionPicker: View {
    @Binding var action: Scheme.Buttons.Mapping.Action

    static let actionTypeTree: [ActionTypeTreeNode] = [
        .actionType(.simpleAction(.auto)),
        .actionType(.simpleAction(.none)),
        .section("Mission Control") { [
            .actionType(.simpleAction(.missionControl)),
            .actionType(.simpleAction(.missionControlSpaceLeft)),
            .actionType(.simpleAction(.missionControlSpaceRight))
        ] },
        .actionType(.simpleAction(.appExpose)),
        .actionType(.simpleAction(.launchpad)),
        .actionType(.simpleAction(.showDesktop)),
        .actionType(.simpleAction(.lookUpAndDataDetectors)),
        .actionType(.simpleAction(.smartZoom)),
        .section("Display") { [
            .actionType(.simpleAction(.displayBrightnessUp)),
            .actionType(.simpleAction(.displayBrightnessDown))
        ] },
        .section("Media") { [
            .actionType(.simpleAction(.mediaVolumeUp)),
            .actionType(.simpleAction(.mediaVolumeDown)),
            .actionType(.simpleAction(.mediaMute)),
            .actionType(.simpleAction(.mediaPlayPause)),
            .actionType(.simpleAction(.mediaPrevious)),
            .actionType(.simpleAction(.mediaNext)),
            .actionType(.simpleAction(.mediaFastForward)),
            .actionType(.simpleAction(.mediaRewind))
        ] },
        .section("Keyboard") { [
            .actionType(.simpleAction(.keyboardBrightnessUp)),
            .actionType(.simpleAction(.keyboardBrightnessDown))
        ] },
        .section("Mouse Wheel") { [
            .actionType(.simpleAction(.mouseWheelScrollUp)),
            .actionType(.simpleAction(.mouseWheelScrollDown)),
            .actionType(.simpleAction(.mouseWheelScrollLeft)),
            .actionType(.simpleAction(.mouseWheelScrollRight))
        ] },
        .section("Mouse Button") { [
            .actionType(.simpleAction(.mouseButtonLeft)),
            .actionType(.simpleAction(.mouseButtonMiddle)),
            .actionType(.simpleAction(.mouseButtonRight)),
            .actionType(.simpleAction(.mouseButtonBack)),
            .actionType(.simpleAction(.mouseButtonForward))
        ] }
    ]

    var body: some View {
        Picker("Action", selection: actionType) {
            ActionTypeTreeView(nodes: Self.actionTypeTree)
        }
    }
}

extension ButtonMappingActionPicker {
    indirect enum ActionTypeTreeNode: Identifiable {
        var id: UUID { UUID() }

        case actionType(ActionType)
        case section(LocalizedStringKey, () -> [ActionTypeTreeNode])
    }

    struct ActionTypeTreeView: View {
        let nodes: [ActionTypeTreeNode]

        var body: some View {
            ForEach(nodes) { node in
                switch node {
                case let .actionType(actionType):
                    Text(actionType.description.capitalized).tag(actionType)
                case let .section(header, getNodes):
                    Section(header: Text(header)) {
                        ActionTypeTreeView(nodes: getNodes())
                    }
                }
            }
        }
    }

    var actionType: Binding<ActionType> {
        Binding {
            switch action {
            case let .simpleAction(simpleAction):
                return .simpleAction(simpleAction)
            case .run:
                return .run
            case .mouseWheelScrollUp:
                return .mouseWheelScrollUp
            case .mouseWheelScrollDown:
                return .mouseWheelScrollDown
            case .mouseWheelScrollLeft:
                return .mouseWheelScrollLeft
            case .mouseWheelScrollRight:
                return .mouseWheelScrollRight
            }
        } set: { action in
            switch action {
            case let .simpleAction(simpleAction):
                self.action = .simpleAction(simpleAction)
            default:
                // TODO: TBD.
                break
            }
        }
    }

    enum ActionType: Hashable {
        case simpleAction(Scheme.Buttons.Mapping.Action.SimpleAction)
        case run
        case mouseWheelScrollUp, mouseWheelScrollDown, mouseWheelScrollLeft, mouseWheelScrollRight
    }
}

extension ButtonMappingActionPicker.ActionType: CustomStringConvertible {
    var description: String {
        switch self {
        case let .simpleAction(simpleAction):
            return simpleAction.description
        case .run:
            return NSLocalizedString("Run command", comment: "")
        case .mouseWheelScrollUp:
            return NSLocalizedString("Scroll up...", comment: "")
        case .mouseWheelScrollDown:
            return NSLocalizedString("Scroll down...", comment: "")
        case .mouseWheelScrollLeft:
            return NSLocalizedString("Scroll left...", comment: "")
        case .mouseWheelScrollRight:
            return NSLocalizedString("Scroll right...", comment: "")
        }
    }
}
