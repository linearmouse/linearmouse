//
//  ModifierKeysView.swift
//  LinearMouse
//
//  Created by lujjjh on 2021/7/30.
//

import SwiftUI

struct ModifierKeysView: View {
    @ObservedObject var defaults = AppDefaults.shared

    var body: some View {
        Form {
            ModifierKeyActionPicker(label: "⌘ (Command)", action: $defaults.modifiersCommandAction)

            ModifierKeyActionPicker(label: "⇧ (Shift)", action: $defaults.modifiersShiftAction)

            ModifierKeyActionPicker(label: "⌥ (Option)", action: $defaults.modifiersAlternateAction)

            ModifierKeyActionPicker(label: "⌃ (Control)", action: $defaults.modifiersControlAction)
        }
        .frame(minWidth: 0, maxWidth: .infinity,
               minHeight: 0, maxHeight: .infinity,
               alignment: .topLeading)
    }
}

struct ModifierKeysView_Previews: PreviewProvider {
    static var previews: some View {
        ModifierKeysView()
    }
}
