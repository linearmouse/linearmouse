// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import Foundation
import LRUCache
import PointerKit

final class BatteryDeviceMonitor: NSObject, ObservableObject {
    static let shared = BatteryDeviceMonitor()

    @Published private(set) var devices: [ConnectedBatteryDeviceInfo] = []

    private static let pollingInterval: TimeInterval = 60
    private static let directLogitechBluetoothActiveRefreshInterval: TimeInterval = 30 * 60
    private static let directLogitechBluetoothFailedRefreshInterval: TimeInterval = 10
    private static let directLogitechBluetoothCacheLimit = 16

    private struct DirectLogitechBluetoothBatteryCacheEntry {
        var info: ConnectedBatteryDeviceInfo?
        var successfulRefreshDate: Date?
        var failedRefreshDate: Date?
        var isRefreshing = false
    }

    private let queue = DispatchQueue(label: "linearmouse.battery-monitor", qos: .utility)
    private let stateQueue = DispatchQueue(label: "linearmouse.battery-monitor.state", qos: .utility)
    private let timerQueue = DispatchQueue(label: "linearmouse.battery-monitor.timer", qos: .utility)

    private var timer: DispatchSourceTimer?
    private var isRunning = false
    private var isRefreshing = false
    private var needsRefresh = false
    private let directLogitechBluetoothCache = LRUCache<String, DirectLogitechBluetoothBatteryCacheEntry>(
        countLimit: directLogitechBluetoothCacheLimit
    )
    private var subscriptions = Set<AnyCancellable>()

    override init() {
        super.init()

        DeviceManager.shared
            .$devices
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshIfNeeded()
            }
            .store(in: &subscriptions)

        DeviceManager.shared
            .$receiverPairedDeviceIdentities
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshIfNeeded()
            }
            .store(in: &subscriptions)
    }

    func enable() {
        stateQueue.sync {
            guard !isRunning else {
                return
            }
            isRunning = true
            directLogitechBluetoothCache.removeAllValues()

            let timer = DispatchSource.makeTimerSource(queue: timerQueue)
            timer.schedule(deadline: .now(), repeating: Self.pollingInterval)
            timer.setEventHandler { [weak self] in
                self?.refreshIfNeeded()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func disable() {
        stateQueue.sync {
            directLogitechBluetoothCache.removeAllValues()
            guard isRunning else {
                return
            }

            isRunning = false
            needsRefresh = false
            timer?.setEventHandler {}
            timer?.cancel()
            timer = nil
        }
    }

    func currentDeviceBatteryLevel(for device: Device) -> Int? {
        let pairedDevices = DeviceManager.shared.pairedReceiverDevices(for: device)
        let directDeviceIdentity = Self.directIdentity(for: device)

        let inventoryLevel = ConnectedBatteryDeviceInfo.currentDeviceBatteryLevel(
            pairedDevices: pairedDevices,
            directDeviceIdentity: directDeviceIdentity,
            inventory: devices
        )
        if let inventoryLevel {
            return inventoryLevel
        }

        guard Self.isDirectLogitechBluetoothDevice(device) else {
            return nil
        }

        return cachedDirectLogitechBluetoothInfo(for: device)?.batteryLevel
    }

    func refreshDirectLogitechBluetoothBatteryIfNeeded(for device: Device) {
        guard Self.isDirectLogitechBluetoothDevice(device) else {
            return
        }

        guard shouldContinueRefreshing else {
            return
        }

        let now = Date()
        let cacheKey = Self.directLogitechBluetoothCacheKey(for: device)
        guard beginDirectLogitechBluetoothRefresh(cacheKey: cacheKey, now: now, active: true) else {
            return
        }

        queue.async { [weak self, weak device] in
            guard let self else {
                return
            }
            defer { self.finishDirectLogitechBluetoothRefresh(cacheKey: cacheKey) }

            guard let device,
                  self.shouldContinueRefreshing else {
                return
            }

            self.refreshDirectLogitechBluetoothDevice(device, cacheKey: cacheKey, now: now)
            self.refreshIfNeeded()
        }
    }

    private func refreshIfNeeded() {
        let shouldRefresh = stateQueue.sync { () -> Bool in
            guard isRunning, !isRefreshing else {
                if isRunning {
                    needsRefresh = true
                }
                return false
            }

            isRefreshing = true
            needsRefresh = false
            return true
        }
        guard shouldRefresh else {
            return
        }

        queue.async { [weak self] in
            guard let self else {
                return
            }

            guard self.shouldContinueRefreshing else {
                self.finishRefreshCycle()
                return
            }

            let receiverPairedBatteries = DeviceManager.shared.devices.flatMap { device in
                DeviceManager.shared
                    .pairedReceiverDevices(for: device)
                    .compactMap { identity -> ConnectedBatteryDeviceInfo? in
                        guard let batteryLevel = identity.batteryLevel else {
                            return nil
                        }

                        return ConnectedBatteryDeviceInfo(
                            id: ConnectedBatteryDeviceInfo.receiverIdentity(
                                receiverLocationID: identity.receiverLocationID,
                                slot: identity.slot
                            ),
                            name: identity.name,
                            batteryLevel: batteryLevel
                        )
                    }
            }
            let visibleDeviceBatteries = DeviceManager.shared
                .devices
                .compactMap { device -> ConnectedBatteryDeviceInfo? in
                    guard DeviceManager.shared.pairedReceiverDevices(for: device).isEmpty,
                          let batteryLevel = device.batteryLevel
                    else {
                        return nil
                    }

                    return ConnectedBatteryDeviceInfo(
                        id: ConnectedBatteryDeviceInfo.directIdentity(
                            vendorID: device.vendorID,
                            productID: device.productID,
                            serialNumber: device.serialNumber,
                            locationID: device.pointerDevice.locationID,
                            transport: device.pointerDevice.transport,
                            fallbackName: device.productName ?? device.name
                        ),
                        name: device.name,
                        batteryLevel: batteryLevel
                    )
                }
            let propertyBackedDevices = ConnectedBatteryDeviceInventory.devices()
            let directlyAddressableLogitechDevices = DeviceManager.shared.devices.filter {
                DeviceManager.shared.pairedReceiverDevices(for: $0).isEmpty
            }
            guard self.shouldContinueRefreshing else {
                self.finishRefreshCycle()
                return
            }

            let directLogitechBluetoothBatteries = self.cachedDirectLogitechBluetoothBatteries(
                for: directlyAddressableLogitechDevices
            )
            guard self.shouldContinueRefreshing else {
                self.finishRefreshCycle()
                return
            }

            let logitechDevices = ConnectedLogitechDeviceInventory
                .devices(
                    from: directlyAddressableLogitechDevices.map(\.pointerDevice)
                ) { [weak self] in self?.shouldContinueRefreshing == true }
            guard self.shouldContinueRefreshing else {
                self.finishRefreshCycle()
                return
            }

            DispatchQueue.main.async {
                guard self.shouldContinueRefreshing else {
                    return
                }

                self.devices = self.merge(
                    logitechDevices: receiverPairedBatteries
                        + visibleDeviceBatteries
                        + directLogitechBluetoothBatteries
                        + logitechDevices,
                    propertyBackedDevices: propertyBackedDevices
                )
            }

            self.finishRefreshCycle()
        }
    }

    private func cachedDirectLogitechBluetoothBatteries(for devices: [Device]) -> [ConnectedBatteryDeviceInfo] {
        let directBluetoothDevices = devices.filter {
            $0.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID
                && $0.pointerDevice.transport == PointerDeviceTransportName.bluetoothLowEnergy
        }

        refreshDirectLogitechBluetoothDevices(directBluetoothDevices, active: false)

        return directBluetoothDevices.compactMap { device in
            guard let cachedInfo = cachedDirectLogitechBluetoothInfo(for: device) else {
                return nil
            }

            return ConnectedBatteryDeviceInfo(
                id: Self.directIdentity(for: device),
                name: cachedInfo.name,
                batteryLevel: cachedInfo.batteryLevel
            )
        }
    }

    private func refreshDirectLogitechBluetoothDevices(
        _ devices: [Device],
        now: Date = Date(),
        active: Bool
    ) {
        for device in devices {
            let cacheKey = Self.directLogitechBluetoothCacheKey(for: device)
            guard beginDirectLogitechBluetoothRefresh(cacheKey: cacheKey, now: now, active: active) else {
                continue
            }

            refreshDirectLogitechBluetoothDevice(device, cacheKey: cacheKey, now: now)
            finishDirectLogitechBluetoothRefresh(cacheKey: cacheKey)
        }
    }

    private func beginDirectLogitechBluetoothRefresh(cacheKey: String, now: Date, active: Bool) -> Bool {
        stateQueue.sync {
            var entry = directLogitechBluetoothCache.value(forKey: cacheKey) ?? .init()
            guard shouldRefreshDirectLogitechBluetoothDevice(entry, now: now, active: active) else {
                return false
            }

            entry.isRefreshing = true
            directLogitechBluetoothCache.setValue(entry, forKey: cacheKey)
            return true
        }
    }

    private func finishDirectLogitechBluetoothRefresh(cacheKey: String) {
        stateQueue.sync {
            guard var entry = directLogitechBluetoothCache.value(forKey: cacheKey) else {
                return
            }

            entry.isRefreshing = false
            directLogitechBluetoothCache.setValue(entry, forKey: cacheKey)
        }
    }

    private func refreshDirectLogitechBluetoothDevice(
        _ device: Device,
        cacheKey: String,
        now: Date
    ) {
        guard let metadata = VendorSpecificDeviceMetadataRegistry.metadata(for: device.pointerDevice),
              let batteryLevel = metadata.batteryLevel
        else {
            recordDirectLogitechBluetoothRefreshFailure(cacheKey: cacheKey, now: now)
            return
        }

        let info = ConnectedBatteryDeviceInfo(
            id: Self.directIdentity(for: device),
            name: metadata.name ?? device.productName ?? device.name,
            batteryLevel: batteryLevel
        )
        recordDirectLogitechBluetoothRefreshSuccess(info, cacheKey: cacheKey, now: now)
    }

    private func recordDirectLogitechBluetoothRefreshFailure(cacheKey: String, now: Date) {
        stateQueue.sync {
            var entry = directLogitechBluetoothCache.value(forKey: cacheKey) ?? .init()
            entry.failedRefreshDate = now
            directLogitechBluetoothCache.setValue(entry, forKey: cacheKey)
        }
    }

    private func recordDirectLogitechBluetoothRefreshSuccess(
        _ info: ConnectedBatteryDeviceInfo,
        cacheKey: String,
        now: Date
    ) {
        stateQueue.sync {
            var entry = directLogitechBluetoothCache.value(forKey: cacheKey) ?? .init()
            entry.info = info
            entry.successfulRefreshDate = now
            entry.failedRefreshDate = nil
            directLogitechBluetoothCache.setValue(entry, forKey: cacheKey)
        }
    }

    private func shouldRefreshDirectLogitechBluetoothDevice(
        _ entry: DirectLogitechBluetoothBatteryCacheEntry,
        now: Date,
        active: Bool
    ) -> Bool {
        if entry.isRefreshing {
            return false
        }

        if let latestFailure = entry.failedRefreshDate,
           now.timeIntervalSince(latestFailure) < Self.directLogitechBluetoothFailedRefreshInterval {
            return false
        }

        guard active else {
            return entry.info == nil
        }

        guard entry.info != nil else {
            return true
        }

        guard let latestSuccess = entry.successfulRefreshDate else {
            return true
        }

        return now.timeIntervalSince(latestSuccess) >= Self.directLogitechBluetoothActiveRefreshInterval
    }

    private func cachedDirectLogitechBluetoothInfo(for device: Device) -> ConnectedBatteryDeviceInfo? {
        stateQueue.sync {
            directLogitechBluetoothCache.value(forKey: Self.directLogitechBluetoothCacheKey(for: device))?.info
        }
    }

    private static func isDirectLogitechBluetoothDevice(_ device: Device) -> Bool {
        device.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID
            && device.pointerDevice.transport == PointerDeviceTransportName.bluetoothLowEnergy
            && DeviceManager.shared.pairedReceiverDevices(for: device).isEmpty
    }

    private static func directIdentity(for device: Device) -> String {
        ConnectedBatteryDeviceInfo.directIdentity(
            vendorID: device.vendorID,
            productID: device.productID,
            serialNumber: device.serialNumber,
            locationID: device.pointerDevice.locationID,
            transport: device.pointerDevice.transport,
            fallbackName: device.productName ?? device.name
        )
    }

    private static func directLogitechBluetoothCacheKey(for device: Device) -> String {
        "logitech-ble|\(directIdentity(for: device))"
    }

    private var shouldContinueRefreshing: Bool {
        stateQueue.sync {
            isRunning
        }
    }

    private func finishRefreshCycle() {
        let shouldRefreshAgain = stateQueue.sync { () -> Bool in
            isRefreshing = false
            defer { needsRefresh = false }
            return needsRefresh
        }

        if shouldRefreshAgain {
            refreshIfNeeded()
        }
    }

    private func merge(
        logitechDevices: [ConnectedBatteryDeviceInfo],
        propertyBackedDevices: [ConnectedBatteryDeviceInfo]
    ) -> [ConnectedBatteryDeviceInfo] {
        var merged = [ConnectedBatteryDeviceInfo]()
        var seen = Set<String>()

        for device in logitechDevices + propertyBackedDevices {
            guard seen.insert(device.id).inserted else {
                continue
            }

            merged.append(device)
        }

        return merged.sorted {
            let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
            if byName == .orderedSame {
                return $0.batteryLevel > $1.batteryLevel
            }

            return byName == .orderedAscending
        }
    }
}
