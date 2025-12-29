// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct DetailView<T>: View where T: View {
    var schemeSpecific = true
    var content: () -> T

    @ObservedObject var schemeState = SchemeState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if schemeSpecific, !schemeState.isSchemeValid {
                Text("No device selected.")
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
            } else {
                content()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
