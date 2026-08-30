// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import ObservationToken
import PointerKitC

/// Runs a report request while holding the per-device request gate. The
/// cancellation check happens after `defer` is installed, so a cancellation
/// racing with acquisition cannot leak a permit.
func withSynchronousReportRequestGate(
    until shouldContinue: () -> Bool,
    acquirePermit: () -> Bool,
    releasePermit: () -> Void,
    perform operation: () -> Data?
) -> Data? {
    while shouldContinue() {
        guard acquirePermit() else {
            continue
        }
        defer { releasePermit() }

        guard shouldContinue() else {
            return nil
        }

        return operation()
    }

    return nil
}

/// Performs one report send after a short admission check.
///
/// Admission is deliberately complete before `send` starts. Once admitted, the
/// synchronous IOKit call is committed and may outlive logical invalidation;
/// invalidation must remain free to revoke later requests without waiting for
/// that external call to return.
func performAdmittedSynchronousReportSend<Result>(
    admission: () -> Bool,
    send: () -> Result
) -> Result? {
    guard admission() else {
        return nil
    }
    return send()
}

/// A sent HID request owns its matcher until a matching response, device
/// invalidation, or the request deadline. Cancellation controls whether its
/// result is returned; it cannot make a late response belong to the next
/// request.
func settleCommittedSynchronousReportRequest(
    until deadline: Date,
    shouldDeliverResult: () -> Bool,
    isTransportValid: () -> Bool,
    wait: (TimeInterval) -> Void,
    response: () -> Data?
) -> Data? {
    while Date() < deadline {
        if let response = response() {
            return shouldDeliverResult() ? response : nil
        }
        guard isTransportValid() else {
            return nil
        }

        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else {
            break
        }
        wait(min(remaining, 0.01))
    }

    guard let response = response() else {
        return nil
    }
    return shouldDeliverResult() ? response : nil
}

/// Common IOHID transport names.
/// This is a shared string namespace, not an exhaustive transport model.
public enum PointerDeviceTransportName {
    public static let usb = "USB"
    public static let bluetooth = "Bluetooth"
    public static let bluetoothLowEnergy = "Bluetooth Low Energy"
}

/// The run-loop mode used for every asynchronous `IOHIDDevice` callback.
///
/// AppKit switches the main run loop to its modal mode after an application
/// returns `terminateLater`. Scheduling in the common modes keeps HID replies
/// flowing during that bounded termination window. A single policy value is
/// shared by scheduling and unscheduling so the two operations cannot drift.
struct PointerDeviceRunLoopScheduling {
    static let inputCallbacks = Self(mode: .commonModes)

    let mode: CFRunLoopMode
}

public class PointerDevice {
    let client: IOHIDServiceClient
    let device: IOHIDDevice?
    private let runLoop: CFRunLoop

    private let stateLock = NSLock()
    private var isValid = true

    private let productValue: String?
    private let vendorIDValue: Int?
    private let productIDValue: Int?
    private let serialNumberValue: String?
    private let buttonCountValue: Int?
    private let locationIDValue: Int?
    private let primaryUsagePageValue: Int?
    private let primaryUsageValue: Int?
    private let maxInputReportSizeValue: Int?
    private let maxOutputReportSizeValue: Int?
    private let maxFeatureReportSizeValue: Int?
    private let transportValue: String?

    public typealias InputValueClosure = (PointerDevice, IOHIDValue) -> Void
    public typealias InputReportClosure = (PointerDevice, Data) -> Void

    private let inputReportRegistrationLock = NSLock()
    private var inputReportCallbackRegistered = false
    private var inputReportBuffer: UnsafeMutablePointer<UInt8>?
    private var inputReportBufferLength = 0

    /// Serializes HID++ transactions. A request that already sent a report
    /// retains ownership until it settles, so a late reply cannot be matched
    /// to its successor.
    private let synchronousReportRequestGate = DispatchSemaphore(value: 1)
    private let pendingReportRequestLock = NSLock()
    private var pendingReportMatcher: ((Data) -> Bool)?
    private var pendingReportResponse: Data?
    private var pendingReportSemaphore: DispatchSemaphore?

    private let observationsLock = NSLock()
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
        let device = client.device
        self.device = device
        runLoop = CFRunLoopGetCurrent()
        productValue = Self.getStaticProperty(kIOHIDProductKey, client: client, device: device)
        vendorIDValue = Self.getStaticProperty(kIOHIDVendorIDKey, client: client, device: device)
        productIDValue = Self.getStaticProperty(kIOHIDProductIDKey, client: client, device: device)
        serialNumberValue = Self.getStaticProperty(kIOHIDSerialNumberKey, client: client, device: device)
        buttonCountValue = Self.getStaticProperty(kIOHIDPointerButtonCountKey, client: client, device: device)
        locationIDValue = Self.getStaticProperty("LocationID", client: client, device: device)
        primaryUsagePageValue = Self.getStaticProperty("PrimaryUsagePage", client: client, device: device)
        primaryUsageValue = Self.getStaticProperty("PrimaryUsage", client: client, device: device)
        maxInputReportSizeValue = Self.getStaticProperty("MaxInputReportSize", client: client, device: device)
        maxOutputReportSizeValue = Self.getStaticProperty("MaxOutputReportSize", client: client, device: device)
        maxFeatureReportSizeValue = Self.getStaticProperty("MaxFeatureReportSize", client: client, device: device)
        transportValue = Self.getStaticProperty("Transport", client: client, device: device)

        if let device {
            IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDDeviceSetInputValueMatching(device, nil)
            let this = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputValueCallback(device, Self.inputValueCallback, this)
            IOHIDDeviceScheduleWithRunLoop(
                device,
                runLoop,
                PointerDeviceRunLoopScheduling.inputCallbacks.mode.rawValue
            )
        }
    }

    private static func getStaticProperty<T>(
        _ key: String,
        client: IOHIDServiceClient,
        device: IOHIDDevice?
    ) -> T? {
        if let valueRef = device.flatMap({ IOHIDDeviceGetProperty($0, key as CFString) }),
           let value = valueRef as? T {
            return value
        }

        return client.getProperty(key)
    }

    deinit {
        invalidate()

        if let device {
            IOHIDDeviceUnscheduleFromRunLoop(
                device,
                runLoop,
                PointerDeviceRunLoopScheduling.inputCallbacks.mode.rawValue
            )
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        inputReportBuffer?.deallocate()
    }

    func invalidate() {
        stateLock.lock()
        isValid = false
        stateLock.unlock()

        unregisterInputCallbacks()

        pendingReportRequestLock.lock()
        let semaphore = pendingReportSemaphore
        clearPendingReportRequest()
        pendingReportRequestLock.unlock()
        semaphore?.signal()
    }

    private var valid: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isValid
    }

    private func getDynamicProperty<T>(_ key: String) -> T? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard isValid else {
            return nil
        }

        return client.getProperty(key)
    }

    private func setDynamicProperty<T>(_ value: T, forKey key: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard isValid else {
            return
        }

        client.setProperty(value, forKey: key)
    }

    private func getDynamicPropertyIOFixed(_ key: String) -> Double? {
        (getDynamicProperty(key) as IOFixed?).map { Double($0) / 65_536 }
    }

    private func setDynamicPropertyIOFixed(_ value: Double?, forKey key: String) {
        setDynamicProperty(value.map { IOFixed($0 * 65_536) }, forKey: key)
    }

    private func unregisterInputCallbacks() {
        guard let device else {
            return
        }

        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)

        inputReportRegistrationLock.lock()
        unregisterInputReportCallbackLocked()
        inputReportRegistrationLock.unlock()
    }

    private func unregisterInputReportCallbackLocked() {
        guard inputReportCallbackRegistered,
              let device,
              let inputReportBuffer
        else {
            return
        }

        IOHIDDeviceRegisterInputReportCallback(
            device,
            inputReportBuffer,
            inputReportBufferLength,
            nil,
            nil
        )
        inputReportCallbackRegistered = false
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
        productValue
    }

    var name: String {
        product ?? "(unknown)"
    }

    var vendorID: Int? {
        vendorIDValue
    }

    var productID: Int? {
        productIDValue
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
        serialNumberValue
    }

    var buttonCount: Int? {
        buttonCountValue
    }

    var locationID: Int? {
        locationIDValue
    }

    var primaryUsagePage: Int? {
        primaryUsagePageValue
    }

    var primaryUsage: Int? {
        primaryUsageValue
    }

    var maxInputReportSize: Int? {
        maxInputReportSizeValue
    }

    var maxOutputReportSize: Int? {
        maxOutputReportSizeValue
    }

    var maxFeatureReportSize: Int? {
        maxFeatureReportSizeValue
    }

    var transport: String? {
        transportValue
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
        get { getDynamicPropertyIOFixed(kIOHIDPointerResolutionKey) }

        set {
            setDynamicPropertyIOFixed(newValue.map { $0.clamp(10, 1995) }, forKey: kIOHIDPointerResolutionKey)

            // HACK: Trigger a `pointerAcceleration` change to make `pointerResolution` take affect
            pointerAcceleration = pointerAcceleration
        }
    }

    var pointerAccelerationType: String? {
        get {
            if let pointerAccelerationType = getDynamicProperty(kIOHIDPointerAccelerationTypeKey) as String? {
                return pointerAccelerationType
            }

            // Guess the type...

            if (getDynamicProperty(kIOHIDPointerAccelerationKey) as IOFixed?) != nil {
                return kIOHIDPointerAccelerationKey
            }

            return kIOHIDMouseAccelerationTypeKey
        }

        set {
            setDynamicProperty(newValue, forKey: kIOHIDPointerAccelerationKey)
        }
    }

    var useLinearScalingMouseAcceleration: Int? {
        get {
            // TODO: Use `kIOHIDUseLinearScalingMouseAccelerationKey`.
            getDynamicProperty("HIDUseLinearScalingMouseAcceleration")
        }
        set {
            // TODO: Use `kIOHIDUseLinearScalingMouseAccelerationKey`.
            setDynamicProperty(newValue, forKey: "HIDUseLinearScalingMouseAcceleration")
        }
    }

    /**
     Indicates the pointer acceleration.

     This value is in the range [0, 40] ∪ { -1 }. -1 means acceleration and sensitivity are disabled.
     */
    var pointerAcceleration: Double? {
        get {
            if useLinearScalingMouseAcceleration == 1 {
                return -1
            }
            return getDynamicPropertyIOFixed(pointerAccelerationType ?? kIOHIDMouseAccelerationTypeKey)
        }

        set {
            setDynamicPropertyIOFixed(
                newValue.map { $0 == -1 ? $0 : $0.clamp(0, 40) },
                forKey: pointerAccelerationType ?? kIOHIDMouseAccelerationTypeKey
            )
        }
    }
}

// MARK: Observe input events

extension PointerDevice {
    private func inputValueCallback(_ value: IOHIDValue) {
        guard valid else {
            return
        }

        let callbacks = inputValueCallbacks()
        for callback in callbacks {
            callback(self, value)
        }
    }

    public func observeInput(using closure: @escaping InputValueClosure) -> ObservationToken {
        observationsLock.lock()
        let id = observations.inputValue.insert(closure)
        observationsLock.unlock()

        return ObservationToken { [weak self] in
            guard let self else {
                return
            }

            observationsLock.lock()
            observations.inputValue.removeValue(forKey: id)
            observationsLock.unlock()
        }
    }

    private func inputValueCallbacks() -> [InputValueClosure] {
        observationsLock.lock()
        defer { observationsLock.unlock() }
        return Array(observations.inputValue.values)
    }
}

// MARK: Observe input reports

extension PointerDevice {
    private func inputReportCallback(_ report: Data) {
        guard valid else {
            return
        }

        completePendingReportRequest(with: report)

        let callbacks = inputReportCallbacks()
        for callback in callbacks {
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

    @discardableResult
    func ensureInputReportCallbackRegistered(minimumReportLength: Int = 0) -> Bool {
        inputReportRegistrationLock.lock()
        defer { inputReportRegistrationLock.unlock() }

        guard valid, let device else {
            return false
        }

        let desiredReportLength = max(maxInputReportSize ?? 8, minimumReportLength, 8)
        if inputReportBufferLength < desiredReportLength {
            unregisterInputReportCallbackLocked()
            let newBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: desiredReportLength)
            inputReportBuffer?.deallocate()
            inputReportBuffer = newBuffer
            inputReportBufferLength = desiredReportLength
        }

        guard !inputReportCallbackRegistered, let inputReportBuffer else {
            return true
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
        return true
    }

    public func performSynchronousOutputReportRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool
    ) -> Data? {
        performSynchronousOutputReportRequest(
            report,
            timeout: timeout,
            matching: matching
        ) { true }
    }

    public func performSynchronousOutputReportRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        until shouldContinue: @escaping () -> Bool
    ) -> Data? {
        guard let device, !report.isEmpty, valid else {
            return nil
        }
        let deadline = Date().addingTimeInterval(timeout)
        let requestShouldContinue = {
            shouldContinue() && Date() < deadline
        }

        return withSynchronousReportRequestGate(
            until: requestShouldContinue,
            acquirePermit: {
                self.acquireSynchronousReportRequestPermit()
            },
            releasePermit: {
                self.synchronousReportRequestGate.signal()
            }
        ) {
            guard requestShouldContinue() else {
                return nil
            }
            guard ensureInputReportCallbackRegistered(minimumReportLength: max(report.count, maxInputReportSize ?? 0)),
                  valid
            else {
                return nil
            }

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

                guard requestShouldContinue() else {
                    return kIOReturnNotOpen
                }

                return performAdmittedSynchronousReportSend(
                    admission: {
                        self.stateLock.withLock { self.isValid }
                            && requestShouldContinue()
                    },
                    send: {
                        IOHIDDeviceSetReport(
                            device,
                            kIOHIDReportTypeOutput,
                            CFIndex(report[0]),
                            baseAddress,
                            report.count
                        )
                    }
                ) ?? kIOReturnNotOpen
            }

            guard result == kIOReturnSuccess else {
                pendingReportRequestLock.lock()
                clearPendingReportRequest()
                pendingReportRequestLock.unlock()
                return nil
            }

            let waitForResponse: (TimeInterval) -> Void
            if CFEqual(CFRunLoopGetCurrent(), runLoop) {
                waitForResponse = { interval in
                    _ = CFRunLoopRunInMode(.defaultMode, interval, true)
                }
            } else {
                waitForResponse = { interval in
                    _ = semaphore.wait(timeout: .now() + interval)
                }
            }

            defer {
                pendingReportRequestLock.lock()
                clearPendingReportRequest()
                pendingReportRequestLock.unlock()
            }
            return settleCommittedSynchronousReportRequest(
                until: deadline,
                shouldDeliverResult: {
                    requestShouldContinue() && self.valid
                },
                isTransportValid: { self.valid },
                wait: waitForResponse
            ) {
                self.pendingReportRequestLock.lock()
                let response = self.pendingReportResponse
                self.pendingReportRequestLock.unlock()
                return response
            }
        }
    }

    private func acquireSynchronousReportRequestPermit() -> Bool {
        if synchronousReportRequestGate.wait(timeout: .now()) == .success {
            return true
        }

        if CFEqual(CFRunLoopGetCurrent(), runLoop) {
            // A background request can hold the gate while waiting for an
            // input-report callback on this run loop. Process one turn before
            // retrying instead of blocking the callback that releases it.
            _ = CFRunLoopRunInMode(.defaultMode, 0.01, true)
            return false
        }

        return synchronousReportRequestGate.wait(timeout: .now() + 0.01) == .success
    }

    public func performSynchronousOutputReportRequestOnce(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        until shouldContinue: @escaping () -> Bool
    ) -> Data? {
        performSynchronousOutputReportRequest(
            report,
            timeout: timeout,
            matching: matching,
            until: shouldContinue
        )
    }

    public func observeReport(using closure: @escaping InputReportClosure) -> ObservationToken {
        guard ensureInputReportCallbackRegistered() else {
            return ObservationToken {}
        }

        observationsLock.lock()
        let id = observations.inputReport.insert(closure)
        observationsLock.unlock()

        return ObservationToken { [weak self] in
            guard let self else {
                return
            }

            observationsLock.lock()
            observations.inputReport.removeValue(forKey: id)
            observationsLock.unlock()
        }
    }

    private func inputReportCallbacks() -> [InputReportClosure] {
        observationsLock.lock()
        defer { observationsLock.unlock() }
        return Array(observations.inputReport.values)
    }
}

// MARK: Utilities

public extension PointerDevice {
    func confirmsTo(_ usagePage: Int, _ usage: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard isValid else {
            return false
        }

        return IOHIDServiceClientConformsTo(client, UInt32(usagePage), UInt32(usage)) != 0
    }
}
