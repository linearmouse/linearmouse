// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import os.log

private struct BoltHIDPP10Report {
    let bytes: [UInt8]
}

extension LogitechReceiverChannel {
    func discoverBoltSlots() -> LogitechHIDPPDeviceMetadataProvider.ReceiverSlotDiscovery? {
        guard readBoltUniqueID() != nil else {
            os_log(
                "Bolt receiver unique ID is unavailable: locationID=%{public}@",
                log: LogitechHIDPPDeviceMetadataProvider.log,
                type: .info,
                locationID.map(String.init) ?? "(nil)"
            )
            return nil
        }

        let connectedDeviceCount = readBoltConnectionState().flatMap {
            LogitechHIDPPDeviceMetadataProvider.parseConnectedDeviceCount($0.bytes)
        }
        let connectionSnapshots = discoverBoltConnectionSnapshots(expectedCount: connectedDeviceCount)
        let pairedSlots = (UInt8(1) ... UInt8(6)).compactMap {
            discoverBoltSlotInfo($0, connectionSnapshot: connectionSnapshots[$0])
        }

        return pairedSlots.isEmpty ? nil : .init(slots: pairedSlots, connectionSnapshots: connectionSnapshots)
    }

    func discoverBoltSlotInfo(
        _ slot: UInt8,
        connectionSnapshot: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot? = nil
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverSlotInfo? {
        let metadataProvider = LogitechHIDPPDeviceMetadataProvider()
        let pairingResponse = boltReceiverInfoRequest(subregister: UInt8(0x50 + Int(slot)))
        let nameResponse = boltReceiverInfoRequest(subregister: UInt8(0x60 + Int(slot)), parameters: [0x01])

        guard pairingResponse != nil || nameResponse != nil else {
            return nil
        }

        let routedTransport = LogitechHIDPPTransport(device: self, deviceIndex: slot)
        let routedName = routedTransport.flatMap { transport in
            metadataProvider.readFriendlyName(using: transport) ?? metadataProvider.readName(using: transport)
        }
        let batteryLevel = routedTransport.flatMap {
            metadataProvider.readReceiverBatteryLevel(using: $0)
        }
        let kind = connectionSnapshot?.kind
            ?? pairingResponse.flatMap { Self.parseBoltReceiverKind($0.bytes) }
            ?? 0
        let name = routedName ?? nameResponse.flatMap { Self.parseBoltReceiverName($0.bytes) }

        return .init(
            slot: slot,
            kind: kind,
            name: name,
            productID: pairingResponse.flatMap { Self.parseBoltReceiverProductID($0.bytes) },
            serialNumber: pairingResponse.flatMap { Self.parseBoltReceiverSerialNumber($0.bytes) },
            batteryLevel: batteryLevel,
            hasLiveMetadata: routedName != nil || batteryLevel != nil
        )
    }

    func discoverBoltPointingDeviceDiscovery(
        baseName: String
    ) -> LogitechHIDPPDeviceMetadataProvider.ReceiverPointingDeviceDiscovery {
        guard let locationID,
              let discovery = discoverBoltSlots()
        else {
            return .init(identities: [], connectionSnapshots: [:], liveReachableSlots: [])
        }

        let liveReachableSlots = Set(discovery.slots.compactMap { slot in
            slot.hasLiveMetadata ? slot.slot : nil
        })

        let identities = discovery.slots.compactMap { slot -> ReceiverLogicalDeviceIdentity? in
            guard let kind = ReceiverLogicalDeviceKind(rawValue: slot.kind), kind.isPointingDevice else {
                return nil
            }

            return ReceiverLogicalDeviceIdentity(
                receiverLocationID: locationID,
                slot: slot.slot,
                kind: kind,
                name: slot.name ?? baseName,
                serialNumber: slot.serialNumber,
                productID: slot.productID,
                batteryLevel: slot.batteryLevel
            )
        }

        return .init(
            identities: identities,
            connectionSnapshots: discovery.connectionSnapshots,
            liveReachableSlots: liveReachableSlots
        )
    }

    private func readBoltUniqueID() -> BoltHIDPP10Report? {
        boltHIDPP10LongRequest(register: 0xFB, parameters: [])
    }

    private func readBoltConnectionState() -> BoltHIDPP10Report? {
        boltHIDPP10ShortRequest(
            subID: 0x81,
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverConnectionStateRegister,
            parameters: [0, 0, 0]
        )
    }

    private func triggerBoltConnectionNotifications() -> Bool {
        boltHIDPP10ShortRequest(
            subID: 0x80,
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverConnectionStateRegister,
            parameters: [0x02, 0x00, 0x00]
        ) != nil
    }

    private func discoverBoltConnectionSnapshots(
        expectedCount: Int? = nil
    ) -> [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot] {
        guard triggerBoltConnectionNotifications() else {
            return [:]
        }

        return collectBoltConnectionSnapshots(timeout: 0.5, expectedCount: expectedCount, until: nil)
    }

    func waitForBoltConnectionSnapshots(
        timeout: TimeInterval,
        until shouldContinue: (() -> Bool)? = nil
    ) -> [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot] {
        guard triggerBoltConnectionNotifications() else {
            return [:]
        }

        guard let initialNotification = waitForBoltConnectionNotification(
            timeout: timeout,
            until: shouldContinue
        ) else {
            return [:]
        }

        var snapshots = [initialNotification.slot: initialNotification.snapshot]
        let deadline = Date().addingTimeInterval(0.1)
        while Date() < deadline, shouldContinue?() ?? true {
            guard let notification = waitForBoltConnectionNotification(timeout: 0.02, until: shouldContinue) else {
                continue
            }

            snapshots[notification.slot] = notification.snapshot
        }

        return snapshots
    }

    func isBoltReceiverReachable() -> Bool {
        readBoltUniqueID() != nil
    }

    private func collectBoltConnectionSnapshots(
        timeout: TimeInterval,
        expectedCount: Int? = nil,
        until shouldContinue: (() -> Bool)? = nil
    ) -> [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot] {
        var snapshots = [UInt8: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot]()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, shouldContinue?() ?? true {
            guard let report = waitForHIDPPNotification(
                timeout: 0.05,
                matching: { response in
                    LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification(response) != nil
                },
                until: shouldContinue
            ) else {
                if let expectedCount,
                   snapshots.values.filter(\.isConnected).count >= expectedCount {
                    break
                }
                continue
            }

            guard let notification = LogitechHIDPPDeviceMetadataProvider
                .parseReceiverConnectionNotification(report) else {
                continue
            }

            snapshots[notification.slot] = notification.snapshot
            if let expectedCount,
               snapshots.values.filter(\.isConnected).count >= expectedCount {
                break
            }
        }

        return snapshots
    }

    private func waitForBoltConnectionNotification(
        timeout: TimeInterval,
        until shouldContinue: (() -> Bool)?
    ) -> (slot: UInt8, snapshot: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot)? {
        guard let report = waitForHIDPPNotification(
            timeout: timeout,
            matching: { response in
                LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification(response) != nil
            },
            until: shouldContinue
        ) else {
            return nil
        }

        return LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification(report)
    }

    private func boltReceiverInfoRequest(
        subregister: UInt8,
        parameters: [UInt8] = []
    ) -> BoltHIDPP10Report? {
        boltHIDPP10LongRequest(
            register: LogitechHIDPPDeviceMetadataProvider.Constants.receiverInfoRegister,
            parameters: [subregister] + parameters,
            firstParameter: subregister
        )
    }

    private func boltHIDPP10ShortRequest(
        subID: UInt8,
        register: UInt8,
        parameters: [UInt8]
    ) -> BoltHIDPP10Report? {
        var bytes = [UInt8](repeating: 0, count: LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength)
        bytes[0] = LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID
        bytes[1] = LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex
        bytes[2] = subID
        bytes[3] = register
        for (index, parameter) in parameters.prefix(3).enumerated() {
            bytes[4 + index] = parameter
        }

        let response = performSynchronousOutputReportRequest(
            Data(bytes),
            timeout: LogitechHIDPPDeviceMetadataProvider.Constants.timeout
        ) { report in
            let reply = [UInt8](report)
            guard reply.count >= LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength,
                  [
                      LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID,
                      LogitechHIDPPDeviceMetadataProvider.Constants.longReportID
                  ].contains(reply[0]),
                  reply[1] == LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex
            else {
                return false
            }

            if reply[2] == 0x8F {
                return reply[3] == subID && reply[4] == register
            }

            return reply[2] == subID && reply[3] == register
        }

        guard let response else {
            return nil
        }

        let responseBytes = Array(response)
        return responseBytes[2] == 0x8F ? nil : .init(bytes: responseBytes)
    }

    private func boltHIDPP10LongRequest(
        register: UInt8,
        parameters: [UInt8],
        firstParameter: UInt8? = nil
    ) -> BoltHIDPP10Report? {
        var bytes = [UInt8](repeating: 0, count: LogitechHIDPPDeviceMetadataProvider.Constants.shortReportLength)
        bytes[0] = LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID
        bytes[1] = LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex
        bytes[2] = 0x83
        bytes[3] = register
        for (index, parameter) in parameters.prefix(3).enumerated() {
            bytes[4 + index] = parameter
        }

        let response = performSynchronousOutputReportRequest(
            Data(bytes),
            timeout: LogitechHIDPPDeviceMetadataProvider.Constants.timeout
        ) { report in
            let reply = [UInt8](report)
            guard reply.count >= 5,
                  [
                      LogitechHIDPPDeviceMetadataProvider.Constants.shortReportID,
                      LogitechHIDPPDeviceMetadataProvider.Constants.longReportID
                  ].contains(reply[0]),
                  reply[1] == LogitechHIDPPDeviceMetadataProvider.Constants.receiverIndex
            else {
                return false
            }

            if reply[2] == 0x8F {
                return reply[3] == 0x83 && reply[4] == register
            }

            guard reply[2] == 0x83,
                  reply[3] == register
            else {
                return false
            }

            if let firstParameter {
                return reply.count > 4 && reply[4] == firstParameter
            }

            return true
        }

        guard let response else {
            return nil
        }

        let responseBytes = Array(response)
        return responseBytes[2] == 0x8F ? nil : .init(bytes: responseBytes)
    }

    static func parseBoltReceiverKind(_ response: [UInt8]) -> UInt8? {
        guard response.count >= 6 else {
            return nil
        }

        return response[5] & 0x0F
    }

    static func parseBoltReceiverProductID(_ response: [UInt8]) -> Int? {
        guard response.count >= 8 else {
            return nil
        }

        return Int(response[7]) << 8 | Int(response[6])
    }

    static func parseBoltReceiverSerialNumber(_ response: [UInt8]) -> String? {
        guard response.count >= 12 else {
            return nil
        }

        return response[8 ... 11].map { String(format: "%02X", $0) }.joined()
    }

    static func parseBoltReceiverName(_ response: [UInt8]) -> String? {
        guard response.count >= 7 else {
            return nil
        }

        let length = Int(response[6])
        let bytes = Array(response.dropFirst(7).prefix(length))
        guard !bytes.isEmpty else {
            return nil
        }

        return String(bytes: bytes, encoding: .utf8)
    }
}
