// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct Header: View {
    var body: some View {
        HStack {
            DeviceIndicator()
        }
        .edgesIgnoringSafeArea(.top)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct Header_Previews: PreviewProvider {
    static var previews: some View {
        Header()
    }
}
