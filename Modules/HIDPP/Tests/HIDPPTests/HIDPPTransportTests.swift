// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
@testable import HIDPP
import XCTest

final class HIDPPTransportTests: XCTestCase {
    func testRejectsDeviceWithoutSupportedReportSize() {
        XCTAssertNil(HIDPPTransport(device: MockHIDPPDevice(maxOutputReportSize: 6), deviceIndex: nil))
    }

    func testBuildsLongDirectDeviceRequestAndParsesResponse() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { _ in
            Data([0x11, 0xFF, 0x22, 0x38, 0xAA, 0xBB, 0xCC])
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))

        let response = transport.request(featureIndex: 0x22, function: 0x03, parameters: [0x01, 0x02])

        XCTAssertEqual(response?.payload, [0xAA, 0xBB, 0xCC])
        XCTAssertEqual(Array(device.reports[0].prefix(6)), [0x11, 0xFF, 0x22, 0x38, 0x01, 0x02])
        XCTAssertEqual(device.reports[0].count, HIDPPConstants.longReportLength)
        XCTAssertNil(transport.receiverSlot)
        XCTAssertFalse(transport.isReceiverRoutedDevice)
    }

    func testRoutesRequestThroughReceiverSlot() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { _ in
            Data([0x11, 0x02, 0x22, 0x18, 0x01, 0x00, 0x00])
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: 0x02))

        XCTAssertNotNil(transport.request(featureIndex: 0x22, function: 0x01, parameters: []))
        XCTAssertEqual([UInt8](device.reports[0])[1], 0x02)
        XCTAssertEqual(transport.receiverSlot, 0x02)
        XCTAssertTrue(transport.isReceiverRoutedDevice)
    }

    func testRetriesOnlyBusyResponses() throws {
        let device = MockHIDPPDevice()
        var attempt = 0
        device.responseProvider = { _ in
            attempt += 1
            if attempt == 1 {
                return Data([0x11, 0xFF, 0xFF, 0x22, 0x18, 0x08, 0x00])
            }
            return Data([0x11, 0xFF, 0x22, 0x18, 0x01, 0x00, 0x00])
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))

        XCTAssertNotNil(transport.request(featureIndex: 0x22, function: 0x01, parameters: []))
        XCTAssertEqual(device.regularRequestCount, 2)
    }

    func testRequestOnceUsesSingleTransactionIO() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { _ in
            Data([0x11, 0xFF, 0x22, 0x38, 0x01, 0x00, 0x00])
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))

        XCTAssertNotNil(transport.requestOnce(featureIndex: 0x22, function: 0x03, parameters: []))
        XCTAssertEqual(device.singleTransactionRequestCount, 1)
        XCTAssertEqual(device.regularRequestCount, 0)
    }

    func testResolvesFeatureIndex() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            XCTAssertEqual(Array(bytes[4 ... 5]), [0x22, 0x01])
            return Data([0x11, 0xFF, 0x00, 0x08, 0x2A, 0x00, 0x00])
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))

        XCTAssertEqual(transport.featureIndex(for: .adjustableDPI), 0x2A)
    }

    func testCancellationStopsRequestBeforeIO() throws {
        let device = MockHIDPPDevice()
        let transport = try XCTUnwrap(HIDPPTransport(
            device: device,
            deviceIndex: nil
        ) { false })

        XCTAssertNil(transport.request(featureIndex: 0x22, function: 0x01, parameters: []))
        XCTAssertTrue(device.reports.isEmpty)
    }

    func testRequestDeadlineCapsRegularAndSingleTransactionTimeouts() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            return Data([0x11, 0xFF, bytes[2], bytes[3], 0x01, 0x00, 0x00])
        }
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))
        let deadline = Date().addingTimeInterval(0.2)

        XCTAssertNotNil(transport.request(
            featureIndex: 0x22,
            function: 0x01,
            parameters: [],
            deadline: deadline
        ) { true })
        XCTAssertNotNil(transport.requestOnce(
            featureIndex: 0x22,
            function: 0x03,
            parameters: [],
            deadline: deadline
        ) { true })

        XCTAssertEqual(device.requestTimeouts.count, 1)
        XCTAssertEqual(device.singleTransactionRequestTimeouts.count, 1)
        XCTAssertGreaterThan(device.requestTimeouts[0], 0)
        XCTAssertLessThanOrEqual(device.requestTimeouts[0], 0.2 + 1e-6)
        XCTAssertGreaterThan(device.singleTransactionRequestTimeouts[0], 0)
        XCTAssertLessThanOrEqual(device.singleTransactionRequestTimeouts[0], device.requestTimeouts[0])
    }

    func testExpiredRequestDeadlinePreventsIO() throws {
        let device = MockHIDPPDevice()
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))

        XCTAssertNil(transport.request(
            featureIndex: 0x22,
            function: 0x01,
            parameters: [],
            deadline: Date(timeIntervalSinceNow: -1)
        ) { true })
        XCTAssertTrue(device.reports.isEmpty)
    }

    func testTransportDeadlineCapsEveryRequest() throws {
        let device = MockHIDPPDevice()
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            return Data([0x11, 0xFF, bytes[2], bytes[3], 0x01, 0x00, 0x00])
        }
        let transport = try XCTUnwrap(HIDPPTransport(
            device: device,
            deviceIndex: nil,
            deadline: Date().addingTimeInterval(0.1)
        ))

        XCTAssertNotNil(transport.request(
            featureIndex: 0x22,
            function: 0x01,
            parameters: []
        ))
        XCTAssertEqual(device.requestTimeouts.count, 1)
        XCTAssertGreaterThan(device.requestTimeouts[0], 0)
        XCTAssertLessThanOrEqual(device.requestTimeouts[0], 0.1 + 1e-6)
    }

    func testRejectsParametersThatDoNotFitReportWithoutSendingIO() throws {
        let device = MockHIDPPDevice(maxOutputReportSize: HIDPPConstants.shortReportLength)
        let transport = try XCTUnwrap(HIDPPTransport(device: device, deviceIndex: nil))

        XCTAssertNil(transport.request(
            featureIndex: 0x22,
            function: 0x01,
            parameters: [0x00, 0x01, 0x02, 0x03]
        ))
        XCTAssertTrue(device.reports.isEmpty)
        XCTAssertEqual(device.regularRequestCount, 0)
    }
}
