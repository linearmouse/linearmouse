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

            ScrollView {
                content()
                    .padding(.horizontal, 40)
                    .padding(.vertical, 30)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
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
