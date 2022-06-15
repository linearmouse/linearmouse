// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

@testable import PointerKit
import XCTest

class PointerDeviceManagerTest: XCTestCase {
    class Scope {}

    struct WeakRef<T: AnyObject> {
        weak var value: T?
    }

    func testStartStop() throws {
        var tokenRef = WeakRef<PointerDeviceManager.ObservationToken>()

        do {
            let manager = PointerDeviceManager()

            // Tieing to manager itself would cause a reference cycle
            let scope = Scope()

            DispatchQueue.main.async {
                tokenRef.value = manager.observeDeviceAdded { manager, device in
                    debugPrint("device added", manager, device)
                }.tieToLifetime(of: scope)

                manager.observeDeviceRemoved { manager, device in
                    debugPrint("device removed", manager, device)
                }.tieToLifetime(of: scope)

                manager.startObservation()
            }

            DispatchQueue.main.async {
                manager.stopObservation()

                debugPrint("stopped")

                Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
                    debugPrint("restarted")

                    manager.startObservation()
                }
            }

            CFRunLoopRunInMode(.defaultMode, 10, false)

            XCTAssertNotNil(tokenRef.value)
        }

        XCTAssertNil(tokenRef.value)
    }

    func testPointerResolutionAndPointerAcceleration() {
        let manager = PointerDeviceManager()

        manager.startObservation()

        DispatchQueue.main.async {
            for device in manager.devices {
                print("Device:", device.name)
                print("Pointer resolution:", device.pointerResolution ?? "(null)")
                print("Pointer acceleration type:", device.pointerAccelerationType ?? "(null)")
                print("Pointer acceleration:", device.pointerAcceleration ?? "(null)")
                print("==========================")
            }
        }

        CFRunLoopRunInMode(.defaultMode, 10, true)
    }
}
