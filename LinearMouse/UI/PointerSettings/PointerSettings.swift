// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct PointerSettings: View {
    @ObservedObject var state = PointerSettingsState.shared

    var body: some View {
        DetailView {
            Form {
                Section {
                    HStack(spacing: 15) {
                        Toggle(isOn: $state.pointerDisableAcceleration.animation()) {
                            Text("Disable pointer acceleration")
                        }

                        HelpButton {
                            NSWorkspace.shared
                                .open(URL(string: "https://go.linearmouse.app/disable-pointer-acceleration-and-speed")!)
                        }
                    }

                    HStack(spacing: 15) {
                        Toggle(isOn: $state.pointerRedirectsToScroll.animation()) {
                            Text("Convert pointer movement to scroll events")
                            Text("Scrolling settings are applied to converted events.")
                                .controlSize(.small)
                                .foregroundColor(.secondary)
                        }
                    }

                    if !state.pointerDisableAcceleration {
                        HStack(alignment: .firstTextBaseline) {
                            Slider(
                                value: $state.pointerAcceleration,
                                in: 0.0 ... 20.0
                            ) {
                                labelWithDescription {
                                    Text("Pointer acceleration")
                                    Text("(0–20)")
                                }
                            }
                            TextField(
                                String(""),
                                value: $state.pointerAcceleration,
                                formatter: state.pointerAccelerationFormatter
                            )
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Slider(
                                value: $state.pointerSpeed,
                                in: 0.0 ... 1.0
                            ) {
                                labelWithDescription {
                                    Text("Pointer speed")
                                    Text("(0–1)")
                                }
                            }
                            TextField(
                                String(""),
                                value: $state.pointerSpeed,
                                formatter: state.pointerSpeedFormatter
                            )
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        }

                        if #available(macOS 11.0, *) {
                            Button("Revert to system defaults") {
                                revertPointerSpeed()
                            }
                            .keyboardShortcut("z", modifiers: [.control, .command, .shift])

                            Text("You may also press ⌃⇧⌘Z to revert to system defaults.")
                                .controlSize(.small)
                                .foregroundColor(.secondary)
                        } else {
                            Button("Revert to system defaults") {
                                revertPointerSpeed()
                            }
                        }
                    } else if #available(macOS 14, *) {
                        HStack(alignment: .firstTextBaseline) {
                            Slider(
                                value: $state.pointerAcceleration,
                                in: 0.0 ... 20.0
                            ) {
                                labelWithDescription {
                                    Text("Tracking speed")
                                    Text("(0–20)")
                                }
                            }
                            TextField(
                                String(""),
                                value: $state.pointerAcceleration,
                                formatter: state.pointerAccelerationFormatter
                            )
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        }

                        Button("Revert to system defaults") {
                            revertPointerSpeed()
                        }
                        .keyboardShortcut("z", modifiers: [.control, .command, .shift])

                        Text("You may also press ⌃⇧⌘Z to revert to system defaults.")
                            .controlSize(.small)
                            .foregroundColor(.secondary)
                    }
                }
                .modifier(SectionViewModifier())
            }
            .modifier(FormViewModifier())
        }
    }

    private func revertPointerSpeed() {
        state.revertPointerSpeed()
    }
}
