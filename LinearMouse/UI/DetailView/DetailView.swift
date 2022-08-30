// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct DetailView<T>: View where T: View {
    var schemeSpecific = true
    var content: () -> T

    @StateObject var schemeState = SchemeState()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if schemeSpecific {
                SchemeIndicator()
            }

            if schemeSpecific, !schemeState.isSchemeValid {
                Text("No device selected.")
                    .frame(maxWidth: .infinity,
                           maxHeight: .infinity)
            } else {
                ScrollView {
                    content()
                        .padding(.horizontal, 40)
                        .padding(.vertical, 30)
                        .frame(
                            minWidth: 500,
                            maxWidth: 850,
                            alignment: .topLeading
                        )
                }
            }
        }
        .edgesIgnoringSafeArea(.top)
    }
}

struct ScrollViewWithHeader_Previews: PreviewProvider {
    static var previews: some View {
        DetailView {
            Text("DetailView")
        }
    }
}
