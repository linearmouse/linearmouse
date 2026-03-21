// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import os.log

final class ReceiverMonitor {
    static let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "ReceiverMonitor")
    static let discoveryTimeout: TimeInterval = 3

    private let provider = LogitechHIDPPDeviceMetadataProvider()
    private var contexts = [Int: ReceiverContext]()

    var onPointingDevicesChanged: ((Int, [ReceiverLogicalDeviceIdentity]) -> Void)?
    func receiverIdentities(for device: Device) -> [ReceiverLogicalDeviceIdentity] {
        provider.receiverPointingDeviceIdentities(for: device.pointerDevice)
    }

    func startMonitoring(device: Device) {
        guard let locationID = device.pointerDevice.locationID else {
            return
        }

        guard contexts[locationID] == nil else {
            return
        }

        let context = ReceiverContext(device: device, locationID: locationID, provider: provider)
        context.onDiscoveryTimedOut = { [weak self] in
            self?.onPointingDevicesChanged?(locationID, [])
        }
        context.onSlotsChanged = { [weak self] identities in
            self?.onPointingDevicesChanged?(locationID, identities)
        }
        contexts[locationID] = context
        context.start()

        os_log("Started receiver monitor for %{public}@", log: Self.log, type: .info, String(describing: device))
    }

    func stopMonitoring(device: Device) {
        guard let locationID = device.pointerDevice.locationID,
              let context = contexts.removeValue(forKey: locationID)
        else {
            return
        }

        context.stop()
    }
}

private final class ReceiverContext {
    let device: Device
    private let locationID: Int
    private let provider: LogitechHIDPPDeviceMetadataProvider
    private var workerThread: Thread?
    private var isRunning = false
    private let stateLock = NSLock()
    private var discoveredAnySlot = false

    var onDiscoveryTimedOut: (() -> Void)?
    var onSlotsChanged: (([ReceiverLogicalDeviceIdentity]) -> Void)?
    init(device: Device, locationID: Int, provider: LogitechHIDPPDeviceMetadataProvider) {
        self.device = device
        self.locationID = locationID
        self.provider = provider
    }

    func start() {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !isRunning else {
            return
        }
        isRunning = true
        discoveredAnySlot = false

        let thread = Thread { [weak self] in
            self?.workerMain()
        }
        thread.name = "linearmouse.receiver-monitor.\(locationID)"
        workerThread = thread
        thread.start()
    }

    func stop() {
        stateLock.lock()
        isRunning = false
        stateLock.unlock()
        workerThread?.cancel()
        workerThread = nil
    }

    private func workerMain() {
        guard let channel = provider.receiverActivityChannel(for: locationID) else {
            DispatchQueue.main.async { [weak self] in
                self?.onDiscoveryTimedOut?()
            }
            return
        }

        channel.enableWirelessNotifications()
        let identities = channel.discoverPointingDeviceIdentities()
        if !identities.isEmpty {
            discoveredAnySlot = true
            let identitiesDescription = identities.map { identity in
                let battery = identity.batteryLevel.map(String.init) ?? "(nil)"
                return "slot=\(identity.slot) name=\(identity.name) battery=\(battery)"
            }
            .joined(separator: ", ")
            os_log(
                "Receiver logical discovery succeeded: locationID=%{public}u identities=%{public}@",
                log: ReceiverMonitor.log,
                type: .info,
                UInt32(locationID),
                identitiesDescription
            )
            DispatchQueue.main.async { [weak self] in
                self?.onSlotsChanged?(identities)
            }
        } else {
            let timeoutDeadline = Date().addingTimeInterval(ReceiverMonitor.discoveryTimeout)
            while shouldContinueRunning(), Date() < timeoutDeadline, !discoveredAnySlot {
                Thread.sleep(forTimeInterval: 0.05)
            }

            if !discoveredAnySlot {
                os_log(
                    "Receiver logical discovery timed out: locationID=%{public}u device=%{public}@",
                    log: ReceiverMonitor.log,
                    type: .info,
                    UInt32(locationID),
                    String(describing: device)
                )
                DispatchQueue.main.async { [weak self] in
                    self?.onDiscoveryTimedOut?()
                }
            }
        }
    }

    private func shouldContinueRunning() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isRunning
    }
}
