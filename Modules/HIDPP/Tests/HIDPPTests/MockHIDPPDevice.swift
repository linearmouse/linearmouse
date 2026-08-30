// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
import HIDPP

final class MockHIDPPDevice: HIDPPCancellableDeviceIO {
    let maxOutputReportSize: Int?
    var responseProvider: ((Data) -> Data?)?

    private(set) var reports = [Data]()
    private(set) var regularRequestCount = 0
    private(set) var singleTransactionRequestCount = 0
    private(set) var requestTimeouts = [TimeInterval]()
    private(set) var singleTransactionRequestTimeouts = [TimeInterval]()

    init(maxOutputReportSize: Int? = HIDPPConstants.longReportLength) {
        self.maxOutputReportSize = maxOutputReportSize
    }

    func performSynchronousOutputReportRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool
    ) -> Data? {
        regularRequestCount += 1
        requestTimeouts.append(timeout)
        return response(to: report, matching: matching)
    }

    func performSynchronousOutputReportRequestOnce(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool
    ) -> Data? {
        singleTransactionRequestCount += 1
        singleTransactionRequestTimeouts.append(timeout)
        return response(to: report, matching: matching)
    }

    func performSynchronousOutputReportRequest(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        until shouldContinue: @escaping () -> Bool
    ) -> Data? {
        guard shouldContinue() else {
            return nil
        }

        regularRequestCount += 1
        requestTimeouts.append(timeout)
        return response(to: report, matching: matching)
    }

    func performSynchronousOutputReportRequestOnce(
        _ report: Data,
        timeout: TimeInterval,
        matching: @escaping (Data) -> Bool,
        until shouldContinue: @escaping () -> Bool
    ) -> Data? {
        guard shouldContinue() else {
            return nil
        }

        singleTransactionRequestCount += 1
        singleTransactionRequestTimeouts.append(timeout)
        return response(to: report, matching: matching)
    }

    private func response(to report: Data, matching: (Data) -> Bool) -> Data? {
        reports.append(report)
        guard let response = responseProvider?(report), matching(response) else {
            return nil
        }

        return response
    }
}
