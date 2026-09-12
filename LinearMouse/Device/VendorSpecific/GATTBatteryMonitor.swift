// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreBluetooth
import Foundation

/// Main-queue CoreBluetooth adapter. Only attaches to peripherals that are
/// already connected to macOS; it never scans for or reconnects sleeping mice.
final class GATTBatteryMonitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    struct Value: Equatable {
        let targetID: String
        let level: Int
    }

    private final class Peer {
        let peripheral: CBPeripheral
        var identity: GATTBatteryIdentity
        var state = GATTBatteryState()
        var battery: CBCharacteristic?
        var identityServicesPending = true
        var identityReads = Set<CBUUID>()
        var targetID: String?
        init(_ peripheral: CBPeripheral) {
            self.peripheral = peripheral
            identity = GATTBatteryIdentity(id: peripheral.identifier)
        }
    }

    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")
    private static let informationService = CBUUID(string: "180A")
    private static let serialNumber = CBUUID(string: "2A25")
    private static let pnpID = CBUUID(string: "2A50")
    private var central: CBCentralManager?
    private var peers = [UUID: Peer]()
    private var attempted = Set<UUID>()
    private var targets = [GATTBatteryTarget]()
    private var lastValues = [Value]()
    private let onChange: ([Value]) -> Void
    private let diagnostic: (String) -> Void

    init(onChange: @escaping ([Value]) -> Void, diagnostic: @escaping (String) -> Void = { _ in }) {
        self.onChange = onChange
        self.diagnostic = diagnostic
        super.init()
    }

    func updateTargets(_ targets: [GATTBatteryTarget]) {
        if targets != self.targets {
            attempted.removeAll()
        }
        self.targets = targets
        guard !targets.isEmpty else {
            stop(); return
        }
        let validIDs = Set(targets.map(\.id))
        for (id, peer) in peers where peer.targetID.map({ !validIDs.contains($0) }) == true {
            retire(id, cancel: true)
        }
        if central == nil {
            central = CBCentralManager(
                delegate: self,
                queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false]
            )
        } else {
            attachConnectedPeripherals()
            publish()
        }
    }

    func stop() {
        let previous = central
        central = nil
        previous?.delegate = nil
        for peer in peers.values {
            peer.state.stop()
            peer.peripheral.delegate = nil
            previous?.cancelPeripheralConnection(peer.peripheral)
        }
        peers.removeAll()
        attempted.removeAll()
        targets.removeAll()
        lastValues = []
        onChange([])
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === self.central else {
            return
        }
        diagnostic("Bluetooth state=\(central.state.rawValue)")
        guard central.state == .poweredOn else {
            for peer in peers.values {
                peer.state.stop(); peer.peripheral.delegate = nil
            }
            peers.removeAll()
            attempted.removeAll()
            publish()
            return
        }
        attachConnectedPeripherals()
    }

    private func attachConnectedPeripherals() {
        guard let central, central.state == .poweredOn, !targets.isEmpty else {
            return
        }
        for peripheral in central.retrieveConnectedPeripherals(withServices: [Self.batteryService]) {
            guard peers[peripheral.identifier] == nil,
                  attempted.insert(peripheral.identifier).inserted else {
                continue
            }
            peers[peripheral.identifier] = Peer(peripheral)
            peripheral.delegate = self
            central.connect(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central === self.central, current(peripheral) != nil else {
            return
        }
        peripheral.discoverServices([Self.batteryService, Self.informationService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard central === self.central else {
            return
        }
        diagnostic("Bluetooth connection failed: \(String(describing: error))")
        retire(peripheral.identifier, cancel: false)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error _: Error?
    ) {
        guard central === self.central else {
            return
        }
        attempted.remove(peripheral.identifier)
        retire(peripheral.identifier, cancel: false)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let peer = current(peripheral) else {
            return
        }
        guard error == nil else {
            retire(peripheral.identifier, cancel: true); return
        }
        let services = peripheral.services ?? []
        peer.identityServicesPending = services.contains { $0.uuid == Self.informationService }
        guard services.contains(where: { $0.uuid == Self.batteryService }) else {
            retire(peripheral.identifier, cancel: true)
            return
        }
        for service in services {
            if service.uuid == Self.batteryService {
                peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
            } else if service.uuid == Self.informationService {
                peripheral.discoverCharacteristics([Self.serialNumber, Self.pnpID], for: service)
            }
        }
        publish()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let peer = current(peripheral) else {
            return
        }
        if service.uuid == Self.informationService {
            peer.identityServicesPending = false
            for characteristic in service.characteristics ?? [] where error == nil {
                guard characteristic.properties.contains(.read) else {
                    continue
                }
                peer.identityReads.insert(characteristic.uuid)
                peripheral.readValue(for: characteristic)
            }
            publish()
        } else if service.uuid == Self.batteryService, error == nil,
                  let characteristic = service.characteristics?.first(where: { $0.uuid == Self.batteryLevel }) {
            peer.battery = characteristic
            publish()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let peer = current(peripheral) else {
            return
        }
        if characteristic === peer.battery {
            let initial = peer.state.phase == .reading
            let actions = peer.state.receive(error == nil ? characteristic.value : nil)
            diagnostic(
                "GATT \(initial ? "initial read" : "notification") \(peripheral.identifier): \(String(describing: peer.state.level)) error=\(String(describing: error))"
            )
            perform(actions, on: peer)
        } else if peer.identityReads.remove(characteristic.uuid) != nil, error == nil,
                  let data = characteristic.value {
            if characteristic.uuid == Self.serialNumber {
                peer.identity.serialNumber = String(data: data, encoding: .utf8)
            } else if characteristic.uuid == Self.pnpID {
                peer.identity.setPnPID(data)
            }
        }
        publish()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let peer = current(peripheral), characteristic === peer.battery else {
            return
        }
        peer.state.notificationStateChanged(enabled: error == nil && characteristic.isNotifying)
        diagnostic(
            "GATT subscription \(peripheral.identifier): \(characteristic.isNotifying) error=\(String(describing: error))"
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard let peer = current(peripheral), invalidatedServices.contains(where: {
            $0.uuid == Self.batteryService || $0.uuid == Self.informationService
        }) else {
            return
        }
        peer.state = GATTBatteryState()
        peer.battery = nil
        peer.identity = GATTBatteryIdentity(id: peripheral.identifier)
        peer.identityServicesPending = true
        peer.identityReads.removeAll()
        peripheral.discoverServices([Self.batteryService, Self.informationService])
        publish()
    }

    private func perform(_ actions: [GATTBatteryState.Action], on peer: Peer) {
        guard let characteristic = peer.battery else {
            return
        }
        for action in actions {
            switch action {
            case .read:
                peer.peripheral.readValue(for: characteristic)
            case .subscribe:
                peer.peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    private func current(_ peripheral: CBPeripheral) -> Peer? {
        guard central?.state == .poweredOn, let peer = peers[peripheral.identifier],
              peer.peripheral === peripheral else {
            return nil
        }
        return peer
    }

    private func retire(_ id: UUID, cancel: Bool) {
        guard let peer = peers.removeValue(forKey: id) else {
            return
        }
        peer.state.stop()
        peer.peripheral.delegate = nil
        if cancel {
            central?.cancelPeripheralConnection(peer.peripheral)
        }
        publish()
    }

    private func publish() {
        let identities = peers.values.map(\.identity)
        let complete = peers.values.allSatisfy { !$0.identityServicesPending && $0.identityReads.isEmpty }
        let values = peers.values
            .compactMap { peer -> Value? in
                peer.targetID = GATTBatteryIdentity.matchedTarget(
                    for: peer.identity,
                    peers: identities,
                    targets: targets,
                    discoveryComplete: complete
                )
                guard let id = peer.targetID else {
                    return nil
                }
                // Only subscribe after matching a connected input device.
                if let characteristic = peer.battery, peer.state.phase == .idle,
                   !peer.identityServicesPending, peer.identityReads.isEmpty {
                    perform(peer.state.start(
                        canRead: characteristic.properties.contains(.read),
                        canNotify: characteristic.properties.contains(.notify)
                            || characteristic.properties.contains(.indicate)
                    ), on: peer)
                }
                guard let level = peer.state.level else {
                    return nil
                }
                return Value(targetID: id, level: level)
            }
            .sorted { $0.targetID < $1.targetID }
        guard values != lastValues else {
            return
        }
        lastValues = values
        onChange(values)
    }
}
