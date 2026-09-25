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

                    pointerRedirectsToScrollControl

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
                                .settingsDescriptionStyle()
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
                            .settingsDescriptionStyle()
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

    private var pointerRedirectsToScrollControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 15) {
                Picker(selection: $state.pointerRedirectsToScrollMode.animation()) {
                    Text("Off")
                        .tag(PointerSettingsState.RedirectsToScrollMode.off)
                    Text("While holding a trigger")
                        .tag(PointerSettingsState.RedirectsToScrollMode.whileHoldingTrigger)
                    Text("Always")
                        .tag(PointerSettingsState.RedirectsToScrollMode.always)
                } label: {
                    withDescription {
                        Text("Convert pointer movement to scroll events")
                        Text("Scrolling settings are applied to converted events.")
                    }
                }
                .modifier(PickerViewModifier())
            }

            if state.pointerRedirectsToScrollMode == .whileHoldingTrigger {
                pointerRedirectsToScrollTriggerControl
            }

            if state.redirectsToScrollAlwaysSecondsUntilRevert != nil {
                pointerRedirectsToScrollAlwaysRevertNotice
            }
        }
        .alert(isPresented: $state.redirectsToScrollAlwaysConfirmationPresented) {
            Alert(
                title: Text("Always convert pointer movement to scroll events?"),
                message: Text(
                    "This device will stop moving the pointer. To undo it you will need the keyboard or another mouse or trackpad, so it is reverted automatically unless you confirm."
                ),
                primaryButton: .default(Text("Turn On")) {
                    state.confirmRedirectsToScrollAlways()
                },
                secondaryButton: .cancel {
                    state.cancelRedirectsToScrollAlways()
                }
            )
        }
    }

    /// Mirrors how macOS confirms a display change: the setting is already
    /// live, and goes back by itself unless it is kept. Where the API is
    /// available, "Keep" is the default button and "Revert" the cancel one, so
    /// both are reachable from the keyboard while the pointer is unusable.
    private var pointerRedirectsToScrollAlwaysRevertNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let seconds = state.redirectsToScrollAlwaysSecondsUntilRevert {
                Text("Reverting in \(seconds) second(s) unless you keep this setting.")
                    .settingsDescriptionStyle()
            }

            HStack {
                if #available(macOS 11.0, *) {
                    Button("Keep") {
                        state.keepRedirectsToScrollAlways()
                    }
                    .keyboardShortcut(.defaultAction)

                    Button("Revert") {
                        state.revertRedirectsToScrollAlways()
                    }
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button("Keep") {
                        state.keepRedirectsToScrollAlways()
                    }

                    Button("Revert") {
                        state.revertRedirectsToScrollAlways()
                    }
                }
            }
        }
    }

    private var pointerRedirectsToScrollTriggerControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trigger")
                .font(.headline)

            HStack {
                ButtonMappingButtonRecorder(
                    mapping: state.pointerRedirectsToScrollTriggerBinding
                )

                if state.pointerRedirectsToScrollTrigger != nil {
                    Button("Clear") {
                        state.pointerRedirectsToScrollTrigger = nil
                    }
                }
            }

            if !state.pointerRedirectsToScrollTriggerValid {
                Text("Choose a mouse button trigger. Left click without modifier keys is not allowed.")
                    .foregroundColor(.red)
                    .controlSize(.small)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if state.pointerRedirectsToScrollTrigger == nil {
                Text("Record a trigger to start converting. Until then, pointer movement is left alone.")
                    .settingsDescriptionStyle()
            } else {
                Text("Convert only while the trigger is held.")
                    .settingsDescriptionStyle()
            }
        }
    }

    private var pointerHardwareDPIControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info = state.pointerHardwareDPIInfo,
               info.currentDPI != nil,
               let range = info.dpiRange {
                pointerHardwareDPISetter(range: range)

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

            DeferredNumberField(
                value: Binding(
                    get: { Double(state.pointerHardwareDPITargetDPI) },
                    set: { state.commitPointerHardwareDPITargetDPI(Int($0.rounded())) }
                ),
                formatter: state.pointerDPIFormatter,
                range: Double(range.lowerBound) ... Double(range.upperBound)
            )
            .frame(width: 80)
            .accessibility(label: Text("Hardware DPI"))
        }
    }
}
