// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
@testable import LinearMouse

final class MockVendorSpecificDeviceContext: LogitechReceiverMonitoringChannel {
    var vendorID: Int?
    var productID: Int?
    var product: String?
    var name: String
    var serialNumber: String?
    var transport: String?
    var locationID: Int?
    var primaryUsagePage: Int?
    var primaryUsage: Int?
    var maxInputReportSize: Int?
    var maxOutputReportSize: Int?
    var maxFeatureReportSize: Int?
    var outputReportRequestCount = 0
    var outputReportRequestOnceCount = 0
    var sentReports = [Data]()
    var responseProvider: ((Data) -> Data?)?
    var wirelessNotificationEnableCount = 0
    var queuedHIDPPNotifications = [[UInt8]]()

    init(
        vendorID: Int?,
        productID: Int?,
        product: String? = nil,
        name: String = "Mock Device",
        serialNumber: String? = nil,
        transport: String?,
        locationID: Int? = nil,
        primaryUsagePage: Int? = nil,
        primaryUsage: Int? = nil,
        maxInputReportSize: Int? = 20,
        maxOutputReportSize: Int? = 20,
        maxFeatureReportSize: Int? = 20
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.product = product
        self.name = name
        self.serialNumber = serialNumber
        self.transport = transport
        self.locationID = locationID
        self.primaryUsagePage = primaryUsagePage
        self.primaryUsage = primaryUsage
        self.maxInputReportSize = maxInputReportSize
        self.maxOutputReportSize = maxOutputReportSize
        self.maxFeatureReportSize = maxFeatureReportSize
    }

    func performSynchronousOutputReportRequest(
        _ report: Data,
        timeout _: TimeInterval,
        matching: @escaping (Data) -> Bool
    ) -> Data? {
        outputReportRequestCount += 1
        sentReports.append(report)
        guard let response = responseProvider?(report),
              matching(response) else {
            return nil
        }
        return response
    }

    func performSynchronousOutputReportRequestOnce(
        _ report: Data,
        timeout _: TimeInterval,
        matching: @escaping (Data) -> Bool
    ) -> Data? {
        outputReportRequestOnceCount += 1
        sentReports.append(report)
        guard let response = responseProvider?(report),
              matching(response) else {
            return nil
        }
        return response
    }

    func enableWirelessNotifications() {
        wirelessNotificationEnableCount += 1
    }

    func waitForReceiverConnectionNotification(
        timeout: TimeInterval,
        until shouldContinue: (() -> Bool)?
    ) -> (slot: UInt8, snapshot: LogitechHIDPPDeviceMetadataProvider.ReceiverConnectionSnapshot)? {
        guard shouldContinue?() ?? true else {
            return nil
        }

        if let index = queuedHIDPPNotifications.firstIndex(where: {
            LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification($0) != nil
        }) {
            let report = queuedHIDPPNotifications.remove(at: index)
            return LogitechHIDPPDeviceMetadataProvider.parseReceiverConnectionNotification(report)
        }

        if timeout > 0 {
            Thread.sleep(forTimeInterval: timeout)
        }
        return nil
    }
}
