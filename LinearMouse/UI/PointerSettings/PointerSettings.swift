// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct PointerSettings: View {
    @ObservedObject var schemeState = SchemeState.shared

    var body: some View {
        DetailView {
            VStack(alignment: .leading, spacing: 20) {
                Form {
                    Slider(value: $schemeState.pointerAcceleration,
                           in: 0.0 ... 20.0) {
                        Text("Acceleration")
                    }
                    HStack {
                        Text("(0–20)")
                            .controlSize(.small)
                            .foregroundColor(.secondary)
                        TextField("",
                                  value: $schemeState.pointerAcceleration,
                                  formatter: schemeState.pointerAccelerationFormatter)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Spacer()
                        .frame(height: 20)

                    Slider(value: $schemeState.pointerSpeed,
                           in: 0.0 ... 1.0) {
                        Text("Speed")
                    }
                    HStack {
                        Text("(0–1)")
                            .controlSize(.small)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        TextField("",
                                  value: $schemeState.pointerSpeed,
                                  formatter: schemeState.pointerSpeedFormatter)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                .disabled(schemeState.pointerDisableAcceleration)

                Spacer()

                HStack(spacing: 15) {
                    Toggle(isOn: $schemeState.pointerDisableAcceleration) {
                        Text("Disable pointer acceleration")
                    }

                    HelpButton {
                        NSWorkspace.shared
                            .open(URL(string: "https://go.linearmouse.app/disable-pointer-acceleration-and-speed")!)
                    }
                }

                Spacer()

                VStack(alignment: .leading) {
                    if #available(macOS 11.0, *) {
                        Text("You may also press ⌃⇧⌘Z to revert to system defaults.")
                            .controlSize(.small)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Revert to system defaults") {
                            revertPointerSpeed()
                        }
                        .keyboardShortcut("z", modifiers: [.control, .command, .shift])
                        .disabled(schemeState.pointerDisableAcceleration)
                    } else {
                        Button("Revert to system defaults") {
                            revertPointerSpeed()
                        }
                        .disabled(schemeState.pointerDisableAcceleration)
                    }
                }
            }
        }
    }

    private func revertPointerSpeed() {
        schemeState.revertPointerSpeed()
    }
}
