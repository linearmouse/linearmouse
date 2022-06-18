//
//  DevicePickerSectionModel.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/6/18.
//

import Combine
import Defaults

class DevicePickerSectionModel: ObservableObject {
    let deviceState = DeviceState.shared

    func setDevice(_ deviceModel: DeviceModel) {
        deviceState.currentDevice = deviceModel.device
    }
}
