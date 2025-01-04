// MIT License
// Copyright (c) 2021-2025 LinearMouse

import SwiftUI

struct SchemeIndicator: View {
    var body: some View {
        HStack {
            DeviceIndicator()
            AppIndicator()
            DisplayIndicator()
        }
        .padding(.horizontal, 10)
        .frame(height: 35, alignment: .leading)
    }
}
