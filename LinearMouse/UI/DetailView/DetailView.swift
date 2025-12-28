// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct DetailView<T>: View where T: View {
    var schemeSpecific = true
    var content: () -> T

    @ObservedObject var schemeState = SchemeState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if schemeSpecific {
                SchemeIndicator()
            }

            if schemeSpecific, !schemeState.isSchemeValid {
                Text("No device selected.")
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
            } else {
                // FIXME: Workaround for Catalina
                if #unavailable(macOS 11) {
                    Text(verbatim: "")
                        .padding(.top)
                }

                content()
            }
        }
        .edgesIgnoringSafeArea(.top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
