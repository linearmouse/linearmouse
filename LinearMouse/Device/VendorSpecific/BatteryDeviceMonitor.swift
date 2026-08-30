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
    private static let hidppRefreshTimeout: TimeInterval = 1

    private struct DirectLogitechBluetoothBatteryCacheEntry {
        var info: ConnectedBatteryDeviceInfo?
        var successfulRefreshDate: Date?
        var failedRefreshDate: Date?
    }

    private let queue = DispatchQueue(label: "linearmouse.battery-monitor", qos: .utility)
    private let stateQueue = DispatchQueue(label: "linearmouse.battery-monitor.state", qos: .utility)
    private let timerQueue = DispatchQueue(label: "linearmouse.battery-monitor.timer", qos: .utility)

    private var timer: DispatchSourceTimer?
    private var isRunning = false
    private var isRefreshing = false
    private var needsRefresh = false
    private var refreshAuthorization = CancellationSource()
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
        let previousAuthorization = stateQueue.sync { () -> CancellationSource? in
            guard !isRunning else {
                return nil
            }
            let previousAuthorization = refreshAuthorization
            refreshAuthorization = CancellationSource()
            isRunning = true
            isRefreshing = false
            directLogitechBluetoothCache.removeAllValues()

            let timer = DispatchSource.makeTimerSource(queue: timerQueue)
            timer.schedule(deadline: .now(), repeating: Self.pollingInterval)
            timer.setEventHandler { [weak self] in
                self?.refreshIfNeeded()
            }
            self.timer = timer
            timer.resume()
            return previousAuthorization
        }
        previousAuthorization?.cancel()
    }

    func disable() {
        let authorization = stateQueue.sync { () -> CancellationSource? in
            directLogitechBluetoothCache.removeAllValues()
            guard isRunning else {
                return nil
            }

            isRunning = false
            isRefreshing = false
            needsRefresh = false
            timer?.setEventHandler {}
            timer?.cancel()
            timer = nil
            return refreshAuthorization
        }
        authorization?.cancel()
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

        guard Self.isDirectLogitechBluetoothDevice(device, pairedDevices: pairedDevices) else {
            return nil
        }

        return cachedDirectLogitechBluetoothInfo(for: device)?.batteryLevel
    }

    func refreshDirectLogitechBluetoothBatteryIfNeeded(for device: Device) {
        let pairedDevices = DeviceManager.shared.pairedReceiverDevices(for: device)
        guard Self.isDirectLogitechBluetoothDevice(device, pairedDevices: pairedDevices) else {
            return
        }

        let cacheKey = Self.directLogitechBluetoothCacheKey(for: device)
        guard let authorization = currentRefreshAuthorization else {
            return
        }

        queue.async { [weak self, weak device] in
            guard let self else {
                return
            }

            guard let device,
                  self.isRefreshAuthorized(authorization) else {
                return
            }

            self.refreshDirectLogitechBluetoothDevice(
                device,
                cacheKey: cacheKey,
                now: Date(),
                active: true,
                authorization: authorization
            )
            self.refreshIfNeeded()
        }
    }

    private func refreshIfNeeded() {
        let authorization = stateQueue.sync { () -> CancellationToken? in
            guard isRunning, !isRefreshing else {
                if isRunning {
                    needsRefresh = true
                }
                return nil
            }

            isRefreshing = true
            needsRefresh = false
            return refreshAuthorization.token
        }
        guard let authorization else {
            return
        }

        queue.async { [weak self] in
            guard let self else {
                return
            }

            guard self.isRefreshAuthorized(authorization) else {
                self.finishRefreshCycle(authorization: authorization)
                return
            }

            let deviceInfos = self.deviceBatteryMonitoringInfos()
            let receiverPairedBatteries = deviceInfos.flatMap { _, pairedDevices in
                pairedDevices.compactMap { identity -> ConnectedBatteryDeviceInfo? in
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
            let visibleDeviceBatteries = deviceInfos
                .compactMap { device, pairedDevices -> ConnectedBatteryDeviceInfo? in
                    guard pairedDevices.isEmpty,
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
            let directlyAddressableLogitechDevices = deviceInfos.compactMap { device, pairedDevices in
                pairedDevices.isEmpty ? device : nil
            }
            guard self.isRefreshAuthorized(authorization) else {
                self.finishRefreshCycle(authorization: authorization)
                return
            }

            let directLogitechBluetoothBatteries = self.cachedDirectLogitechBluetoothBatteries(
                for: directlyAddressableLogitechDevices,
                authorization: authorization
            )
            guard self.isRefreshAuthorized(authorization) else {
                self.finishRefreshCycle(authorization: authorization)
                return
            }

            let metadataDeadline = Date().addingTimeInterval(Self.hidppRefreshTimeout)
            let logitechDevices = ConnectedLogitechDeviceInventory
                .devices(
                    from: directlyAddressableLogitechDevices.map(\.pointerDevice),
                    deadline: metadataDeadline
                ) { [weak self] in self?.isRefreshAuthorized(authorization) == true }
            guard self.isRefreshAuthorized(authorization) else {
                self.finishRefreshCycle(authorization: authorization)
                return
            }

            DispatchQueue.main.async {
                guard self.isRefreshAuthorized(authorization) else {
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

            self.finishRefreshCycle(authorization: authorization)
        }
    }

    private func deviceBatteryMonitoringInfos() -> [(device: Device, pairedDevices: [ReceiverLogicalDeviceIdentity])] {
        DispatchQueue.main.sync {
            DeviceManager.shared.devices.map { device in
                (device, DeviceManager.shared.pairedReceiverDevices(for: device))
            }
        }
    }

    private func cachedDirectLogitechBluetoothBatteries(
        for devices: [Device],
        authorization: CancellationToken
    ) -> [ConnectedBatteryDeviceInfo] {
        let directBluetoothDevices = devices.filter {
            $0.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID
                && $0.pointerDevice.transport == PointerDeviceTransportName.bluetoothLowEnergy
        }

        refreshDirectLogitechBluetoothDevices(
            directBluetoothDevices,
            active: false,
            authorization: authorization
        )

        return stateQueue.sync {
            directBluetoothDevices.compactMap { device in
                let cacheKey = Self.directLogitechBluetoothCacheKey(for: device)
                guard let cachedInfo = directLogitechBluetoothCache.value(forKey: cacheKey)?.info else {
                    return nil
                }

                return ConnectedBatteryDeviceInfo(
                    id: Self.directIdentity(for: device),
                    name: cachedInfo.name,
                    batteryLevel: cachedInfo.batteryLevel
                )
            }
        }
    }

    private func refreshDirectLogitechBluetoothDevices(
        _ devices: [Device],
        now: Date = Date(),
        active: Bool,
        authorization: CancellationToken
    ) {
        for device in devices {
            let cacheKey = Self.directLogitechBluetoothCacheKey(for: device)
            refreshDirectLogitechBluetoothDevice(
                device,
                cacheKey: cacheKey,
                now: now,
                active: active,
                authorization: authorization
            )
        }
    }

    private func refreshDirectLogitechBluetoothDevice(
        _ device: Device,
        cacheKey: String,
        now: Date,
        active: Bool,
        authorization: CancellationToken
    ) {
        let shouldRefresh = stateQueue.sync { () -> Bool in
            guard isRunning,
                  refreshAuthorization.token == authorization,
                  authorization.shouldContinue else {
                return false
            }
            let entry = directLogitechBluetoothCache.value(forKey: cacheKey) ?? .init()
            return shouldRefreshDirectLogitechBluetoothDevice(entry, now: now, active: active)
        }
        guard shouldRefresh else {
            return
        }

        let deadline = Date().addingTimeInterval(Self.hidppRefreshTimeout)
        let metadata = VendorSpecificDeviceMetadataRegistry.metadata(
            for: device.pointerDevice,
            deadline: deadline
        ) { [weak self] in
            self?.isRefreshAuthorized(authorization) == true
        }
        guard let metadata,
              let batteryLevel = metadata.batteryLevel else {
            stateQueue.sync {
                guard isRunning,
                      refreshAuthorization.token == authorization,
                      authorization.shouldContinue else {
                    return
                }
                var entry = directLogitechBluetoothCache.value(forKey: cacheKey) ?? .init()
                entry.failedRefreshDate = now
                directLogitechBluetoothCache.setValue(entry, forKey: cacheKey)
            }
            return
        }

        let info = ConnectedBatteryDeviceInfo(
            id: Self.directIdentity(for: device),
            name: metadata.name ?? device.productName ?? device.name,
            batteryLevel: batteryLevel
        )
        stateQueue.sync {
            guard isRunning,
                  refreshAuthorization.token == authorization,
                  authorization.shouldContinue else {
                return
            }
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

    private static func isDirectLogitechBluetoothDevice(
        _ device: Device,
        pairedDevices: [ReceiverLogicalDeviceIdentity]
    ) -> Bool {
        device.vendorID == LogitechHIDPPDeviceMetadataProvider.Constants.vendorID
            && device.pointerDevice.transport == PointerDeviceTransportName.bluetoothLowEnergy
            && pairedDevices.isEmpty
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

    private func isRefreshAuthorized(_ authorization: CancellationToken) -> Bool {
        stateQueue.sync {
            isRunning
                && refreshAuthorization.token == authorization
                && authorization.shouldContinue
        }
    }

    private var currentRefreshAuthorization: CancellationToken? {
        stateQueue.sync {
            let authorization = refreshAuthorization.token
            guard isRunning, authorization.shouldContinue else {
                return nil
            }
            return authorization
        }
    }

    private func finishRefreshCycle(authorization: CancellationToken) {
        let shouldRefreshAgain = stateQueue.sync { () -> Bool in
            guard refreshAuthorization.token == authorization else {
                return false
            }
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
