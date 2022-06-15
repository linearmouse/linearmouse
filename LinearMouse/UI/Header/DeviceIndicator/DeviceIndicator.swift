// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct DeviceIndicator: View {
    @StateObject var model = DeviceIndicatorModel()

    var body: some View {
        HStack {
            Button(model.activeDeviceName) {}
                .buttonStyle(SecondaryButtonStyle())
                .lineLimit(1)
                .frame(maxWidth: 150, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: 35)
        .controlSize(.small)
    }
}

struct DeviceIndicator_Previews: PreviewProvider {
    static var previews: some View {
        DeviceIndicator()
    }
}
