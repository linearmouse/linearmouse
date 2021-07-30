//
//  ModifierKeyActionPicker.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/7/29.
//

import Foundation
import SwiftUI

struct ModifierKeyActionPicker: View {
    @State var label: String

    @Binding var action: ModifierKeyAction

    var body: some View {
        Picker(label, selection: $action.type) {
            ForEach(ModifierKeyActionType.allCases, id: \.self) {
                Text(NSLocalizedString($0.rawValue, comment: "")).tag($0)
            }
        }

        if action.type == .changeSpeed {
            HStack {
                Text("to")
                Slider(value: $action.speedFactor,
                    in: 0.1...5.0,
                    step: 0.1)
                Text(String(format: "%.1f×", action.speedFactor))
            }
            .padding(.bottom, 20)
        }
    }
}

struct ModifierKeyActionPicker_Previews: PreviewProvider {
    static var previews: some View {
        ModifierKeyActionPicker(label: "shift", action: .constant(.init(type: .noAction, speedFactor: 1.0)))
    }
}
