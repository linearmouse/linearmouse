// MIT License
// Copyright (c) 2021-2023 LinearMouse

import Defaults
import SwiftUI

struct DevicePickerSheet: View {
    @Binding var isPresented: Bool
    @Default(.autoSwitchToActiveDevice) var autoSwitchToActiveDevice

    var body: some View {
        VStack(spacing: 10) {
            if !autoSwitchToActiveDevice {
                DevicePicker(isPresented: $isPresented)
                    .frame(minHeight: 300)
            }

            Toggle("Auto switch to the active device", isOn: $autoSwitchToActiveDevice.animation())
                .padding()

            if autoSwitchToActiveDevice {
                HStack {
                    Spacer()

                    Button("OK") {
                        isPresented = false
                    }
                    .padding([.bottom, .horizontal])
                    .controlSize(.regular)
                    .asDefaultAction()
                }
            }
        }
    }
}
