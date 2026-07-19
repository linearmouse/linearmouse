// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct PointerSettings: View {
    @ObservedObject var state = PointerSettingsState.shared
    @State private var isPointerSpeedLimitationPopoverPresented = false

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
                                in: 0.0 ... 40.0
                            ) {
                                labelWithDescription {
                                    Text("Pointer acceleration")
                                    Text(verbatim: "(0–40)")
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
                                    HStack(spacing: 4) {
                                        Text("Pointer speed")

                                        if state.showsPointerSpeedLimitationNotice {
                                            Button {
                                                isPointerSpeedLimitationPopoverPresented.toggle()
                                            } label: {
                                                Text(verbatim: "⚠︎")
                                                    .foregroundColor(.orange)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .popover(
                                                isPresented: $isPointerSpeedLimitationPopoverPresented,
                                                arrowEdge: .top
                                            ) {
                                                VStack(alignment: .leading, spacing: 10) {
                                                    Text(
                                                        "Due to system limitations, this device may not support adjusting Pointer Speed on newer versions of macOS."
                                                    )
                                                    .fixedSize(horizontal: false, vertical: true)

                                                    HyperLink(
                                                        URL(
                                                            string: "https://go.linearmouse.app/pointer-speed-limitations"
                                                        )!
                                                    ) {
                                                        Text("Learn more")
                                                    }
                                                }
                                                .padding()
                                                .frame(width: 280, alignment: .leading)
                                            }
                                        }
                                    }

                                    Text(verbatim: "(0–1)")
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

                        if state.showsPointerHardwareDPIControl {
                            pointerHardwareDPIControl
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
                                in: 0.0 ... 40.0
                            ) {
                                labelWithDescription {
                                    Text("Tracking speed")
                                    Text(verbatim: "(0–40)")
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

                        if state.showsPointerHardwareDPIControl {
                            pointerHardwareDPIControl
                        }

                        Button("Revert to system defaults") {
                            revertPointerSpeed()
                        }
                        .keyboardShortcut("z", modifiers: [.control, .command, .shift])

                        Text("You may also press ⌃⇧⌘Z to revert to system defaults.")
                            .controlSize(.small)
                            .foregroundColor(.secondary)
                    } else {
                        if state.showsPointerHardwareDPIControl {
                            pointerHardwareDPIControl
                        }
                    }
                }
                .modifier(SectionViewModifier())
            }
            .modifier(FormViewModifier())
        }
        .onAppear {
            state.refreshPointerHardwareDPIInfo()
        }
    }

    private func revertPointerSpeed() {
        state.revertPointerSpeed()
    }

    private var pointerHardwareDPIControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info = state.pointerHardwareDPIInfo,
               info.currentDPI != nil,
               let range = info.dpiRange {
                pointerHardwareDPISetter(range: range)
                    .disabled(state.pointerHardwareDPIBusy)

                if let message = state.pointerHardwareDPIStatusMessage {
                    Text(message)
                        .foregroundColor(.secondary)
                }
            } else if state.pointerHardwareDPIBusy {
                Text(state.pointerHardwareDPIApplying ? "Applying..." : "Refreshing...")
                    .foregroundColor(.secondary)
            } else {
                Text(state.pointerHardwareDPIStatusMessage ?? "Reading hardware DPI from the selected device.")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func pointerHardwareDPISetter(range: ClosedRange<Int>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if range.lowerBound < range.upperBound {
                Slider(
                    value: Binding(
                        get: { Double(state.pointerHardwareDPITargetDPI) },
                        set: { state.updatePointerHardwareDPITargetDPI(Int($0.rounded())) }
                    ),
                    in: Double(range.lowerBound) ... Double(range.upperBound)
                ) {
                    labelWithDescription {
                        Text("Hardware DPI")
                        Text(verbatim: "(\(range.lowerBound)–\(range.upperBound))")
                    }
                }
            } else {
                labelWithDescription {
                    Text("Hardware DPI")
                    Text(verbatim: "(\(range.lowerBound))")
                }
                Spacer()
            }

            TextField(
                "Hardware DPI",
                value: Binding(
                    get: { state.pointerHardwareDPITargetDPI },
                    set: { state.updatePointerHardwareDPITargetDPI($0) }
                ),
                formatter: state.pointerDPIFormatter
            )
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
        }
    }
}
