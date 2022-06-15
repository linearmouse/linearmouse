// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Foundation
import PointerKitC

public final class PointerDeviceManager {
    private var eventSystemClient: IOHIDEventSystemClient?
    private let queue: DispatchQueue

    public typealias DeviceAddedClosure = (PointerDeviceManager, PointerDevice) -> Void
    public typealias DeviceRemovedClosure = (PointerDeviceManager, PointerDevice) -> Void
    public typealias PropertyChangedClosure = (PointerDeviceManager) -> Void

    private var observations = (
        deviceAdded: [UUID: DeviceAddedClosure](),
        deviceRemoved: [UUID: DeviceRemovedClosure](),
        propertyChanged: [UUID: (property: String, closure: PropertyChangedClosure)]()
    )

    public private(set) var devices = Set<PointerDevice>()

    public init(queue: DispatchQueue = DispatchQueue.main) {
        self.queue = queue
    }
}

// MARK: Observation API

public extension PointerDeviceManager {
    func observeDeviceAdded(using closure: @escaping DeviceAddedClosure) -> ObservationToken {
        let id = observations.deviceAdded.insert(closure)

        return ObservationToken { [weak self] in
            self?.observations.deviceAdded.removeValue(forKey: id)
        }
    }

    func observeDeviceRemoved(using closure: @escaping DeviceRemovedClosure) -> ObservationToken {
        let id = observations.deviceRemoved.insert(closure)

        return ObservationToken { [weak self] in
            self?.observations.deviceRemoved.removeValue(forKey: id)
        }
    }

    func observePropertyChanged(property: String,
                                using closure: @escaping PropertyChangedClosure) -> ObservationToken {
        let id = observations.propertyChanged.insert((property: property, closure: closure))

        return ObservationToken { [weak self] in
            self?.observations.propertyChanged.removeValue(forKey: id)
        }
    }
}

// MARK: Device observation

extension PointerDeviceManager {
    private enum ObservationMatches {
        static var mouseOrPointer: CFArray {
            let usageMouse = [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse
            ] as CFDictionary

            let usagePointer = [
                kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer
            ] as CFDictionary

            return [usageMouse, usagePointer] as CFArray
        }
    }

    private static let propertyChangedCallback: IOHIDEventSystemClientPropertyChangedCallback =
        { target, _, property, value in
            guard let target = target else { return }
            guard let property = property else { return }

            let this = Unmanaged<PointerDeviceManager>.fromOpaque(target).takeUnretainedValue()
            this.propertyChangedCallback(property as String, value)
        }

    /**
     Start observing device additions and removals.

     Registered `DeviceAddedClosure`s will be notified immediately with all the current devices.
     */
    public func startObservation() {
        queue.async { [self] in
            guard eventSystemClient == nil else { return }

            guard let eventSystemClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
                return
            }

            self.eventSystemClient = eventSystemClient

            IOHIDEventSystemClientSetMatchingMultiple(eventSystemClient,
                                                      ObservationMatches.mouseOrPointer)
            IOHIDEventSystemClientRegisterDeviceMatchingBlock(eventSystemClient,
                                                              serviceMatchingCallback,
                                                              nil,
                                                              nil)
            IOHIDEventSystemClientScheduleWithDispatchQueue(eventSystemClient, queue)

            if let clients = IOHIDEventSystemClientCopyServices(eventSystemClient) as? [IOHIDServiceClient] {
                for client in clients {
                    addDevice(forClient: client)
                }
            }

            for property in observations.propertyChanged.values.map(\.property) {
                IOHIDEventSystemClientRegisterPropertyChangedCallback(
                    eventSystemClient,
                    property as CFString,
                    Self.propertyChangedCallback,
                    Unmanaged.passUnretained(self).toOpaque(),
                    nil
                )
            }
        }
    }

    /**
     Stop observing device additions and removals.

     Registered `DeviceRemovedClosure`s will be notified immediately with all the current devices.
     */
    public func stopObservation() {
        queue.async { [self] in
            guard let eventSystemClient = eventSystemClient else { return }

            IOHIDEventSystemClientUnregisterDeviceMatchingBlock(eventSystemClient)
            IOHIDEventSystemClientUnscheduleFromDispatchQueue(eventSystemClient, queue)

            for device in devices {
                removeDevice(device)
            }

            self.eventSystemClient = nil
        }
    }

    private func serviceMatchingCallback(_: UnsafeMutableRawPointer?,
                                         _: UnsafeMutableRawPointer?,
                                         _ client: IOHIDServiceClient?) {
        guard let client = client else { return }

        queue.async { [self] in
            addDevice(forClient: client)
        }
    }

    private func clientRemovalCallback(_: UnsafeMutableRawPointer?,
                                       _: UnsafeMutableRawPointer?,
                                       _ client: IOHIDServiceClient?) {
        guard let client = client else { return }

        queue.async { [self] in
            removeDevice(forClient: client)
        }
    }

    private func propertyChangedCallback(_ property: String, _: AnyObject?) {
        queue.async { [self] in
            for (_, (observingProperty, callback)) in observations.propertyChanged where property == observingProperty {
                callback(self)
            }
        }
    }

    private func addDevice(forClient client: IOHIDServiceClient) {
        let device = PointerDevice(client, queue)

        guard !devices.contains(device) else { return }

        devices.insert(device)

        for (_, callback) in observations.deviceAdded {
            callback(self, device)
        }

        IOHIDServiceClientRegisterRemovalBlock(client, clientRemovalCallback, nil, nil)
    }

    private func removeDevice(forClient client: IOHIDServiceClient) {
        let device = PointerDevice(client, queue)

        guard devices.contains(device) else { return }

        removeDevice(device)
    }

    private func removeDevice(_ device: PointerDevice) {
        devices.remove(device)

        for (_, callback) in observations.deviceRemoved {
            callback(self, device)
        }
    }
}
