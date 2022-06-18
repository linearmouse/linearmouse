// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation
import SwiftUI

struct ModifierKeyActionPicker: View {
    @State var label: String

    @Binding var action: ModifierKeyAction

    private var speedFactor: Binding<Double> {
        Binding<Double>(get: {
            action.speedFactor
        }, set: {
            if $0 < 0 {
                action.speedFactor = $0.rounded()
            } else if 0 ..< 0.1 ~= $0 {
                action.speedFactor = ($0 * 20).rounded() / 20
            } else if 0.1 ..< 1 ~= $0 {
                action.speedFactor = ($0 * 10).rounded() / 10
            } else {
                action.speedFactor = ($0 * 2).rounded() / 2
            }
        })
    }

    var body: some View {
        Picker(label, selection: $action.type) {
            ForEach(ModifierKeyActionType.allCases, id: \.self) {
                Text(NSLocalizedString($0.rawValue, comment: "")).tag($0)
            }
        }

        if action.type == .changeSpeed {
            HStack {
                Text("to")
                Slider(value: speedFactor,
                       in: 0.05 ... 10.00)
                HStack(spacing: 5) {
                    Text(String(format: "%0.2f ×", action.speedFactor))
                }
                .frame(width: 60, alignment: .trailing)
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
