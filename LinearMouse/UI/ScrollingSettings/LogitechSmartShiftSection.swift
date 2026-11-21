// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

extension ScrollingSettings {
    struct LogitechSmartShiftSection: View {
        @ObservedObject private var state = ScrollingSettingsState.shared
        @State private var draggedThreshold: Double?
        @State private var draggedTorque: Double?

        var body: some View {
            Section {
                Picker("Wheel mode", selection: $state.smartShiftMode) {
                    Text("Ratchet").tag(Scheme.Logitech.SmartShift.Mode.ratchet)
                    Text("Free spin").tag(Scheme.Logitech.SmartShift.Mode.freeSpin)
                }
                .modifier(PickerViewModifier())

                Toggle(isOn: $state.smartShiftAutomatic) {
                    withDescription {
                        Text("SmartShift")
                        Text("Switch from ratchet to free spin when you flick the wheel.")
                    }
                }

                if state.smartShiftAutomatic {
                    Slider(
                        value: Binding(
                            get: { draggedThreshold ?? Double(state.smartShiftThreshold) },
                            set: { draggedThreshold = $0 }
                        ),
                        in: Double(ScrollingSettingsState.smartShiftThresholdRange.lowerBound)
                            ... Double(ScrollingSettingsState.smartShiftThresholdRange.upperBound),
                        step: 1
                    ) {
                        labelWithDescription {
                            Text("SmartShift threshold")
                            Text(verbatim: "(\(Int(draggedThreshold ?? Double(state.smartShiftThreshold))))")
                        }
                    } minimumValueLabel: {
                        Text("Sensitive")
                    } maximumValueLabel: {
                        Text("Firm")
                    } onEditingChanged: { editing in
                        guard !editing, let draggedThreshold else {
                            return
                        }
                        state.smartShiftThreshold = Int(draggedThreshold.rounded())
                        self.draggedThreshold = nil
                    }
                }

                if state.supportsSmartShiftTorque {
                    Slider(
                        value: Binding(
                            get: { draggedTorque ?? Double(state.smartShiftTorque) },
                            set: { draggedTorque = $0 }
                        ),
                        in: 1 ... 100,
                        step: 1
                    ) {
                        labelWithDescription {
                            Text("Ratchet force")
                            Text(verbatim: "(\(Int(draggedTorque ?? Double(state.smartShiftTorque)))%)")
                        }
                    } minimumValueLabel: {
                        Text("Light")
                    } maximumValueLabel: {
                        Text("Strong")
                    } onEditingChanged: { editing in
                        guard !editing, let draggedTorque else {
                            return
                        }
                        state.smartShiftTorque = Int(draggedTorque.rounded())
                        self.draggedTorque = nil
                    }
                }
            }
            .modifier(SectionViewModifier())
        }
    }
}
