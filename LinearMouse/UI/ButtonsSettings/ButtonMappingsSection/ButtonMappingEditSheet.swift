// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ButtonMappingEditSheet: View {
    @Binding var isPresented: Bool

    @ObservedObject private var state: ButtonsSettingsState = .shared

    @Binding var mapping: Scheme.Buttons.Mapping
    let completion: ((Scheme.Buttons.Mapping) -> Void)?

    let mode: Mode

    init(
        isPresented: Binding<Bool>,
        mapping: Binding<Scheme.Buttons.Mapping>,
        mode: Mode = .edit,
        completion: ((Scheme.Buttons.Mapping) -> Void)?
    ) {
        _isPresented = isPresented
        _mapping = mapping
        self.completion = completion
        self.mode = mode
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mode == .create ? "Add Button Mapping" : "Edit Button Mapping")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            VStack(alignment: .leading, spacing: 22) {
                ButtonMappingSheetSection("Trigger") {
                    if mode == .edit {
                        ButtonMappingTriggerSummary(mapping: mapping)
                    } else {
                        ButtonMappingButtonRecorder(
                            mapping: $mapping,
                            autoStartRecording: mode == .create,
                            mode: .advanced
                        )
                    }

                    triggerMessages
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Action")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    ScrollView {
                        if valid {
                            if mapping.isStructured {
                                ButtonMappingActionsEditor(mapping: $mapping)
                            } else {
                                ButtonMappingAction(action: $mapping.recordedAction)
                            }
                        } else {
                            Text("Record a trigger to choose an action.")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 8) {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .sheetSecondaryActionStyle()
                .asCancelAction()

                Button(mode == .create ? "Create" : "OK") {
                    completion?(mapping)
                    isPresented = false
                }
                .disabled(!valid)
                .sheetPrimaryActionStyle()
                .asDefaultAction()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(width: 500, height: 360)
        .onExitCommand {
            isPresented = false
        }
    }

    @ViewBuilder
    private var triggerMessages: some View {
        if conflicted {
            ButtonMappingMessage(
                "The trigger is already assigned.",
                systemImage: "exclamationmark.circle.fill",
                color: .red
            )
        } else if !mapping.valid, mapping.isUnmodifiedStandalonePrimaryButton {
            ButtonMappingMessage(
                "Primary alone only supports Long Press. Add a modifier or another button for other actions.",
                systemImage: "exclamationmark.circle.fill",
                color: .red
            )
        } else {
            switch mapping.primaryButtonUsageRisk {
            case .standaloneLongPress:
                ButtonMappingMessage(
                    "Long Press on Primary delays normal clicks and may interrupt dragging.",
                    systemImage: "exclamationmark.triangle.fill",
                    color: .orange
                )
            case let .simultaneousChord(recommendedHeldButton):
                ButtonMappingMessage(
                    "Combining Primary with another button may briefly delay normal clicks and drags.",
                    systemImage: "exclamationmark.triangle.fill",
                    color: .orange,
                    actionTitle: recommendedHeldButton == nil ? nil : "Use Hold, Then Press"
                ) {
                    guard let recommendedHeldButton else {
                        return
                    }
                    useOrderedPrimaryTrigger(holding: recommendedHeldButton)
                }
            case .heldPrefix:
                ButtonMappingMessage(
                    "Using Primary as the held button delays normal clicks and drags until you release it.",
                    systemImage: "exclamationmark.triangle.fill",
                    color: .orange
                )
            case nil:
                EmptyView()
            }
        }
    }

    private func useOrderedPrimaryTrigger(holding button: Scheme.Buttons.Mapping.Button) {
        guard var trigger = mapping.trigger else {
            return
        }
        trigger.setTwoButtonRelationship(.holdThenPress, preferredHeldButton: button)
        mapping.trigger = trigger
    }
}

private struct ButtonMappingSheetSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ButtonMappingTriggerSummary: View {
    var mapping: Scheme.Buttons.Mapping

    var body: some View {
        HStack {
            ButtonMappingButtonDescription<EmptyView>(mapping: mapping)
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
    }
}

private struct ButtonMappingMessage: View {
    let text: LocalizedStringKey
    let systemImage: String
    let color: Color
    let actionTitle: LocalizedStringKey?
    let action: (() -> Void)?

    init(
        _ text: LocalizedStringKey,
        systemImage: String,
        color: Color,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            messageIcon
                .foregroundColor(color)
            Text(text)
                .foregroundColor(.secondary)
                .layoutPriority(1)

            if let actionTitle, let action {
                Spacer(minLength: 6)
                Button(action: action) {
                    Text(actionTitle)
                        .lineLimit(1)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var messageIcon: some View {
        if #available(macOS 11.0, *) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
        } else {
            Text("!")
                .fontWeight(.semibold)
        }
    }
}

private struct ButtonMappingActionsEditor: View {
    @Binding var mapping: Scheme.Buttons.Mapping

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            actionEditors
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actionEditors: some View {
        if case .wheel = mapping.trigger?.input {
            ButtonMappingAction(action: $mapping.immediateActionBinding)
        } else {
            if mapping.outcomes?.press != nil {
                ButtonMappingAction(action: $mapping.pressAction, label: "While pressed action")
            } else if mapping.outcomes?.shortPress != nil {
                ButtonMappingAction(action: $mapping.shortPressAction, label: "Short press action")
            }
            if mapping.outcomes?.longPress != nil {
                ButtonMappingAction(action: $mapping.longPressAction, label: "Long press action")
            }
            if mapping.outcomes?.swipe?.up != nil {
                ButtonMappingAction(action: $mapping.swipeUpAction, label: "Swipe up action")
            }
            if mapping.outcomes?.swipe?.down != nil {
                ButtonMappingAction(action: $mapping.swipeDownAction, label: "Swipe down action")
            }
            if mapping.outcomes?.swipe?.left != nil {
                ButtonMappingAction(action: $mapping.swipeLeftAction, label: "Swipe left action")
            }
            if mapping.outcomes?.swipe?.right != nil {
                ButtonMappingAction(action: $mapping.swipeRightAction, label: "Swipe right action")
            }

            if mapping.supportsPressBehaviorSelection {
                ButtonMappingBehaviorPicker(mapping: $mapping)
            }
        }
    }
}

private struct ButtonMappingBehaviorPicker: View {
    @Binding var mapping: Scheme.Buttons.Mapping

    var body: some View {
        Picker("Behavior", selection: behavior) {
            ForEach(availableBehaviors) { behavior in
                Text(behavior.title).tag(behavior)
            }
        }
        .modifier(PickerViewModifier())
    }

    private var behavior: Binding<Behavior> {
        Binding(
            get: {
                guard let press = mapping.outcomes?.press else {
                    return .performOnRelease
                }
                switch press.behavior {
                case .perform:
                    return .performOnPress
                case .repeat:
                    return .repeatWhilePressed
                case .hold:
                    return .holdWhilePressed
                case .remap:
                    return .remapWhilePressed
                }
            },
            set: { newBehavior in
                var outcomes = mapping.outcomes ?? .init()
                let action = outcomes.press?.action ?? outcomes.shortPress ?? .arg0(.auto)
                switch newBehavior {
                case .performOnRelease:
                    outcomes.press = nil
                    outcomes.shortPress = action
                case .performOnPress:
                    outcomes.shortPress = nil
                    outcomes.press = .init(action: action, behavior: .perform)
                case .repeatWhilePressed:
                    outcomes.shortPress = nil
                    outcomes.press = .init(action: action, behavior: .repeat)
                case .holdWhilePressed:
                    outcomes.shortPress = nil
                    outcomes.press = .init(action: action, behavior: .hold)
                case .remapWhilePressed:
                    outcomes.shortPress = nil
                    outcomes.press = .init(action: action, behavior: .remap)
                }
                mapping.outcomes = outcomes
            }
        )
    }

    private var availableBehaviors: [Behavior] {
        var behaviors: [Behavior] = [.performOnRelease, .performOnPress, .repeatWhilePressed]
        let action = mapping.outcomes?.press?.action ?? mapping.outcomes?.shortPress
        if case .arg1(.keyPress) = action {
            behaviors.append(.holdWhilePressed)
        }
        if action?.remappedMouseButton != nil,
           case .button(.mouse) = mapping.trigger?.input,
           mapping.trigger?.chordButtons.count == 1,
           mapping.trigger?.whileHeld == nil {
            behaviors.append(.remapWhilePressed)
        }
        return behaviors
    }

    private enum Behavior: String, Identifiable {
        case performOnRelease
        case performOnPress
        case repeatWhilePressed
        case holdWhilePressed
        case remapWhilePressed

        var id: Self {
            self
        }

        var title: LocalizedStringKey {
            switch self {
            case .performOnRelease:
                return "Perform once on release"
            case .performOnPress:
                return "Perform once on press"
            case .repeatWhilePressed:
                return "Repeat while pressed"
            case .holdWhilePressed:
                return "Hold keys while pressed"
            case .remapWhilePressed:
                return "Remap button while pressed"
            }
        }
    }
}

extension ButtonMappingEditSheet {
    enum Mode {
        case edit, create
    }

    var conflicted: Bool {
        guard mode == .create else {
            return false
        }

        return !state.mappings.allSatisfy { !mapping.conflicted(with: $0) }
    }

    var valid: Bool {
        mapping.valid && !conflicted
    }
}

private extension Scheme.Buttons.Mapping {
    var isUnmodifiedStandalonePrimaryButton: Bool {
        guard modifierFlags.isEmpty,
              let trigger = effectiveTrigger,
              case .button(.mouse(0)) = trigger.input else {
            return false
        }
        return trigger.simultaneous?.isEmpty != false && trigger.whileHeld?.isEmpty != false
    }

    var supportsPressBehaviorSelection: Bool {
        guard trigger != nil else {
            return false
        }
        if outcomes?.press != nil {
            return true
        }
        return outcomes?.shortPress != nil && outcomes?.longPress == nil && outcomes?.swipe?.isEmpty != false
    }
}

private extension Scheme.Buttons.Mapping {
    var recordedAction: Action {
        get {
            guard let trigger else {
                return action ?? .arg0(.auto)
            }

            if case .wheel = trigger.input {
                return action ?? .arg0(.auto)
            }
            if let press = outcomes?.press {
                return press.action
            }
            if let longPress = outcomes?.longPress {
                return longPress
            }
            if let swipe = outcomes?.swipe {
                return swipe.up ?? swipe.down ?? swipe.left ?? swipe.right ?? .arg0(.auto)
            }
            return outcomes?.shortPress ?? .arg0(.auto)
        }
        set {
            guard let trigger else {
                action = newValue
                return
            }

            if case .wheel = trigger.input {
                action = newValue
                return
            }
            if outcomes?.press != nil {
                outcomes?.press?.action = newValue
                normalizePressBehaviorForAction()
                return
            }
            if outcomes?.longPress != nil {
                outcomes?.longPress = newValue
                return
            }
            if outcomes?.swipe?.up != nil {
                outcomes?.swipe?.up = newValue
                return
            }
            if outcomes?.swipe?.down != nil {
                outcomes?.swipe?.down = newValue
                return
            }
            if outcomes?.swipe?.left != nil {
                outcomes?.swipe?.left = newValue
                return
            }
            if outcomes?.swipe?.right != nil {
                outcomes?.swipe?.right = newValue
                return
            }
            if outcomes == nil {
                outcomes = .init()
            }
            outcomes?.shortPress = newValue
        }
    }

    mutating func normalizePressBehaviorForAction() {
        guard let press = outcomes?.press else {
            return
        }
        switch press.behavior {
        case .hold:
            guard case .arg1(.keyPress) = press.action else {
                outcomes?.press?.behavior = .perform
                return
            }
        case .remap:
            if press.action.remappedMouseButton == nil {
                outcomes?.press?.behavior = .perform
            }
        case .perform, .repeat:
            break
        }
    }
}

private extension Binding where Value == Scheme.Buttons.Mapping {
    var immediateActionBinding: Binding<Scheme.Buttons.Mapping.Action> {
        actionBinding(
            get: { $0.action },
            set: { $0.action = $1 }
        )
    }

    var pressAction: Binding<Scheme.Buttons.Mapping.Action> {
        actionBinding(
            get: { $0.outcomes?.press?.action },
            set: {
                $0.outcomes?.press?.action = $1
                $0.normalizePressBehaviorForAction()
            }
        )
    }

    var shortPressAction: Binding<Scheme.Buttons.Mapping.Action> {
        actionBinding(
            get: { $0.outcomes?.shortPress },
            set: { $0.outcomes?.shortPress = $1 }
        )
    }

    var longPressAction: Binding<Scheme.Buttons.Mapping.Action> {
        actionBinding(
            get: { $0.outcomes?.longPress },
            set: { $0.outcomes?.longPress = $1 }
        )
    }

    var swipeUpAction: Binding<Scheme.Buttons.Mapping.Action> {
        actionBinding(
            get: { $0.outcomes?.swipe?.up },
            set: { $0.outcomes?.swipe?.up = $1 }
        )
    }

    var swipeDownAction: Binding<Scheme.Buttons.Mapping.Action> {
        actionBinding(
            get: { $0.outcomes?.swipe?.down },
            set: { $0.outcomes?.swipe?.down = $1 }
        )
    }

    var swipeLeftAction: Binding<Scheme.Buttons.Mapping.Action> {
        actionBinding(
            get: { $0.outcomes?.swipe?.left },
            set: { $0.outcomes?.swipe?.left = $1 }
        )
    }

    var swipeRightAction: Binding<Scheme.Buttons.Mapping.Action> {
        actionBinding(
            get: { $0.outcomes?.swipe?.right },
            set: { $0.outcomes?.swipe?.right = $1 }
        )
    }

    private func actionBinding(
        get: @escaping (Value) -> Scheme.Buttons.Mapping.Action?,
        set: @escaping (inout Value, Scheme.Buttons.Mapping.Action) -> Void
    ) -> Binding<Scheme.Buttons.Mapping.Action> {
        Binding<Scheme.Buttons.Mapping.Action>(
            get: { get(wrappedValue) ?? .arg0(.auto) },
            set: { newValue in
                var mapping = wrappedValue
                set(&mapping, newValue)
                wrappedValue = mapping
            }
        )
    }

    var recordedAction: Binding<Scheme.Buttons.Mapping.Action> {
        Binding<Scheme.Buttons.Mapping.Action>(
            get: { wrappedValue.recordedAction },
            set: { wrappedValue.recordedAction = $0 }
        )
    }
}
