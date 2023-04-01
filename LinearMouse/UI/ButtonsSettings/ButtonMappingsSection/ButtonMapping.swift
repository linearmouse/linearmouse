// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ButtonMappingListItem: View {
    var mapping: Scheme.Buttons.Mapping

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                ButtonMappingButtonDescription<EmptyView>(mapping: mapping)
                ButtonMappingActionDescription(action: mapping.action ?? .simpleAction(.auto))
            }
        }
        .padding(.vertical, 4)
    }
}

struct ButtonMappingButtonDescription<FallbackView: View>: View {
    var mapping: Scheme.Buttons.Mapping
    var fallback: (() -> FallbackView)?

    var body: some View {
        if let button = mapping.button {
            HStack(spacing: 5) {
                Text(modifiersDescription)
                Text(buttonDescription(of: button))
            }
        } else if let scroll = mapping.scroll {
            HStack(spacing: 5) {
                Text(modifiersDescription)
                Text(scrollDescription(of: scroll))
            }
        } else {
            if let fallback {
                fallback()
            } else {
                Text("Not specified")
            }
        }
    }

    private var modifiersDescription: String {
        [
            (mapping.command, "⌘"),
            (mapping.shift, "⇧"),
            (mapping.option, "⌥"),
            (mapping.control, "⌃")
        ]
        .compactMap { $0.0 == true ? $0.1 : nil }
        .joined()
    }

    private func buttonDescription(of button: Int) -> LocalizedStringKey {
        switch button {
        case 0:
            return "Left click"
        case 1:
            return "Right click"
        case 2:
            return "Middle click"
        default:
            return "Button #\(button) click"
        }
    }

    private func scrollDescription(of scroll: Scheme.Buttons.Mapping.ScrollDirection) -> LocalizedStringKey {
        switch scroll {
        case .up:
            return "Scroll up"
        case .down:
            return "Scroll down"
        case .left:
            return "Scroll left"
        case .right:
            return "Scroll right"
        }
    }
}

struct ButtonMappingActionDescription: View {
    var action: Scheme.Buttons.Mapping.Action

    var body: some View {
        Text(action.description)
            .foregroundColor(.secondary)
    }
}
