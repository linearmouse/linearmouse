// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import SwiftUI

struct SchemeIndicator: View {
    var body: some View {
        HStack {
            DeviceIndicator()
            AppIndicator()
        }
        .padding(.horizontal, 10)
        .frame(height: 35, alignment: .leading)
    }
}
