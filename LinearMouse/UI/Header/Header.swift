// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct Header: View {
    var body: some View {
        HStack {
            DeviceIndicator()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 35, maxHeight: 35, alignment: .leading)
        .controlSize(.small)
    }
}

struct Header_Previews: PreviewProvider {
    static var previews: some View {
        Header()
    }
}
