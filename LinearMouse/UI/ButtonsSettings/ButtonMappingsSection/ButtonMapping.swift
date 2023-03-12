// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

extension ButtonMappingsSection {
    struct ButtonMapping: View {
        @Binding var mapping: Scheme.Buttons.Mapping

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                MappingDescription(mapping: mapping)
                ActionDescription(action: mapping.action ?? .simpleAction(.auto))
            }
            .padding(.vertical, 4)
        }
    }
}

extension ButtonMappingsSection.ButtonMapping {
    struct MappingDescription: View {
        var mapping: Scheme.Buttons.Mapping

        var body: some View {
            Group {
                if let button = mapping.button {
                    Text("\(modifiersDescription) Button \(button)")
                } else if let scroll = mapping.scroll {
                    Text("\(modifiersDescription) Scroll \(String(describing: scroll))")
                }
            }
            .font(.body.weight(.medium))
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
    }

    struct ActionDescription: View {
        var action: Scheme.Buttons.Mapping.Action

        var body: some View {
            Text(action.description)
                .foregroundColor(.secondary)
        }
    }
}
