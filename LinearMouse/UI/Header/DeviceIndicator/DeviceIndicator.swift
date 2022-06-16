// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

struct DeviceIndicator: View {
    @StateObject var model = DeviceIndicatorModel()

    var body: some View {
        Button(action: {}) {
            Text(model.activeDeviceName ?? "Unknown")
                .frame(maxWidth: 150)
                .fixedSize()
                .lineLimit(1)
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}

struct DeviceIndicator_Previews: PreviewProvider {
    static var previews: some View {
        DeviceIndicator()
    }
}
