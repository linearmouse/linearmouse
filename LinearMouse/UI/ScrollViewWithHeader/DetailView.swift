// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct DetailView<T>: View where T: View {
    var content: () -> T

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                content()
                    .padding(40)
            }

            Header()
        }
    }
}

struct ScrollViewWithHeader_Previews: PreviewProvider {
    static var previews: some View {
        DetailView {
            Text("DetailView")
        }
    }
}
