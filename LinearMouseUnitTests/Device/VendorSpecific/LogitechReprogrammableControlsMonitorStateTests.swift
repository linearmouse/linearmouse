// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import PointerKit
import XCTest

final class LogitechReprogrammableControlsMonitorStateTests: XCTestCase {
    func testDisableCompletionWaitsForWorkerToFinish() {
        let state = LogitechReprogrammableControlsMonitorState()
        let workerStarted = expectation(description: "worker started")
        let allowWorkerToFinish = DispatchSemaphore(value: 0)
        let disableCompleted = DispatchSemaphore(value: 0)

        state.enable {
            Thread {
                workerStarted.fulfill()
                allowWorkerToFinish.wait()
                state.workerDidStop(restartIfEnabled: true) {
                    XCTFail("Disabled worker must not restart")
                    return Thread {}
                }
            }
        }

        wait(for: [workerStarted], timeout: 1)
        state.disable {
            disableCompleted.signal()
        }

        XCTAssertEqual(disableCompleted.wait(timeout: .now() + 0.05), .timedOut)

        allowWorkerToFinish.signal()
        XCTAssertEqual(disableCompleted.wait(timeout: .now() + 1), .success)
    }

    func testDisableCompletesImmediatelyWithoutWorker() {
        let state = LogitechReprogrammableControlsMonitorState()
        let disableCompleted = expectation(description: "disable completed")

        state.disable {
            disableCompleted.fulfill()
        }

        wait(for: [disableCompleted], timeout: 0.1)
    }
}

final class LogitechReprogrammableControlsReportingTests: XCTestCase {
    func testNativeRestorationClearsExistingDiversion() throws {
        let device = MockVendorSpecificDeviceContext(
            vendorID: 0x046D,
            productID: 0xC548,
            transport: PointerDeviceTransportName.usb
        )
        var isDiverted = true
        device.responseProvider = { report in
            let bytes = [UInt8](report)
            guard bytes.count >= 9 else {
                return nil
            }

            switch bytes[3] {
            case 0x38:
                XCTAssertEqual(Array(bytes[4 ... 8]), [0x00, 0xC3, 0x02, 0x00, 0x00])
                isDiverted = false
                return Self.hidppLongReply(
                    deviceIndex: bytes[1],
                    featureIndex: bytes[2],
                    address: bytes[3],
                    payload: [0x00, 0xC3]
                )
            case 0x28:
                return Self.hidppLongReply(
                    deviceIndex: bytes[1],
                    featureIndex: bytes[2],
                    address: bytes[3],
                    payload: [0x00, 0xC3, isDiverted ? 0x01 : 0x00, 0x00, 0xC3, 0x00]
                )
            default:
                return nil
            }
        }

        let transport = try XCTUnwrap(LogitechHIDPPTransport(device: device, deviceIndex: 2))
        let failures = LogitechReprogrammableControlsMonitor.restoreNativeReporting(
            for: [0x00C3],
            using: transport,
            featureIndex: 0x1B,
            locationID: 1,
            slot: 2,
            reason: "test native restoration"
        )

        XCTAssertTrue(failures.isEmpty)
        XCTAssertFalse(isDiverted)
        XCTAssertEqual(device.sentReports.count, 2)
    }

    private static func hidppLongReply(
        deviceIndex: UInt8,
        featureIndex: UInt8,
        address: UInt8,
        payload: [UInt8]
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = 0x11
        bytes[1] = deviceIndex
        bytes[2] = featureIndex
        bytes[3] = address
        for (index, byte) in payload.enumerated() where index + 4 < bytes.count {
            bytes[index + 4] = byte
        }
        return Data(bytes)
    }
}
