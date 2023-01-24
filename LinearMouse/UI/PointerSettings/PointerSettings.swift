// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct PointerSettings: View {
    @ObservedObject var schemeState = SchemeState.shared

    var body: some View {
        DetailView {
            Form {
                Section {
                    HStack(spacing: 15) {
                        Toggle(isOn: $schemeState.pointerDisableAcceleration.animation()) {
                            Text("Disable pointer acceleration")
                        }

                        HelpButton {
                            NSWorkspace.shared
                                .open(URL(string: "https://go.linearmouse.app/disable-pointer-acceleration-and-speed")!)
                        }
                    }

                    if !schemeState.pointerDisableAcceleration {
                        HStack(alignment: .top) {
                            Slider(value: $schemeState.pointerAcceleration,
                                   in: 0.0 ... 20.0) {
                                labelWithDescription {
                                    Text("Acceleration")
                                    Text("(0–20)")
                                }
                            }
                            TextField("",
                                      value: $schemeState.pointerAcceleration,
                                      formatter: schemeState.pointerAccelerationFormatter)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }

                        HStack(alignment: .top) {
                            Slider(value: $schemeState.pointerSpeed,
                                   in: 0.0 ... 1.0) {
                                labelWithDescription {
                                    Text("Speed")
                                    Text("(0–1)")
                                }
                            }
                            TextField("",
                                      value: $schemeState.pointerSpeed,
                                      formatter: schemeState.pointerSpeedFormatter)
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
                    }
                }
                .modifier(SectionViewModifier())
            }
            .modifier(FormViewModifier())
        }
    }

    private func revertPointerSpeed() {
        schemeState.revertPointerSpeed()
    }
}
