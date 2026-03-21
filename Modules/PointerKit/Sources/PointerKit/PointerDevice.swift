// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import ObservationToken
import PointerKitC

public class PointerDevice {
    let client: IOHIDServiceClient
    let device: IOHIDDevice?

    public typealias InputValueClosure = (PointerDevice, IOHIDValue) -> Void
    public typealias InputReportClosure = (PointerDevice, Data) -> Void

    private var inputReportCallbackRegistered = false
    private var inputReportBuffer: UnsafeMutablePointer<UInt8>?
    private var inputReportBufferLength = 0

    private let synchronousReportRequestLock = NSLock()
    private let pendingReportRequestLock = NSLock()
    private var pendingReportMatcher: ((Data) -> Bool)?
    private var pendingReportResponse: Data?
    private var pendingReportSemaphore: DispatchSemaphore?

    private var observations = (
        inputValue: [UUID: InputValueClosure](),
        inputReport: [UUID: InputReportClosure](),
        ()
    )

    private static let inputValueCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else {
            return
        }
        let this = Unmanaged<PointerDevice>.fromOpaque(context).takeUnretainedValue()

        this.inputValueCallback(value)
    }

    private static let inputReportCallback: IOHIDReportCallback = { context, _, _, _, _, report, reportLength in
        guard let context else {
            return
        }
        let this = Unmanaged<PointerDevice>.fromOpaque(context).takeUnretainedValue()

        this.inputReportCallback(Data(bytes: report, count: reportLength))
    }

    init(_ client: IOHIDServiceClient) {
        self.client = client
        device = client.device

        if let device {
            IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDDeviceSetInputValueMatching(device, nil)
            let this = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputValueCallback(device, Self.inputValueCallback, this)
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
    }

    deinit {
        inputReportBuffer?.deallocate()

        if let device {
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

public extension PointerDevice {
    var product: String? {
        client.getProperty(kIOHIDProductKey)
    }

    var name: String {
        product ?? "(unknown)"
    }

    var vendorID: Int? {
        client.getProperty(kIOHIDVendorIDKey)
    }

    var productID: Int? {
        client.getProperty(kIOHIDProductIDKey)
    }

    var vendorIDString: String {
        guard let vendorID else {
            return "(nil)"
        }

        return String(format: "0x%04X", vendorID)
    }

    var productIDString: String {
        guard let productID else {
            return "(nil)"
        }

        return String(format: "0x%04X", productID)
    }

    var serialNumber: String? {
        client.getProperty(kIOHIDSerialNumberKey)
    }

    var buttonCount: Int? {
        client.getProperty(kIOHIDPointerButtonCountKey)
    }

    var locationID: Int? {
        client.getProperty("LocationID")
    }

    var primaryUsagePage: Int? {
        client.getProperty("PrimaryUsagePage")
    }

    var primaryUsage: Int? {
        client.getProperty("PrimaryUsage")
    }

    var maxInputReportSize: Int? {
        client.getProperty("MaxInputReportSize")
    }

    var maxOutputReportSize: Int? {
        client.getProperty("MaxOutputReportSize")
    }

    var maxFeatureReportSize: Int? {
        client.getProperty("MaxFeatureReportSize")
    }

    var transport: String? {
        client.getProperty("Transport")
    }
}

extension PointerDevice: CustomStringConvertible {
    public var description: String {
        String(format: "%@ (VID=%@, PID=%@)", name, vendorIDString, productIDString)
    }
}

// MARK: Pointer resolution and acceleration

public extension PointerDevice {
    /**
     Indicates the pointer resolution.
     The lower the value is, the faster the pointer moves.

     This value is in the range [10-1995].
     */
    var pointerResolution: Double? {
        get { client.getPropertyIOFixed(kIOHIDPointerResolutionKey) }

        set {
            client.setPropertyIOFixed(newValue.map { $0.clamp(10, 1995) }, forKey: kIOHIDPointerResolutionKey)

            // HACK: Trigger a `pointerAcceleration` change to make `pointerResolution` take affect
            pointerAcceleration = pointerAcceleration
        }
    }

    var pointerAccelerationType: String? {
        get {
            if let pointerAccelerationType = client.getProperty(kIOHIDPointerAccelerationTypeKey) as String? {
                return pointerAccelerationType
            }

            // Guess the type...

            if (client.getProperty(kIOHIDPointerAccelerationKey) as IOFixed?) != nil {
                return kIOHIDPointerAccelerationKey
            }

            return kIOHIDMouseAccelerationTypeKey
        }

        set {
            client.setProperty(newValue, forKey: kIOHIDPointerAccelerationKey)
        }
    }

    var useLinearScalingMouseAcceleration: Int? {
        get {
            // TODO: Use `kIOHIDUseLinearScalingMouseAccelerationKey`.
            client.getProperty("HIDUseLinearScalingMouseAcceleration")
        }
        set {
            // TODO: Use `kIOHIDUseLinearScalingMouseAccelerationKey`.
            client.setProperty(newValue, forKey: "HIDUseLinearScalingMouseAcceleration")
        }
    }

    /**
     Indicates the pointer acceleration.

     This value is in the range [0, 20] ∪ { -1 }. -1 means acceleration and sensitivity are disabled.
     */
    var pointerAcceleration: Double? {
        get {
            if useLinearScalingMouseAcceleration == 1 {
                return -1
            }
            return client.getPropertyIOFixed(pointerAccelerationType ?? kIOHIDMouseAccelerationTypeKey)
        }

        set {
            client.setPropertyIOFixed(
                newValue.map { $0 == -1 ? $0 : $0.clamp(0, 20) },
                forKey: pointerAccelerationType ?? kIOHIDMouseAccelerationTypeKey
            )
        }
    }
}

// MARK: Observe input events

extension PointerDevice {
    private func inputValueCallback(_ value: IOHIDValue) {
        for (_, callback) in observations.inputValue {
            callback(self, value)
        }
    }

    public func observeInput(using closure: @escaping InputValueClosure) -> ObservationToken {
        let id = observations.inputValue.insert(closure)

        return ObservationToken { [weak self] in
            self?.observations.inputValue.removeValue(forKey: id)
        }
    }
}

// MARK: Observe input reports

extension PointerDevice {
    private func inputReportCallback(_ report: Data) {
        completePendingReportRequest(with: report)

        for (_, callback) in observations.inputReport {
            callback(self, report)
        }
    }

    private func completePendingReportRequest(with report: Data) {
        pendingReportRequestLock.lock()
        defer { pendingReportRequestLock.unlock() }

        guard let reportMatcher = pendingReportMatcher, reportMatcher(report) else {
            return
        }

        pendingReportResponse = report
        pendingReportMatcher = nil
        pendingReportSemaphore?.signal()
    }

    private func clearPendingReportRequest() {
        pendingReportMatcher = nil
        pendingReportResponse = nil
        pendingReportSemaphore = nil
    }

    func ensureInputReportCallbackRegistered(minimumReportLength: Int = 0) {
        guard let device else {
            return
        }

        let desiredReportLength = max(maxInputReportSize ?? 8, minimumReportLength, 8)
        if inputReportBufferLength < desiredReportLength {
            let newBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: desiredReportLength)
            inputReportBuffer?.deallocate()
            inputReportBuffer = newBuffer
            inputReportBufferLength = desiredReportLength
            inputReportCallbackRegistered = false
        }

        guard !inputReportCallbackRegistered, let inputReportBuffer else {
            return
        }

        let this = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            inputReportBuffer,
            inputReportBufferLength,
            Self.inputReportCallback,
            this
        )
        inputReportCallbackRegistered = true
    }

    public func performSynchronousOutputReportRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool
    ) -> Data? {
        guard let device, !report.isEmpty else {
            return nil
        }

        synchronousReportRequestLock.lock()
        defer { synchronousReportRequestLock.unlock() }

        ensureInputReportCallbackRegistered(minimumReportLength: max(report.count, maxInputReportSize ?? 0))

        let semaphore = DispatchSemaphore(value: 0)
        pendingReportRequestLock.lock()
        clearPendingReportRequest()
        pendingReportMatcher = matching
        pendingReportSemaphore = semaphore
        pendingReportRequestLock.unlock()

        let result = report.withUnsafeBytes { rawBuffer -> IOReturn in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return kIOReturnBadArgument
            }

            return IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(report[0]),
                baseAddress,
                report.count
            )
        }

        guard result == kIOReturnSuccess else {
            pendingReportRequestLock.lock()
            clearPendingReportRequest()
            pendingReportRequestLock.unlock()
            return nil
        }

        if Thread.isMainThread {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                pendingReportRequestLock.lock()
                let response = pendingReportResponse
                pendingReportRequestLock.unlock()

                if response != nil {
                    break
                }

                CFRunLoopRunInMode(.defaultMode, 0.01, true)
            }
        } else {
            _ = semaphore.wait(timeout: .now() + timeout)
        }

        pendingReportRequestLock.lock()
        let response = pendingReportResponse
        clearPendingReportRequest()
        pendingReportRequestLock.unlock()
        return response
    }

    public func observeReport(using closure: @escaping InputReportClosure) -> ObservationToken {
        ensureInputReportCallbackRegistered()

        let id = observations.inputReport.insert(closure)

        return ObservationToken { [weak self] in
            self?.observations.inputReport.removeValue(forKey: id)
        }
    }
}

// MARK: Utilities

public extension PointerDevice {
    func confirmsTo(_ usagePage: Int, _ usage: Int) -> Bool {
        IOHIDServiceClientConformsTo(client, UInt32(usagePage), UInt32(usage)) != 0
    }
}
