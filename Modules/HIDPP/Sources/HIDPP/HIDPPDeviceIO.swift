// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// The report-level I/O required by HID++. Platform-specific device wrappers
/// provide this interface without leaking their discovery or UI models into
/// the protocol module.
public protocol HIDPPDeviceIO {
    var maxOutputReportSize: Int? { get }

    func performSynchronousOutputReportRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool
    ) -> Data?

    func performSynchronousOutputReportRequestOnce(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool
    ) -> Data?
}

/// Optional I/O extension for transports that can stop an in-flight request
/// when its owning device disappears or a newer route supersedes it.
public protocol HIDPPCancellableDeviceIO: HIDPPDeviceIO {
    func performSynchronousOutputReportRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        until shouldContinue: @escaping () -> Bool
    ) -> Data?

    func performSynchronousOutputReportRequestOnce(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        until shouldContinue: @escaping () -> Bool
    ) -> Data?
}

public extension HIDPPDeviceIO {
    func performSynchronousOutputReportRequestOnce(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool
    ) -> Data? {
        performSynchronousOutputReportRequest(report, timeout: timeout, matching: matching)
    }
}
