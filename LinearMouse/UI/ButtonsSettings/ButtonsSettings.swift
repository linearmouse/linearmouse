// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct ButtonsSettings: View {
    @ObservedObject var schemeState = SchemeState.shared

    var body: some View {
        DetailView {
            Form {
                Section {
                    Toggle(isOn: $schemeState.universalBackForward) {
                        withDescription {
                            Text("Enable universal back and forward")
                            Text(
                                "Convert the back and forward side buttons to swiping gestures to allow universal back and forward functionality."
                            )
                        }
                    }
                }
                .modifier(SectionViewModifier())
            }
            .modifier(FormViewModifier())
        }
    }
}
