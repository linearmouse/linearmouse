// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct GestureButtonSection: View {
    @ObservedObject var state: ButtonsSettingsState = .shared

    var isMouseDevice: Bool {
        DeviceState.shared.currentDeviceRef?.value?.category == .mouse
    }

    var body: some View {
        if isMouseDevice {
            primaryGestureSection
            secondaryGestureSection
        }
    }

    @ViewBuilder
    private var primaryGestureSection: some View {
        Section {
            Toggle(isOn: $state.gestureEnabled.animation()) {
                withDescription {
                    Text("Enable primary gesture button")
                    Text(
                        "Press and hold a button while dragging to trigger gestures like switching desktop spaces or opening Mission Control."
                    )
                }
            }

            if state.gestureEnabled {
                gestureConfiguration(
                    trigger: state.gestureTriggerBinding,
                    triggerValid: state.gestureTriggerValid,
                    threshold: $state.gestureThresholdDouble,
                    thresholdPixels: state.gestureThreshold,
                    actionLeft: $state.gestureActionLeft,
                    actionRight: $state.gestureActionRight,
                    actionUp: $state.gestureActionUp,
                    actionDown: $state.gestureActionDown
                )
            }
        }
        .modifier(SectionViewModifier())
    }

    @ViewBuilder
    private var secondaryGestureSection: some View {
        Section {
            Toggle(isOn: $state.secondaryGestureEnabled.animation()) {
                withDescription {
                    Text("Enable secondary gesture button")
                    Text(
                        "Use a second mouse button as an independent gesture trigger."
                    )
                }
            }

            if state.secondaryGestureEnabled {
                gestureConfiguration(
                    trigger: state.secondaryGestureTriggerBinding,
                    triggerValid: state.secondaryGestureTriggerValid,
                    threshold: $state.secondaryGestureThresholdDouble,
                    thresholdPixels: state.secondaryGestureThreshold,
                    actionLeft: $state.secondaryGestureActionLeft,
                    actionRight: $state.secondaryGestureActionRight,
                    actionUp: $state.secondaryGestureActionUp,
                    actionDown: $state.secondaryGestureActionDown
                )
            }
        }
        .modifier(SectionViewModifier())
    }

    @ViewBuilder
    private func gestureConfiguration(
        trigger: Binding<Scheme.Buttons.Mapping>,
        triggerValid: Bool,
        threshold: Binding<Double>,
        thresholdPixels: Int,
        actionLeft: Binding<Scheme.Buttons.Gesture.GestureAction>,
        actionRight: Binding<Scheme.Buttons.Gesture.GestureAction>,
        actionUp: Binding<Scheme.Buttons.Gesture.GestureAction>,
        actionDown: Binding<Scheme.Buttons.Gesture.GestureAction>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trigger")
                .font(.headline)

            ButtonMappingButtonRecorder(
                mapping: trigger
            )

            if !triggerValid {
                Text("Choose a mouse button trigger. Left click without modifier keys is not allowed.")
                    .foregroundColor(.red)
                    .controlSize(.small)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Threshold")
                Spacer()
                Text("\(thresholdPixels) pixels")
                    .foregroundColor(.secondary)
            }

            Slider(
                value: threshold,
                in: 20 ... 200,
                step: 5
            )
        }

        Divider()

        Text("Gesture Actions")
            .font(.headline)

        GestureActionPicker(
            label: "Swipe left",
            selection: actionLeft
        )

        GestureActionPicker(
            label: "Swipe right",
            selection: actionRight
        )

        GestureActionPicker(
            label: "Swipe up",
            selection: actionUp
        )

        GestureActionPicker(
            label: "Swipe down",
            selection: actionDown
        )

        Text(
            "Hold the button and drag to trigger gestures. Drag at least \(thresholdPixels) pixels in one direction."
        )
        .settingsDescriptionStyle()
        .padding(.top, 8)
    }
}
