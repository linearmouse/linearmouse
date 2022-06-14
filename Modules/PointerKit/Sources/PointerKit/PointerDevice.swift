//
//  PointerDevice.swift
//  
//
//  Created by Jiahao Lu on 2022/6/14.
//

import PointerKitC
import Foundation

public class PointerDevice {
    private let client: IOHIDServiceClient
    private let device: IOHIDDevice?
    private let queue: DispatchQueue

    public typealias InputValueClosure = (PointerDevice, IOHIDValue) -> Void

    private var observations = (
        inputValue: [UUID: InputValueClosure](),
        ()
    )

    private static let inputValueCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context = context else {
            return
        }

        let this = Unmanaged<PointerDevice>.fromOpaque(context).takeUnretainedValue()
        this.inputValueCallback(value)
    }

    init(_ client: IOHIDServiceClient, _ queue: DispatchQueue) {
        self.client = client
        self.device = client.device
        self.queue = queue

        if let device = device {
            IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDDeviceRegisterInputValueCallback(device,
                                                  Self.inputValueCallback,
                                                  Unmanaged.passUnretained(self).toOpaque())
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
    }

    deinit {
        if let device = device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
    }
}

extension PointerDevice: Equatable {
    public static func == (lhs: PointerDevice, rhs: PointerDevice) -> Bool {
        lhs.client == rhs.client
    }
}

extension PointerDevice: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(client)
    }
}


// MARK: Product and vendor information

extension PointerDevice {
    public var product: String? {
        client.getProperty(kIOHIDProductKey)
    }

    public var name: String {
        product ?? "(unknown)"
    }

    public var vendorID: Int? {
        client.getProperty(kIOHIDVendorIDKey)
    }

    public var productID: Int? {
        client.getProperty(kIOHIDProductIDKey)
    }

    public var vendorIDString: String {
        guard let vendorID = vendorID else {
            return "(null)"
        }

        return String(format: "0x%04X", vendorID)
    }

    public var productIDString: String {
        guard let productID = productID else {
            return "(null)"
        }

        return String(format: "0x%04X", productID)
    }
}

extension PointerDevice: CustomStringConvertible {
    public var description: String {
        String(format: "%@ (VID=%@, PID=%@)", name, vendorIDString, productIDString)
    }
}


// MARK: Pointer resolution and acceleration

extension PointerDevice {
    /**
     Indicates the pointer resolution.
     The lower the value is, the faster the pointer moves.

     This value is in the range [10-1995].
     */
    public var pointerResolution: Double? {
        get { client.getPropertyIOFixed(kIOHIDPointerResolutionKey) }

        set {
            client.setPropertyIOFixed(newValue.map { $0.clamp(10, 1995) }, forKey: kIOHIDPointerResolutionKey)

            // HACK: Trigger a `pointerAcceleration` change to make `pointerResolution` take affect
            pointerAcceleration = pointerAcceleration
        }
    }

    public var pointerAccelerationType: String? {
        get {
            if let pointerAccelerationType = client.getProperty(kIOHIDPointerAccelerationTypeKey) as String? {
                return pointerAccelerationType
            }

            // Guess the type...

            if let _ = client.getProperty(kIOHIDPointerAccelerationKey) as IOFixed? {
                return kIOHIDPointerAccelerationKey
            }

            return kIOHIDMouseAccelerationTypeKey
        }

        set {
            client.setProperty(newValue, forKey: kIOHIDPointerAccelerationKey)
        }
    }

    /**
     Indicates the pointer acceleration.

     This value is in the range [0, 20] ∪ { -1 }. -1 means acceleration and sensitivity are disabled.
     */
    public var pointerAcceleration: Double? {
        get { client.getPropertyIOFixed(pointerAccelerationType ?? kIOHIDMouseAccelerationTypeKey) }

        set {
            client.setPropertyIOFixed(newValue.map { $0 == -1 ? $0 : $0.clamp(0, 20) },
                                      forKey: pointerAccelerationType ?? kIOHIDMouseAccelerationTypeKey)
        }
    }
}


// MARK: Observe input events

extension PointerDevice {
    private func inputValueCallback(_ value: IOHIDValue) {
        queue.async { [self] in
            for (_, callback) in observations.inputValue {
                callback(self, value)
            }
        }
    }

    public func observeInput(using closure: @escaping InputValueClosure) -> ObservationToken {
        let id = observations.inputValue.insert(closure)

        return ObservationToken { [weak self] in
            self?.observations.inputValue.removeValue(forKey: id)
        }
    }
}


// MARK: Utilities

extension PointerDevice {
    public func confirmsTo(_ usagePage: Int, _ usage: Int) -> Bool {
        IOHIDServiceClientConformsTo(client, UInt32(usagePage), UInt32(usage)) != 0
    }
}
