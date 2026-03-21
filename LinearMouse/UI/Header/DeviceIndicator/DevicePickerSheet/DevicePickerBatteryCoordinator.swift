// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import Foundation

final class DevicePickerBatteryCoordinator {
    static let shared = DevicePickerBatteryCoordinator()

    private let queue = DispatchQueue(label: "linearmouse.device-picker-battery", qos: .utility)
    private var activeRefreshes = Set<Int32>()
    private let lock = NSLock()

    func refresh(_ deviceModel: DeviceModel) {
        guard let device = deviceModel.deviceRef.value,
              !device.isLogicalDevice,
              device.pointerDevice.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID,
              device.pointerDevice.transport == "Bluetooth Low Energy" else {
            return
        }

        let deviceID = device.id
        lock.lock()
        guard activeRefreshes.insert(deviceID).inserted else {
            lock.unlock()
            return
        }
        lock.unlock()

        let pointerDevice = device.pointerDevice
        queue.async { [weak self, weak deviceModel] in
            let metadata = VendorSpecificDeviceMetadataRegistry.metadata(for: pointerDevice)
            DispatchQueue.main.async {
                deviceModel?.applyVendorSpecificMetadata(metadata)
                self?.lock.lock()
                self?.activeRefreshes.remove(deviceID)
                self?.lock.unlock()
            }
        }
    }
}
