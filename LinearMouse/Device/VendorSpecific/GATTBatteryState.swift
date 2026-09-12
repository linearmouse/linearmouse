// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

struct GATTBatteryTarget: Equatable {
    let id: String
    let generation: Int32
    let name: String
    let serialNumber: String?
    let vendorID: Int?
    let productID: Int?
}

struct GATTBatteryIdentity {
    let id: UUID
    var serialNumber: String?
    var vendorID: Int?
    var productID: Int?

    mutating func setPnPID(_ data: Data) {
        // Source 2 uses USB vendor IDs, matching IOKit's VendorID. Bluetooth
        // SIG company identifiers (source 1) are a different namespace.
        guard data.count == 7, data[0] == 2 else {
            return
        }
        vendorID = Int(data[1]) | Int(data[2]) << 8
        productID = Int(data[3]) | Int(data[4]) << 8
    }

    static func matchedTarget(
        for peer: Self, peers: [Self], targets: [GATTBatteryTarget], discoveryComplete: Bool
    ) -> String? {
        if let serial = normalizedSerial(peer.serialNumber) {
            guard peers.filter({ normalizedSerial($0.serialNumber) == serial }).count == 1 else {
                return nil
            }
            let matches = targets.filter {
                normalizedSerial($0.serialNumber) == serial
                    && (peer.vendorID == nil || $0.vendorID == nil || peer.vendorID == $0.vendorID)
                    && (peer.productID == nil || $0.productID == nil || peer.productID == $0.productID)
            }
            return matches.count == 1 ? matches[0].id : nil
        }
        guard discoveryComplete, let vendor = peer.vendorID, let product = peer.productID,
              peers.allSatisfy({ $0.vendorID != nil && $0.productID != nil }),
              peers.filter({ $0.vendorID == vendor && $0.productID == product }).count == 1 else {
            return nil
        }
        let matches = targets.filter { $0.vendorID == vendor && $0.productID == product }
        return matches.count == 1 ? matches[0].id : nil
    }

    private static func normalizedSerial(_ serial: String?) -> String? {
        guard let serial = serial?.trimmingCharacters(in: .whitespacesAndNewlines), !serial.isEmpty,
              !serial.allSatisfy({ $0 == "0" }), !serial.uppercased().allSatisfy({ $0 == "F" }) else {
            return nil
        }
        return serial
    }
}

/// Read first, then subscribe: the initial read response cannot overwrite a
/// notification, because notifications are only enabled after that response.
struct GATTBatteryState {
    enum Action: Equatable { case read, subscribe }
    enum Phase { case idle, reading, subscribing, listening, readOnly, stopped }
    private(set) var phase = Phase.idle
    private(set) var level: Int?
    private var canNotify = false

    mutating func start(canRead: Bool, canNotify: Bool) -> [Action] {
        guard phase == .idle else {
            return []
        }
        self.canNotify = canNotify
        if canRead {
            phase = .reading
            return [.read]
        }
        return subscribeIfPossible()
    }

    mutating func receive(_ data: Data?) -> [Action] {
        guard phase != .idle, phase != .stopped else {
            return []
        }
        if let data, data.count == 1, data[0] <= 100 {
            level = Int(data[0])
        }
        return phase == .reading ? subscribeIfPossible() : []
    }

    mutating func notificationStateChanged(enabled: Bool) {
        guard phase == .subscribing else {
            return
        }
        phase = enabled ? .listening : .readOnly
    }

    mutating func stop() {
        phase = .stopped
        level = nil
    }

    private mutating func subscribeIfPossible() -> [Action] {
        phase = canNotify ? .subscribing : .readOnly
        return canNotify ? [.subscribe] : []
    }
}
