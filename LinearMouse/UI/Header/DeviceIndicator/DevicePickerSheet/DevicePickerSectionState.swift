// MIT License
// Copyright (c) 2021-2023 LinearMouse

import Combine
import Defaults

class DevicePickerSectionState: ObservableObject {
    static let shared = DevicePickerSectionState()

    let deviceState = DeviceState.shared

    func setDevice(_ deviceModel: DeviceModel) {
        deviceState.currentDeviceRef = deviceModel.deviceRef
    }
}
