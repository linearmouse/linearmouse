// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Defaults
import SwiftUI

struct DevicePickerSheet: View {
    @Environment(\.isPresented) var isPresented
    @Default(.autoSwitchToActiveDevice) var autoSwitchToActiveDevice

    var body: some View {
        VStack(spacing: 10) {
            if !autoSwitchToActiveDevice {
                DevicePicker()
                    .frame(minHeight: 300)
            }

            Toggle("Auto switch to the active device", isOn: $autoSwitchToActiveDevice.animation())
                .padding()

            if autoSwitchToActiveDevice {
                HStack {
                    Spacer()

                    Button("OK") {
                        isPresented?.wrappedValue.toggle()
                    }
                    .padding([.bottom, .horizontal])
                    .controlSize(.regular)
                    .asDefaultAction()
                }
            }
        }
    }
}

struct DevicePickerSheet_Previews: PreviewProvider {
    static var previews: some View {
        DevicePickerSheet()
    }
}
