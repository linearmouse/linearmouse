//
//  CursorView.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/12/9.
//

import SwiftUI

struct CursorView: View {
    @ObservedObject var defaults = AppDefaults.shared
    let cursorManager = CursorManager.shared

    var sensitivityInDouble: Binding<Double> {
        Binding<Double>(get: {
            return Double(defaults.cursorSensitivity)
        }, set: {
            defaults.cursorSensitivity = Int($0)
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
        formatter.maximumFractionDigits = 0
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
                           in: 5...1990) {
                    Text("Sensitivity")
                }.padding(.top)
                HStack {
                    Text("(5–1990)")
                        .controlSize(.small)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("",
                              value: $defaults.cursorSensitivity,
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
                        cursorManager.revertToSystemDefaults()
                        defaults.cursorAcceleration = cursorManager.acceleration
                        defaults.cursorSensitivity = cursorManager.sensitivity
                    }
                    .keyboardShortcut("z", modifiers: [.control, .command, .shift])
                    .disabled(defaults.linearMovementOn)
                } else {
                    Button("Revert to system defaults") {
                        cursorManager.revertToSystemDefaults()
                        defaults.cursorAcceleration = cursorManager.acceleration
                        defaults.cursorSensitivity = cursorManager.sensitivity
                    }
                    .disabled(defaults.linearMovementOn)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 400)
    }
}

struct CursorView_Previews: PreviewProvider {
    static var previews: some View {
        CursorView()
    }
}
