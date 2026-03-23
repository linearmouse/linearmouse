// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ButtonMappingListItem: View {
    @Binding var mapping: Scheme.Buttons.Mapping

    @State private var hover = false

    @State private var showEditSheet = false
    @State private var mappingToEdit: Scheme.Buttons.Mapping = .init()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                ButtonMappingButtonDescription<EmptyView>(mapping: mapping)
                ButtonMappingActionDescription(action: mapping.action ?? .arg0(.auto))
            }

            Spacer()

            Button("Edit") {
                mappingToEdit = mapping
                showEditSheet.toggle()
            }
            .opacity(hover ? 1 : 0)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showEditSheet) {
            ButtonMappingEditSheet(isPresented: $showEditSheet, mapping: $mappingToEdit) { mapping in
                self.mapping = mapping
            }
        }
        .onHover {
            hover = $0
        }
    }
}

struct ButtonMappingButtonDescription<FallbackView: View>: View {
    var mapping: Scheme.Buttons.Mapping
    var showPartial = false
    var fallback: (() -> FallbackView)?

    var body: some View {
        if let button = mapping.button {
            descriptionRow {
                Text(buttonDescription(of: button))
            }
        } else if let scroll = mapping.scroll {
            descriptionRow {
                Text(scrollDescription(of: scroll))
            }
        } else if showPartial, !mapping.modifierFlags.isEmpty {
            Text(modifiersDescription)
        } else {
            if let fallback {
                fallback()
            } else {
                Text("Not specified")
            }
        }
    }

    private var modifiersDescription: String {
        let flags = mapping.modifierFlags
        let modifierDescriptions: [(Bool, String)] = [
            (flags.contains(CGEventFlags.maskControl), "⌃"),
            (flags.contains(CGEventFlags.maskAlternate), "⌥"),
            (flags.contains(CGEventFlags.maskShift), "⇧"),
            (flags.contains(CGEventFlags.maskCommand), "⌘")
        ]

        return modifierDescriptions
            .compactMap { $0.0 == true ? $0.1 : nil }
            .joined()
    }

    @ViewBuilder
    private func descriptionRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if modifiersDescription.isEmpty {
            content()
        } else {
            HStack(spacing: 5) {
                Text(modifiersDescription)
                content()
            }
        }
    }

    private func buttonDescription(of button: Scheme.Buttons.Mapping.Button) -> LocalizedStringKey {
        switch button {
        case let .mouse(buttonNumber):
            switch buttonNumber {
            case 0:
                return "Primary click"
            case 1:
                return "Secondary click"
            case 2:
                return "Middle click"
            default:
                return "Button #\(buttonNumber) click"
            }
        case let .logitechControl(identity):
            return LocalizedStringKey(identity.userVisibleName)
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
