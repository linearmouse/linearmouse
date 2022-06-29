// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct DetailView<T>: View where T: View {
    var showHeader = true
    var content: () -> T

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showHeader {
                Header()
            }

            if #available(macOS 11.0, *) {
                ScrollView {
                    content()
                        .padding(.horizontal, 40)
                        .padding(.vertical, 30)
                }
                .frame(minWidth: 500, alignment: .topLeading)
            } else {
                // HACK: maxWidth: .inifinity will cause crashes on Catalina?
                ScrollView {
                    content()
                        .padding(.horizontal, 40)
                        .padding(.vertical, 30)
                }
                .frame(minWidth: 500, maxWidth: 10000, alignment: .topLeading)
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
