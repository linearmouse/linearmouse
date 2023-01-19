// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct DetailView<T>: View where T: View {
    var schemeSpecific = true
    var content: () -> T

    @ObservedObject var schemeState = SchemeState.shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            if schemeSpecific, !schemeState.isSchemeValid {
                Text("No device selected.")
                    .frame(maxWidth: .infinity,
                           maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    // FIXME: Workaround for Catalina
                    if #unavailable(macOS 11) {
                        Text("")
                            .padding(.top)
                    }

                    content()
                        .padding(.horizontal, 40)
                        .padding(.vertical, 30)
                        .frame(
                            minWidth: 0,
                            maxWidth: .infinity,
                            alignment: .topLeading
                        )
                }
            }

            if schemeSpecific {
                SchemeIndicator()
                    .edgesIgnoringSafeArea(.top)
            }
        }
    }
}
