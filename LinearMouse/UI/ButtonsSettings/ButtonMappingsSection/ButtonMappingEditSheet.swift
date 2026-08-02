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
        if !valid, conflicted {
            ButtonMappingMessage(
                "The trigger is already assigned.",
                systemImage: "exclamationmark.circle.fill",
                color: .red
            )
        }

        if !valid, mapping.isUnmodifiedStandalonePrimaryButton {
            ButtonMappingMessage(
                "Without modifiers, Primary click can only be assigned to Long Press.",
                systemImage: "exclamationmark.circle.fill",
                color: .red
            )
        } else if mapping.isUnmodifiedStandalonePrimaryLongPress {
            ButtonMappingMessage(
                "Recognizing a Primary click long press may delay clicks and interfere with dragging.",
                systemImage: "exclamationmark.triangle.fill",
                color: .orange
            )
        } else if mapping.isUnmodifiedPrimarySecondaryChord {
            ButtonMappingMessage(
                "To keep normal Primary clicks and drags responsive, record this as Hold Secondary → Primary.",
                systemImage: "lightbulb.fill",
                color: .orange
            )
        } else if mapping.isUnmodifiedSecondaryHeldPrimaryTrigger {
            ButtonMappingMessage(
                "Primary clicks and drags are only captured while Secondary is held.",
                systemImage: "info.circle.fill",
                color: .accentColor
            )
        } else if mapping.mayAffectPrimaryButtonUsage {
            ButtonMappingMessage(
                "This trigger may delay primary clicks or drag gestures while it is being recognized.",
                systemImage: "exclamationmark.triangle.fill",
                color: .orange
            )
        }
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

    init(_ text: LocalizedStringKey, systemImage: String, color: Color) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            messageIcon
                .foregroundColor(color)
            Text(text)
                .foregroundColor(.secondary)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var messageIcon: some View {
        if #available(macOS 11.0, *) {
            Image(systemName: systemImage)
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
        return trigger.simultaneous == nil && trigger.whileHeld == nil
    }

    var isUnmodifiedStandalonePrimaryLongPress: Bool {
        isUnmodifiedStandalonePrimaryButton && outcomes?.isLongPressOnly == true
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
