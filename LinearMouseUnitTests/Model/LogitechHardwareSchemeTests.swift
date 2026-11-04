// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

/// The settings UI and the apply path read the same hardware scheme, so the
/// "Reverse in the mouse" option shows and reads what the mouse is told.
final class LogitechHardwareSchemeTests: XCTestCase {
    private let receiver = DeviceMatcher(
        vendorID: 0x046D,
        productID: 0xC548,
        productName: "USB Receiver",
        serialNumber: nil,
        category: [.mouse]
    )

    private let mouse = DeviceMatcher(
        vendorID: 0x046D,
        productID: 0xB042,
        productName: "MX Master 4",
        serialNumber: "0001",
        category: [.mouse]
    )

    private var candidates: [DeviceMatcher] {
        [mouse, receiver]
    }

    func testMouseInheritsReverseInMouseFromItsReceiver() {
        let configuration = Configuration(schemes: [
            Scheme(
                if: [.init(device: receiver)],
                scrolling: .init(reverse: .init(vertical: true)),
                logitech: .init(invertWheel: true)
            ),
            Scheme(if: [.init(device: mouse)], logitech: .init(highResolutionWheel: false))
        ])

        let scheme = configuration.logitechHardwareScheme(forCandidates: candidates)

        XCTAssertEqual(scheme.logitech.invertWheel, true)
        XCTAssertEqual(scheme.managedLogitechWheelInvert, true)
    }

    func testMouseSchemeOverridesItsReceiver() {
        let configuration = Configuration(schemes: [
            Scheme(
                if: [.init(device: receiver)],
                scrolling: .init(reverse: .init(vertical: true)),
                logitech: .init(invertWheel: true)
            ),
            Scheme(if: [.init(device: mouse)], logitech: .init(invertWheel: false))
        ])

        let scheme = configuration.logitechHardwareScheme(forCandidates: candidates)

        XCTAssertEqual(scheme.logitech.invertWheel, false)
        XCTAssertNil(scheme.managedLogitechWheelInvert)
    }

    func testVerticalReverseComesFromSchemesForEveryAppAndDisplay() {
        let configuration = Configuration(schemes: [
            Scheme(
                if: [.init(device: DeviceMatcher(category: .mouse))],
                scrolling: .init(reverse: .init(vertical: true))
            ),
            Scheme(if: [.init(device: mouse)], logitech: .init(invertWheel: true)),
            Scheme(
                if: [.init(device: mouse, app: "com.example.app")],
                scrolling: .init(reverse: .init(vertical: false))
            ),
            Scheme(
                if: [.init(device: mouse, display: "External Display")],
                scrolling: .init(reverse: .init(vertical: false))
            )
        ])

        let scheme = configuration.logitechHardwareScheme(forCandidates: candidates)

        XCTAssertEqual(scheme.scrolling.reverse.vertical, true)
        XCTAssertEqual(scheme.managedLogitechWheelInvert, true)
    }

    func testReverseInMouseControlFollowsTheHardwareScheme() {
        var reversing = Scheme()
        reversing.scrolling.reverse.vertical = true

        XCTAssertTrue(shows(hardwareScheme: reversing))
        XCTAssertFalse(shows(hardwareScheme: Scheme()))
        XCTAssertFalse(shows(hardwareScheme: nil))
        XCTAssertFalse(shows(direction: .horizontal, hardwareScheme: reversing))
        XCTAssertFalse(shows(editsDeviceWideSettings: false, hardwareScheme: reversing))
        XCTAssertFalse(shows(supportsWheelInversion: false, hardwareScheme: reversing))
    }

    private func shows(
        direction: Scheme.Scrolling.BidirectionalDirection = .vertical,
        editsDeviceWideSettings: Bool = true,
        supportsWheelInversion: Bool = true,
        hardwareScheme: Scheme?
    ) -> Bool {
        ScrollingSettingsState.showsReverseInMouseControl(
            direction: direction,
            editsDeviceWideSettings: editsDeviceWideSettings,
            supportsWheelInversion: supportsWheelInversion,
            hardwareScheme: hardwareScheme
        )
    }
}
