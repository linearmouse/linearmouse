// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Defaults
import SwiftUI

struct DevicePickerSheet: View {
    @Environment(\.isPresented) var isPresented
    @Default(.autoSelectActiveDevice) var autoSelectActiveDevice

    var body: some View {
        VStack(spacing: 10) {
            if !autoSelectActiveDevice {
                DevicePicker()
                    .frame(minHeight: 300)
            }

            Toggle("Auto select the active device", isOn: $autoSelectActiveDevice.animation())
                .padding()

            if autoSelectActiveDevice {
                Button("OK") {
                    isPresented?.wrappedValue.toggle()
                }
                .padding(.bottom)
            }
        }
    }
}

struct DevicePickerSheet_Previews: PreviewProvider {
    static var previews: some View {
        DevicePickerSheet()
    }
}
