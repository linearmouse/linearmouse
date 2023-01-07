// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation
import SwiftUI

struct ModifierKeyActionPicker: View {
    @State var label: String

    @Binding var action: Scheme.Scrolling.Modifiers.Action?

    var body: some View {
        Picker(label, selection: actionType) {
            ForEach(ActionType.allCases) { type in
                Text(NSLocalizedString(type.rawValue, comment: "")).tag(type)
            }
        }

        if actionType.wrappedValue == .changeSpeed {
            HStack {
                Text("to")
                Slider(value: self.speedFactor,
                       in: 0.05 ... 10.00)
                HStack(spacing: 5) {
                    Text(String(format: "%0.2f ×", self.speedFactor.wrappedValue))
                }
                .frame(width: 60, alignment: .trailing)
            }
            .padding(.bottom, 20)
        }
    }
}
