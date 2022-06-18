// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct ButtonsSettings: View {
    @ObservedObject var defaults = AppDefaults.shared

    var body: some View {
        DetailView {
            Toggle(isOn: $defaults.universalBackForwardOn) {
                VStack(alignment: .leading) {
                    Text("Enable universal back and forward")
                    Text("""
                    Convert the back and forward side buttons to \
                    swiping gestures to allow universal back and \
                    forward functionality.
                    """)
                    .controlSize(.small)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct ButtonsSettings_Previews: PreviewProvider {
    static var previews: some View {
        ButtonsSettings()
    }
}
