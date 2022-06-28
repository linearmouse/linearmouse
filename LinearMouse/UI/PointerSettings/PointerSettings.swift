// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct PointerSettings: View {
    @StateObject var state = PointerSettingsState()

    var body: some View {
        DetailView {
            VStack(alignment: .leading, spacing: 20) {
                Form {
                    Slider(value: $state.pointerAcceleration,
                           in: 0.0 ... 20.0) {
                        Text("Acceleration")
                    }
                    HStack {
                        Text("(0–20)")
                            .controlSize(.small)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        TextField("",
                                  value: $state.pointerAcceleration,
                                  formatter: state.pointerAccelerationFormatter)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Slider(value: $state.pointerSpeed,
                           in: 0 ... 1) {
                        Text("Speed")
                    }.padding(.top)
                    HStack {
                        Text("(0–1)")
                            .controlSize(.small)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        TextField("",
                                  value: $state.pointerSpeed,
                                  formatter: state.pointerSpeedFormatter)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                .disabled(state.pointerDisableAcceleration)

                Spacer()

                Toggle(isOn: $state.pointerDisableAcceleration) {
                    Text("Disable pointer acceleration")
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
                        .disabled(state.pointerDisableAcceleration)
                    } else {
                        Button("Revert to system defaults") {
                            revertPointerSpeed()
                        }
                        .disabled(state.pointerDisableAcceleration)
                    }
                }
            }
        }
    }

    private func revertPointerSpeed() {
        state.revertPointerSpeed()
    }
}

struct CursorSettings_Previews: PreviewProvider {
    static var previews: some View {
        PointerSettings()
    }
}
