//
//  DevicePickerSheet.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/6/17.
//

import SwiftUI
import Defaults

struct DevicePickerSheet: View {
    @Environment(\.isPresented) var isPresented
    @StateObject var model = DevicePickerSheetModel()
    @Default(.shouldSwitchToActiveDevice) var shouldSwitchToActiveDevice

    var body: some View {
        VStack(spacing: 10) {
            if !shouldSwitchToActiveDevice {
                DevicePicker()
                    .frame(minHeight: 300)
            }

            Toggle("Switch to the active device automatically", isOn: $shouldSwitchToActiveDevice.animation())
                .padding()

            if shouldSwitchToActiveDevice {
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
