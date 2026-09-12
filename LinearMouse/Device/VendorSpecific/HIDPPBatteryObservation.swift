// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import HIDPP
import ObservationToken

/// One HID++ connection/receiver slot. Discover once, then consume unsolicited
/// battery reports without sending further requests. Reconnect creates a new instance.
final class HIDPPBatteryObservation {
    struct Reading: Equatable {
        enum ChargeState { case unknown, discharging, charging, full }
        let level: Int?
        let chargeState: ChargeState
    }

    struct Update {
        let reading: Reading
        let sequence: UInt64
    }

    struct Feature {
        let id: HIDPPFeatureID
        let index: UInt8
        var supportsPercentage = true

        func decode(_ payload: [UInt8]) -> Reading? {
            switch id {
            case .batteryStatus:
                guard payload.count >= 3 else {
                    return nil
                }
                return Reading(level: percentage(payload[0]), chargeState: chargeState(payload[2]))
            case .unifiedBattery:
                guard payload.count >= 4 else {
                    return nil
                }
                let approximate: Int? = [UInt8(1): 5, 2: 20, 4: 50, 8: 100][payload[1]]
                return Reading(
                    level: supportsPercentage ? percentage(payload[0]) ?? approximate : approximate,
                    chargeState: chargeState(payload[2])
                )
            case .batteryVoltage, .adcMeasurement:
                guard payload.count >= 3 else {
                    return nil
                }
                let flags = payload[2]
                if id == .adcMeasurement, flags & 0x01 == 0 {
                    return nil
                }
                let millivolts = Int(payload[0]) << 8 | Int(payload[1])
                guard (2000 ... 5000).contains(millivolts) else {
                    return nil
                }
                let level = Int((Double(min(4200, max(3500, millivolts)) - 3500) / 700 * 100).rounded())
                let state: Reading.ChargeState
                if id == .adcMeasurement {
                    state = flags & 0x02 != 0 ? .charging : .discharging
                } else {
                    state = flags & 0x80 == 0 ? .discharging : (flags & 0x03 == 3 ? .full : .charging)
                }
                return Reading(level: level, chargeState: state)
            default:
                return nil
            }
        }

        private func percentage(_ byte: UInt8) -> Int? {
            // HID++ uses zero as unknown for these battery features.
            (1 ... 100).contains(byte) ? Int(byte) : nil
        }

        private func chargeState(_ byte: UInt8) -> Reading.ChargeState {
            switch byte {
            case 0:
                return .discharging
            case 1, 2, 4:
                return .charging
            case 3:
                return .full
            default:
                return .unknown
            }
        }
    }

    private let lock = NSLock()
    private let acceptedIndices: Set<UInt8>
    private let onChange: (Update) -> Void
    private var active = true
    private var started = false
    private var feature: Feature?
    private var pendingReports = [UInt8: [UInt8]]()
    private var receivedNotification = false
    private var reading: Reading?
    private var sequence: UInt64 = 0

    init(receiverSlot: UInt8? = nil, onChange: @escaping (Update) -> Void) {
        acceptedIndices = receiverSlot.map { [$0] } ?? HIDPPConstants.directReplyIndices
        self.onChange = onChange
    }

    var isActive: Bool {
        lock.withLock { active }
    }

    func stop() {
        lock.withLock {
            active = false
            pendingReports.removeAll()
        }
    }

    /// The caller registers its input observer before invoking this on a worker.
    func readInitial(using transport: HIDPPTransport) {
        let shouldStart = lock.withLock {
            guard active, !started else {
                return false
            }
            started = true
            return true
        }
        guard shouldStart else {
            return
        }

        for id: HIDPPFeatureID in [.unifiedBattery, .batteryStatus, .batteryVoltage, .adcMeasurement] {
            guard isActive else {
                return
            }
            guard let index = transport.featureIndex(for: id) else {
                continue
            }
            var feature = Feature(id: id, index: index)
            if id == .unifiedBattery {
                guard let capabilities = transport.request(featureIndex: index, function: 0, parameters: []),
                      capabilities.payload.count >= 2 else {
                    continue
                }
                feature.supportsPercentage = capabilities.payload[1] & 0x02 != 0
            }
            configure(feature)
            let function: UInt8 = id == .unifiedBattery ? 1 : 0
            if let response = transport.request(featureIndex: index, function: function, parameters: []),
               let reading = feature.decode(response.payload) {
                acceptInitial(reading)
            }
            return
        }
    }

    func receive(_ data: Data) {
        let report = [UInt8](data)
        guard report.count >= HIDPPConstants.shortReportLength,
              report[0] == HIDPPConstants.shortReportID || report[0] == HIDPPConstants.longReportID,
              report[0] != HIDPPConstants.longReportID || report.count >= HIDPPConstants.longReportLength,
              acceptedIndices.contains(report[1]), report[2] > 0,
              report[3] == 0 else {
            return
        }
        let changed: Update? = lock.withLock {
            guard active else {
                return nil
            }
            guard let feature else {
                // Discovery requests can overlap the first battery notification.
                // Keep the latest event per feature, so frequent button
                // notifications cannot evict a battery update during discovery.
                pendingReports[report[2]] = report
                return nil
            }
            guard report[2] == feature.index, let value = feature.decode(Array(report.dropFirst(4))) else {
                return nil
            }
            receivedNotification = true
            return update(value)
        }
        if let changed {
            onChange(changed)
        }
    }

    private func configure(_ feature: Feature) {
        let changed: Update? = lock.withLock {
            guard active else {
                return nil
            }
            self.feature = feature
            defer { pendingReports.removeAll() }
            guard let report = pendingReports[feature.index],
                  let value = feature.decode(Array(report.dropFirst(4))) else {
                return nil
            }
            receivedNotification = true
            return update(value)
        }
        if let changed {
            onChange(changed)
        }
    }

    private func acceptInitial(_ value: Reading) {
        let changed: Update? = lock.withLock {
            guard active, !receivedNotification else {
                return nil
            }
            return update(value)
        }
        if let changed {
            onChange(changed)
        }
    }

    private func update(_ value: Reading) -> Update? {
        let next = Reading(level: value.level ?? reading?.level, chargeState: value.chargeState)
        guard next != reading else {
            return nil
        }
        reading = next
        sequence += 1
        return Update(reading: next, sequence: sequence)
    }
}

/// Fan out reports without consuming the receiver's connection/control queue.
final class HIDPPReportObservers {
    private let lock = NSLock()
    private var observers = [UUID: (Data) -> Void]()

    func observe(_ callback: @escaping (Data) -> Void) -> ObservationToken {
        let id = UUID()
        lock.withLock { observers[id] = callback }
        return ObservationToken { [weak self] in
            guard let self else {
                return
            }
            _ = self.lock.withLock { self.observers.removeValue(forKey: id) }
        }
    }

    func receive(_ report: Data) {
        let callbacks = lock.withLock { Array(observers.values) }
        callbacks.forEach { $0(report) }
    }
}
