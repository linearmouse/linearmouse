// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import Foundation

final class BatteryDeviceMonitor: NSObject, ObservableObject {
    static let shared = BatteryDeviceMonitor()

    @Published private(set) var devices: [ConnectedBatteryDeviceInfo] = []

    private static let pollingInterval: TimeInterval = 60

    private let queue = DispatchQueue(label: "linearmouse.battery-monitor", qos: .utility)
    private let timerQueue = DispatchQueue(label: "linearmouse.battery-monitor.timer", qos: .utility)

    private var timer: DispatchSourceTimer?
    private var isRunning = false
    private var isRefreshing = false
    private let stateLock = NSLock()
    private var subscriptions = Set<AnyCancellable>()

    override init() {
        super.init()

        DeviceManager.shared
            .$devices
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] devices in
                guard !devices.isEmpty else {
                    return
                }

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
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    private func refreshIfNeeded() {
        stateLock.lock()
        guard isRunning, !isRefreshing else {
            stateLock.unlock()
            return
        }
        isRefreshing = true
        stateLock.unlock()

        queue.async { [weak self] in
            guard let self else {
                return
            }

            let propertyBackedDevices = ConnectedBatteryDeviceInventory.devices()
            let logitechDevices = ConnectedLogitechDeviceInventory
                .devices(from: DeviceManager.shared.devices.map(\.pointerDevice))
            let devices = merge(logitechDevices: logitechDevices, propertyBackedDevices: propertyBackedDevices)
            print(
                "Battery monitor refresh:",
                "pointerDevices=\(DeviceManager.shared.devices.count)",
                "logitechDevices=\(logitechDevices.map { "\($0.name):\($0.batteryLevel)" })",
                "propertyDevices=\(propertyBackedDevices.map { "\($0.name):\($0.batteryLevel)" })"
            )
            DispatchQueue.main.async {
                self.devices = devices
            }

            self.stateLock.lock()
            self.isRefreshing = false
            self.stateLock.unlock()
        }
    }

    private func merge(
        logitechDevices: [ConnectedBatteryDeviceInfo],
        propertyBackedDevices: [ConnectedBatteryDeviceInfo]
    ) -> [ConnectedBatteryDeviceInfo] {
        var merged = [ConnectedBatteryDeviceInfo]()
        var seen = Set<String>()

        for device in logitechDevices + propertyBackedDevices {
            let key = "\(device.name)|\(device.batteryLevel)"
            guard seen.insert(key).inserted else {
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
