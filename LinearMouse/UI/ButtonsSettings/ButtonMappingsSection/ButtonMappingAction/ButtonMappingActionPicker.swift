// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct ButtonMappingActionPicker: View, Equatable {
    @Binding var actionType: ActionType

    var body: some View {
        Picker("Action", selection: $actionType) {
            ActionTypeTreeView(nodes: Self.actionTypeTree)
        }
        .modifier(PickerViewModifier())
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.actionType == rhs.actionType
    }
}

extension ButtonMappingActionPicker {
    enum ActionType: Equatable, Hashable {
        case arg0(Scheme.Buttons.Mapping.Action.Arg0)
        case run
        case mouseWheelScrollUp, mouseWheelScrollDown, mouseWheelScrollLeft, mouseWheelScrollRight
        case keyPress
    }

    indirect enum ActionTypeTreeNode: Identifiable {
        var id: UUID { UUID() }

        case actionType(ActionType)
        case section(LocalizedStringKey, () -> [Self])
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
                        Self(nodes: getNodes())
                    }
                }
            }
        }
    }

    static let actionTypeTree: [ActionTypeTreeNode] = [
        .actionType(.arg0(.auto)),
        .actionType(.arg0(.none)),
        .section("Mission Control") { [
            .actionType(.arg0(.missionControl)),
            .actionType(.arg0(.missionControlSpaceLeft)),
            .actionType(.arg0(.missionControlSpaceRight))
        ]
        },
        .actionType(.arg0(.appExpose)),
        .actionType(.arg0(.launchpad)),
        .actionType(.arg0(.showDesktop)),
        .actionType(.arg0(.lookUpAndDataDetectors)),
        .actionType(.arg0(.smartZoom)),
        .section("Display") { [
            .actionType(.arg0(.displayBrightnessUp)),
            .actionType(.arg0(.displayBrightnessDown))
        ]
        },
        .section("Media") { [
            .actionType(.arg0(.mediaVolumeUp)),
            .actionType(.arg0(.mediaVolumeDown)),
            .actionType(.arg0(.mediaMute)),
            .actionType(.arg0(.mediaPlayPause)),
            .actionType(.arg0(.mediaPrevious)),
            .actionType(.arg0(.mediaNext)),
            .actionType(.arg0(.mediaFastForward)),
            .actionType(.arg0(.mediaRewind))
        ]
        },
        .section("Keyboard") { [
            .actionType(.arg0(.keyboardBrightnessUp)),
            .actionType(.arg0(.keyboardBrightnessDown)),
            .actionType(.keyPress)
        ]
        },
        .section("Mouse Wheel") { [
            .actionType(.arg0(.mouseWheelScrollUp)),
            .actionType(.mouseWheelScrollUp),
            .actionType(.arg0(.mouseWheelScrollDown)),
            .actionType(.mouseWheelScrollDown),
            .actionType(.arg0(.mouseWheelScrollLeft)),
            .actionType(.mouseWheelScrollLeft),
            .actionType(.arg0(.mouseWheelScrollRight)),
            .actionType(.mouseWheelScrollRight)
        ]
        },
        .section("Mouse Button") { [
            .actionType(.arg0(.mouseButtonLeft)),
            .actionType(.arg0(.mouseButtonLeftDouble)),
            .actionType(.arg0(.mouseButtonMiddle)),
            .actionType(.arg0(.mouseButtonRight)),
            .actionType(.arg0(.mouseButtonBack)),
            .actionType(.arg0(.mouseButtonForward))
        ]
        },
        .section("Execute") { [
            .actionType(.run)
        ]
        }
    ]
}

extension ButtonMappingActionPicker.ActionType: CustomStringConvertible {
    var description: String {
        switch self {
        case let .arg0(value):
            return value.description
        case .run:
            return NSLocalizedString("Run shell command…", comment: "")
        case .mouseWheelScrollUp:
            return NSLocalizedString("Scroll up…", comment: "")
        case .mouseWheelScrollDown:
            return NSLocalizedString("Scroll down…", comment: "")
        case .mouseWheelScrollLeft:
            return NSLocalizedString("Scroll left…", comment: "")
        case .mouseWheelScrollRight:
            return NSLocalizedString("Scroll right…", comment: "")
        case .keyPress:
            return NSLocalizedString("Keyboard shortcut…", comment: "")
        }
    }
}
