// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct GestureButtonSection: View {
    @ObservedObject var state: ButtonsSettingsState = .shared
    
    var isMouseDevice: Bool {
        DeviceState.shared.currentDeviceRef?.value?.category == .mouse
    }

    var body: some View {
        if isMouseDevice {
            Section {
            Toggle(isOn: $state.gestureEnabled.animation()) {
                withDescription {
                    Text("Enable gesture button")
                    Text(
                        "Press and hold a button while dragging to trigger gestures like switching desktop spaces or opening Mission Control."
                    )
                }
            }

            if state.gestureEnabled {
                Picker("Button", selection: $state.gestureButton) {
                    Text("Middle Button").tag(2)
//                    Text("Back Button").tag(3)
//                    Text("Forward Button").tag(4)
                }
                .modifier(PickerViewModifier())

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Threshold")
                        Spacer()
                        Text("\(state.gestureThreshold) pixels")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $state.gestureThresholdDouble, in: 20 ... 200, step: 5)
                }

                Divider()

                Text("Gesture Actions")
                    .font(.headline)

                GestureActionPicker(
                    label: "Swipe left",
                    selection: $state.gestureActionLeft
                )

                GestureActionPicker(
                    label: "Swipe right",
                    selection: $state.gestureActionRight
                )

                GestureActionPicker(
                    label: "Swipe up",
                    selection: $state.gestureActionUp
                )

                GestureActionPicker(
                    label: "Swipe down",
                    selection: $state.gestureActionDown
                )

                Text(
                    "Hold the button and drag to trigger gestures. Drag at least \(state.gestureThreshold) pixels in one direction."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            }
        }
        .modifier(SectionViewModifier())
        }
    }
}
