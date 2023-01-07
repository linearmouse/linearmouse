// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Combine
import Defaults

class DevicePickerSectionState: ObservableObject {
    let deviceState = DeviceState.shared

    func setDevice(_ deviceModel: DeviceModel) {
        deviceState.currentDevice = deviceModel.device
    }
}
