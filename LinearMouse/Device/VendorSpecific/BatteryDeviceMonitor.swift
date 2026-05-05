// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import Foundation
import PointerKit

final class BatteryDeviceMonitor: NSObject, ObservableObject {
    static let shared = BatteryDeviceMonitor()

    @Published private(set) var devices: [ConnectedBatteryDeviceInfo] = []

    private static let pollingInterval: TimeInterval = 60
    private static let directLogitechBluetoothActiveRefreshInterval: TimeInterval = 30 * 60
    private static let directLogitechBluetoothFailedRefreshInterval: TimeInterval = 10

    private let queue = DispatchQueue(label: "linearmouse.battery-monitor", qos: .utility)
    private let timerQueue = DispatchQueue(label: "linearmouse.battery-monitor.timer", qos: .utility)

    private var timer: DispatchSourceTimer?
    private var isRunning = false
    private var isRefreshing = false
    private var needsRefresh = false
    // Preserve direct BLE Logitech battery data across sleep/wake. DeviceManager may briefly
    // report no BLE device while macOS rebuilds HID services after wake.
    private var directLogitechBluetoothCache = [String: ConnectedBatteryDeviceInfo]()
    private var directLogitechBluetoothSuccessfulRefreshDates = [String: Date]()
    private var directLogitechBluetoothFailedRefreshDates = [String: Date]()
    private var directLogitechBluetoothRefreshesInFlight = Set<String>()
    private let directLogitechBluetoothLock = NSLock()
    private let stateLock = NSLock()
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

    func start() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !isRunning else {
            return
        }
        isRunning = true

        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: Self.pollingInterval)
        timer.setEventHandler { [weak self] in
            self?.refreshIfNeeded()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard isRunning else {
            return
        }

        isRunning = false
        needsRefresh = false
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
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

        queue.async { [weak self, weak device] in
            guard let self,
                  let device,
                  self.shouldContinueRefreshing else {
                return
            }

            let now = Date()
            guard self.shouldRefreshDirectLogitechBluetoothDevice(device, now: now, active: true) else {
                return
            }

            self.refreshDirectLogitechBluetoothDevices([device], now: now)
            self.refreshIfNeeded()
        }
    }

    private func refreshIfNeeded() {
        stateLock.lock()
        guard isRunning, !isRefreshing else {
            if isRunning {
                needsRefresh = true
            }
            stateLock.unlock()
            return
        }
        isRefreshing = true
        needsRefresh = false
        stateLock.unlock()

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

        let uncachedDevices = directBluetoothDevices.filter {
            cachedDirectLogitechBluetoothInfo(for: $0) == nil
                && shouldRefreshDirectLogitechBluetoothDevice($0, active: false)
        }
        if !uncachedDevices.isEmpty {
            refreshDirectLogitechBluetoothDevices(uncachedDevices)
        }

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

    private func refreshDirectLogitechBluetoothDevices(_ devices: [Device], now: Date = Date()) {
        let devicesToRefresh = devices.filter {
            let keys = Self.directLogitechBluetoothCacheKeys(for: $0)
            directLogitechBluetoothLock.lock()
            defer { directLogitechBluetoothLock.unlock() }
            return !keys.contains { directLogitechBluetoothRefreshesInFlight.contains($0) }
        }
        guard !devicesToRefresh.isEmpty else {
            return
        }

        let cacheKeys = devicesToRefresh.flatMap(Self.directLogitechBluetoothCacheKeys(for:))
        directLogitechBluetoothLock.lock()
        directLogitechBluetoothRefreshesInFlight.formUnion(cacheKeys)
        directLogitechBluetoothLock.unlock()
        defer {
            directLogitechBluetoothLock.lock()
            directLogitechBluetoothRefreshesInFlight.subtract(cacheKeys)
            directLogitechBluetoothLock.unlock()
        }

        for device in devicesToRefresh {
            let keys = Self.directLogitechBluetoothCacheKeys(for: device)
            guard let metadata = VendorSpecificDeviceMetadataRegistry.metadata(for: device.pointerDevice),
                  let batteryLevel = metadata.batteryLevel
            else {
                directLogitechBluetoothLock.lock()
                for key in keys {
                    directLogitechBluetoothFailedRefreshDates[key] = now
                }
                directLogitechBluetoothLock.unlock()
                continue
            }

            let info = ConnectedBatteryDeviceInfo(
                id: Self.directIdentity(for: device),
                name: metadata.name ?? device.productName ?? device.name,
                batteryLevel: batteryLevel
            )
            directLogitechBluetoothLock.lock()
            for key in keys {
                directLogitechBluetoothCache[key] = info
                directLogitechBluetoothSuccessfulRefreshDates[key] = now
                directLogitechBluetoothFailedRefreshDates.removeValue(forKey: key)
            }
            directLogitechBluetoothLock.unlock()
        }
    }

    private func shouldRefreshDirectLogitechBluetoothDevice(
        _ device: Device,
        now: Date = Date(),
        active: Bool
    ) -> Bool {
        let keys = Self.directLogitechBluetoothCacheKeys(for: device)
        directLogitechBluetoothLock.lock()
        defer { directLogitechBluetoothLock.unlock() }

        if keys.contains(where: { directLogitechBluetoothRefreshesInFlight.contains($0) }) {
            return false
        }

        if let latestFailure = keys.compactMap({ directLogitechBluetoothFailedRefreshDates[$0] }).max(),
           now.timeIntervalSince(latestFailure) < Self.directLogitechBluetoothFailedRefreshInterval {
            return false
        }

        guard active else {
            return !keys.contains { directLogitechBluetoothCache[$0] != nil }
        }

        guard keys.contains(where: { directLogitechBluetoothCache[$0] != nil }) else {
            return true
        }

        guard let latestSuccess = keys.compactMap({ directLogitechBluetoothSuccessfulRefreshDates[$0] }).max() else {
            return true
        }

        return now.timeIntervalSince(latestSuccess) >= Self.directLogitechBluetoothActiveRefreshInterval
    }

    private func cachedDirectLogitechBluetoothInfo(for device: Device) -> ConnectedBatteryDeviceInfo? {
        directLogitechBluetoothLock.lock()
        defer { directLogitechBluetoothLock.unlock() }

        return Self.directLogitechBluetoothCacheKeys(for: device)
            .lazy
            .compactMap { self.directLogitechBluetoothCache[$0] }
            .first
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

    private static func directLogitechBluetoothCacheKeys(for device: Device) -> [String] {
        let vendorID = device.vendorID ?? 0
        let productID = device.productID ?? 0
        var keys = [String]()

        if let serialNumber = device.serialNumber, !serialNumber.isEmpty {
            keys.append("logitech-ble|serial|\(vendorID)|\(productID)|\(serialNumber.uppercased())")
        }

        let name = (device.productName ?? device.name)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            keys.append("logitech-ble|name|\(vendorID)|\(productID)|\(name)")
        }

        if let locationID = device.pointerDevice.locationID {
            keys.append("logitech-ble|location|\(vendorID)|\(productID)|\(locationID)")
        }

        if keys.isEmpty {
            keys.append("logitech-ble|identity|\(directIdentity(for: device))")
        }

        return NSOrderedSet(array: keys).compactMap { $0 as? String }
    }

    private var shouldContinueRefreshing: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isRunning
    }

    private func finishRefreshCycle() {
        stateLock.lock()
        isRefreshing = false
        let shouldRefreshAgain = needsRefresh
        needsRefresh = false
        stateLock.unlock()

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
