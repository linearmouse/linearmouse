// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ButtonMappingListItem: View {
    @Binding var mapping: Scheme.Buttons.Mapping
    var onEdit: (Scheme.Buttons.Mapping) -> Void

    @State private var hover = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                ButtonMappingButtonDescription<EmptyView>(mapping: mapping)
                ForEach(actionRows) { row in
                    HStack(spacing: 4) {
                        if let label = row.label {
                            Text(label)
                                .foregroundColor(.secondary)
                        }
                        ButtonMappingActionDescription(action: row.action)
                    }
                }
            }

            Spacer()

            Button("Edit") {
                onEdit(mapping)
            }
            .opacity(hover ? 1 : 0)
        }
        .padding(.vertical, 4)
        .onHover {
            hover = $0
        }
    }

    private var actionRows: [ActionRow] {
        guard mapping.isStructured else {
            return [.init(id: "action", action: mapping.action ?? .arg0(.auto))]
        }

        if case .wheel = mapping.trigger?.input {
            return [.init(id: "wheel", action: mapping.action ?? .arg0(.auto))]
        }

        var rows = [ActionRow]()
        if let press = mapping.outcomes?.press {
            rows.append(.init(id: "press", label: press.behavior.label, action: press.action))
        }
        if let action = mapping.outcomes?.shortPress {
            rows.append(.init(id: "short", label: "Short press:", action: action))
        }
        if let action = mapping.outcomes?.longPress {
            rows.append(.init(id: "long", label: "Long press:", action: action))
        }
        if let action = mapping.outcomes?.swipe?.up {
            rows.append(.init(id: "swipe-up", label: "Swipe up:", action: action))
        }
        if let action = mapping.outcomes?.swipe?.down {
            rows.append(.init(id: "swipe-down", label: "Swipe down:", action: action))
        }
        if let action = mapping.outcomes?.swipe?.left {
            rows.append(.init(id: "swipe-left", label: "Swipe left:", action: action))
        }
        if let action = mapping.outcomes?.swipe?.right {
            rows.append(.init(id: "swipe-right", label: "Swipe right:", action: action))
        }
        return rows
    }

    private struct ActionRow: Identifiable {
        var id: String
        var label: LocalizedStringKey?
        var action: Scheme.Buttons.Mapping.Action
    }
}

private extension Scheme.Buttons.Mapping.PressAction.Behavior {
    var label: LocalizedStringKey {
        switch self {
        case .perform:
            return "On press:"
        case .repeat:
            return "Repeat:"
        case .hold:
            return "Hold:"
        case .remap:
            return "Remap:"
        }
    }
}

struct ButtonMappingButtonDescription<FallbackView: View>: View {
    var mapping: Scheme.Buttons.Mapping
    var showPartial = false
    var fallback: (() -> FallbackView)?

    var body: some View {
        if let trigger = mapping.trigger {
            descriptionRow {
                if let triggerDescription = ButtonMappingTriggerText.description(for: trigger) {
                    Text(triggerDescription)
                } else {
                    switch trigger.input {
                    case let .button(button):
                        Text(buttonDescription(of: button))
                    case let .wheel(direction):
                        Text(scrollDescription(of: direction))
                    }
                }
            }
        } else if let button = mapping.button {
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

enum ButtonMappingTriggerText {
    typealias Mapping = Scheme.Buttons.Mapping

    static func description(for trigger: Mapping.Trigger) -> String? {
        description(for: trigger, buttonDescription: buttonDescription)
    }

    static func description(
        for trigger: Mapping.Trigger,
        buttonDescription: (Mapping.Button) -> String
    ) -> String? {
        let heldButtons = trigger.whileHeld ?? []

        switch trigger.input {
        case let .button(button):
            if let simultaneous = trigger.simultaneous, !simultaneous.isEmpty {
                let simultaneousDescription = String(
                    format: NSLocalizedString(
                        "Press %@ simultaneously with %@",
                        comment: "Localized simultaneous button trigger"
                    ),
                    buttonDescription(button),
                    buttonListDescription(simultaneous, using: buttonDescription)
                )

                guard !heldButtons.isEmpty else {
                    return simultaneousDescription
                }

                return String(
                    format: NSLocalizedString(
                        "Hold %@, then %@",
                        comment: "Localized ordered button trigger"
                    ),
                    buttonListDescription(heldButtons, using: buttonDescription),
                    simultaneousDescription
                )
            }

            guard !heldButtons.isEmpty else {
                return nil
            }

            return String(
                format: NSLocalizedString(
                    "Hold %@, then press %@",
                    comment: "Localized ordered button trigger"
                ),
                buttonListDescription(heldButtons, using: buttonDescription),
                buttonDescription(button)
            )
        case let .wheel(direction):
            guard !heldButtons.isEmpty else {
                return nil
            }

            return String(
                format: NSLocalizedString(
                    "Hold %@, then %@",
                    comment: "Localized ordered button trigger"
                ),
                buttonListDescription(heldButtons, using: buttonDescription),
                scrollDescription(direction)
            )
        }
    }

    static func buttonDescription(_ button: Mapping.Button) -> String {
        switch button {
        case let .mouse(buttonNumber):
            switch buttonNumber {
            case 0:
                return NSLocalizedString("Primary click", comment: "Primary mouse button")
            case 1:
                return NSLocalizedString("Secondary click", comment: "Secondary mouse button")
            case 2:
                return NSLocalizedString("Middle click", comment: "Middle mouse button")
            default:
                return String(
                    format: NSLocalizedString("Button #%lld click", comment: "Mouse button description"),
                    Int64(buttonNumber)
                )
            }
        case let .logitechControl(identity):
            return identity.userVisibleName
        }
    }

    private static func buttonListDescription(
        _ buttons: [Mapping.Button],
        using buttonDescription: (Mapping.Button) -> String
    ) -> String {
        let descriptions = buttons.map(buttonDescription)
        guard let last = descriptions.last else {
            return ""
        }
        guard descriptions.count > 1 else {
            return last
        }

        let conjunction = NSLocalizedString("and", comment: "Button list conjunction")
        return descriptions.dropLast().joined(separator: ", ") + " " + conjunction + " " + last
    }

    private static func scrollDescription(_ direction: Mapping.ScrollDirection) -> String {
        let arrow: String
        switch direction {
        case .up:
            arrow = "↑"
        case .down:
            arrow = "↓"
        case .left:
            arrow = "←"
        case .right:
            arrow = "→"
        }
        return String(
            format: NSLocalizedString("Scroll %@", comment: "Recorded gesture token"),
            arrow
        )
    }
}

struct ButtonMappingActionDescription: View {
    var action: Scheme.Buttons.Mapping.Action

    var body: some View {
        Text(action.description)
            .foregroundColor(.secondary)
    }
}
