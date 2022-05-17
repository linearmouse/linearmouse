//
//  CursorView.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/12/9.
//

import SwiftUI

struct CursorView: View {
    @ObservedObject var defaults = AppDefaults.shared

    var sensitivityInDouble: Binding<Double> {
        let low = 1.0 / 1200
        let high = 1.0 / 40

        return Binding<Double>(get: {
            (1 / (2000 - defaults.cursorSensitivity) - low) / (high - low)
        }, set: {
            let value = 1 / (low + (high - low) * $0)
            defaults.cursorSensitivity = 2000 - value
        })
    }

    let accelerationFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = NumberFormatter.Style.decimal
        formatter.roundingMode = NumberFormatter.RoundingMode.halfUp
        formatter.maximumFractionDigits = 4
        formatter.thousandSeparator = ""
        return formatter
    }()

    let sensitivityFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = NumberFormatter.Style.decimal
        formatter.roundingMode = NumberFormatter.RoundingMode.halfUp
        formatter.maximumFractionDigits = 2
        formatter.thousandSeparator = ""
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            Form {
                Slider(value: $defaults.cursorAcceleration,
                       in: 0.0...20.0) {
                    Text("Acceleration")
                }
                HStack {
                    Text("(0–20)")
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("",
                         value: $defaults.cursorAcceleration,
                         formatter: accelerationFormatter)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }

                Slider(value: sensitivityInDouble,
                       in: 0...1) {
                    Text("Sensitivity")
                }.padding(.top)
                HStack {
                    Text("(0–1)")
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("",
                              value: sensitivityInDouble,
                              formatter: sensitivityFormatter)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }
            .disabled(defaults.linearMovementOn)

            Spacer()

            Toggle(isOn: $defaults.linearMovementOn) {
                Text("Disable cursor acceleration & sensitivity")
            }

            Spacer()

            VStack(alignment: .leading) {
                if #available(macOS 11.0, *) {
                    Text("You may also press ⌃⇧⌘Z to revert to system defaults.")
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Revert to system defaults") {
                        revertSpeed()
                    }
                    .keyboardShortcut("z", modifiers: [.control, .command, .shift])
                    .disabled(defaults.linearMovementOn)
                } else {
                    Button("Revert to system defaults") {
                        revertSpeed()
                    }
                    .disabled(defaults.linearMovementOn)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 400)
    }

    private func revertSpeed() {
        DeviceManager.shared.restorePointerSpeedToInitialValue()
        defaults.cursorAcceleration = DeviceManager.shared.pointerAcceleration
        defaults.cursorSensitivity = DeviceManager.shared.pointerSensitivity
    }
}

struct CursorView_Previews: PreviewProvider {
    static var previews: some View {
        CursorView()
    }
}
