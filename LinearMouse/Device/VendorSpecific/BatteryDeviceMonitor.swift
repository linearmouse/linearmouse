// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Combine
import Foundation
import HIDPP
import ObservationToken
import PointerKit

/// Lifecycle and published state belong to the main thread. Only initial HID++
/// reads and system-property enumeration run on the worker queue.
final class BatteryDeviceMonitor: NSObject, ObservableObject {
    static let shared = BatteryDeviceMonitor()
    @Published private(set) var devices: [ConnectedBatteryDeviceInfo] = []

    private struct Source: Equatable {
        let deviceID: Int32
        var channelID: ObjectIdentifier?
        var serialNumber: String?
        var productID: Int?
    }

    private struct Connection {
        let source: Source
        let generation: UUID
        let name: String
        let observer: HIDPPBatteryObservation
        let token: ObservationToken
        var sequence: UInt64 = 0
        var info: ConnectedBatteryDeviceInfo?
    }

    private let queue = DispatchQueue(label: "linearmouse.battery-monitor", qos: .utility)
    private var connections = [String: Connection]()
    private var propertyDevices = [ConnectedBatteryDeviceInfo]()
    private var fallbackDevices = [ConnectedBatteryDeviceInfo]()
    private var gattDevices = [ConnectedBatteryDeviceInfo]()
    private var gattTargetNames = [String: String]()
    private lazy var gatt = GATTBatteryMonitor { [weak self] values in
        guard let self, self.isRunning else {
            return
        }
        self.gattDevices = values.compactMap { value in
            guard let name = self.gattTargetNames[value.targetID] else {
                return nil
            }
            return ConnectedBatteryDeviceInfo(id: value.targetID, name: name, batteryLevel: value.level)
        }
        self.publish()
    }

    private var subscriptions = Set<AnyCancellable>()
    private var authorization = CancellationSource()
    private var timer: DispatchSourceTimer?
    private var isRunning = false
    private var propertyRefreshInFlight = false

    override init() {
        super.init()
        DeviceManager.shared
            .$devices
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        DeviceManager.shared
            .$receiverPairedDeviceIdentities
            .receive(on: RunLoop.main)
            .sink { [weak self] identities in
                guard let self else {
                    return
                }
                let present = Set(identities.values.flatMap(\.self).map {
                    ConnectedBatteryDeviceInfo.receiverIdentity(
                        receiverLocationID: $0.receiverLocationID, slot: $0.slot
                    )
                })
                let receiverIDs = Set(self.connections.filter { $0.value.source.channelID != nil }.keys)
                for id in receiverIDs.subtracting(present) {
                    self.retire(id)
                }
                self.refresh()
            }
            .store(in: &subscriptions)
    }

    func enable() {
        guard !isRunning else {
            return
        }
        authorization = CancellationSource()
        isRunning = true
        // This timer reads OS-maintained properties only. Existing HID++
        // connections are observed, never polled, including after a failed read.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 60)
        timer.setEventHandler { [weak self] in self?.refresh() }
        self.timer = timer
        timer.resume()
    }

    func disable() {
        isRunning = false
        authorization.cancel()
        timer?.cancel()
        timer = nil
        for value in connections.values {
            value.observer.stop()
            value.token.cancel()
        }
        connections.removeAll()
        gatt.stop()
        gattDevices.removeAll()
        propertyRefreshInFlight = false
    }

    func currentDeviceBatteryLevel(for device: Device) -> Int? {
        ConnectedBatteryDeviceInfo.currentDeviceBatteryLevel(
            pairedDevices: DeviceManager.shared.pairedReceiverDevices(for: device),
            directDeviceIdentity: Self.directIdentity(for: device),
            inventory: devices
        )
    }

    private func refresh() {
        guard isRunning else {
            return
        }
        synchronizeConnections()
        publish()
        guard !propertyRefreshInFlight else {
            return
        }
        propertyRefreshInFlight = true
        let token = authorization.token
        queue.async { [weak self] in
            guard token.shouldContinue else {
                return
            }
            let values = ConnectedBatteryDeviceInventory.devices()
            DispatchQueue.main.async {
                guard let self, self.isRunning, self.authorization.token == token else {
                    return
                }
                self.propertyRefreshInFlight = false
                self.propertyDevices = values
                self.publish()
            }
        }
    }

    private func synchronizeConnections() {
        var present = Set<String>()
        var fallback = [ConnectedBatteryDeviceInfo]()
        for device in DeviceManager.shared.devices where !device.isRemoved {
            let paired = DeviceManager.shared.pairedReceiverDevices(for: device)
            for identity in paired {
                let id = ConnectedBatteryDeviceInfo.receiverIdentity(
                    receiverLocationID: identity.receiverLocationID, slot: identity.slot
                )
                if let level = identity.batteryLevel {
                    fallback.append(.init(id: id, name: identity.name, batteryLevel: level))
                }
                guard let channel = LogitechReceiverChannel.existingChannel(locationID: identity.receiverLocationID)
                else {
                    continue
                }
                guard present.insert(id).inserted else {
                    continue
                }
                observe(
                    id: id,
                    source: Source(
                        deviceID: device.id,
                        channelID: ObjectIdentifier(channel),
                        serialNumber: identity.serialNumber,
                        productID: identity.productID
                    ),
                    name: identity.name,
                    device: device,
                    io: channel,
                    slot: identity.slot,
                    subscribe: channel.observeReports
                )
            }
            guard paired.isEmpty else {
                continue
            }
            let id = Self.directIdentity(for: device)
            if let level = device.batteryLevel {
                fallback.append(.init(id: id, name: device.name, batteryLevel: level))
            }
            guard device.vendorID == HIDPPConstants.vendorID,
                  !LogitechHIDPPDeviceMetadataProvider.isKnownReceiver(
                      vendorID: device.vendorID, productID: device.productID
                  ) else {
                continue
            }
            guard present.insert(id).inserted else {
                continue
            }
            observe(
                id: id,
                source: Source(deviceID: device.id),
                name: device.name,
                device: device,
                io: device.pointerDevice,
                slot: nil
            ) { callback in
                device.pointerDevice.observeReport { _, report in callback(report) }
            }
        }
        for id in Set(connections.keys).subtracting(present) {
            retire(id)
        }
        fallbackDevices = fallback
        let targets = DeviceManager.shared.devices.compactMap { device -> GATTBatteryTarget? in
            guard !device.isRemoved,
                  [PointerDeviceTransportName.bluetooth, PointerDeviceTransportName.bluetoothLowEnergy]
                  .contains(device.pointerDevice.transport ?? "") else {
                return nil
            }
            return GATTBatteryTarget(
                id: Self.directIdentity(for: device),
                generation: device.id,
                name: device.name,
                serialNumber: device.serialNumber,
                vendorID: device.vendorID,
                productID: device.productID
            )
        }
        gattTargetNames = Dictionary(targets.map { ($0.id, $0.name) }) { first, _ in first }
        gatt.updateTargets(targets)
    }

    private func observe(
        id: String,
        source: Source,
        name: String,
        device: Device,
        io: HIDPPDeviceIO,
        slot: UInt8?,
        subscribe: (@escaping (Data) -> Void) -> ObservationToken
    ) {
        guard connections[id]?.source != source else {
            return
        }
        retire(id)
        let generation = UUID()
        let observer = HIDPPBatteryObservation(receiverSlot: slot) { [weak self] update in
            DispatchQueue.main.async {
                guard let self, self.isRunning,
                      var connection = self.connections[id], connection.generation == generation,
                      update.sequence > connection.sequence else {
                    return
                }
                connection.sequence = update.sequence
                if let level = update.reading.level {
                    connection.info = .init(id: id, name: connection.name, batteryLevel: level)
                }
                self.connections[id] = connection
                self.publish()
            }
        }
        // Subscribe before discovery/initial reads so charging notifications
        // arriving during those requests are retained by the observer.
        let subscription = subscribe { [weak observer] report in observer?.receive(report) }
        connections[id] = Connection(
            source: source,
            generation: generation,
            name: name,
            observer: observer,
            token: subscription
        )
        let token = authorization.token
        queue.async { [weak device] in
            guard let device, token.shouldContinue, observer.isActive, !device.isRemoved,
                  let transport = HIDPPTransport(
                      device: io,
                      deviceIndex: slot,
                      deadline: Date().addingTimeInterval(1),
                      shouldContinue: { token.shouldContinue && observer.isActive && !device.isRemoved }
                  ) else {
                return
            }
            observer.readInitial(using: transport)
        }
    }

    private func retire(_ id: String) {
        guard let connection = connections.removeValue(forKey: id) else {
            return
        }
        connection.observer.stop()
        connection.token.cancel()
    }

    private func publish() {
        // An OS property read is not necessarily a new measurement. A valid
        // HID++ observation owns that device's value; OS data is a fallback.
        let values = connections.values.compactMap(\.info) + gattDevices + fallbackDevices + propertyDevices
        var seen = Set<String>()
        devices = values.filter { seen.insert($0.id).inserted }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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
}
