// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

/// A device behind a receiver is matched by its own identity first and by the
/// receiver second, so schemes follow the mouse across connections while
/// schemes written for the receiver keep applying.
final class DeviceMatcherCandidatesTests: XCTestCase {
    private let receiver = DeviceMatcher(
        vendorID: 0x046D,
        productID: 0xC548,
        productName: "USB Receiver",
        serialNumber: nil,
        category: [.mouse]
    )

    private func mouse(productID: Int, serialNumber: String, name: String = "MX Master 4") -> DeviceMatcher {
        DeviceMatcher(
            vendorID: 0x046D,
            productID: productID,
            productName: name,
            serialNumber: serialNumber,
            category: [.mouse]
        )
    }

    private func context(_ devices: [DeviceMatcher]) -> Scheme.MatchContext {
        var context = Scheme.MatchContext()
        context.devices = devices
        return context
    }

    private func reverseScheme(for device: DeviceMatcher, vertical: Bool) -> Scheme {
        Scheme(if: [.init(device: device)], scrolling: .init(reverse: .init(vertical: vertical)))
    }

    func testSchemeWrittenOverBluetoothAppliesThroughReceiver() {
        let bluetooth = mouse(productID: 0xB042, serialNumber: "11D5D259")
        let scheme = reverseScheme(for: bluetooth, vertical: true)
        let throughReceiver = context([mouse(productID: 0xB042, serialNumber: "11D5D259"), receiver])

        XCTAssertTrue(scheme.isActive(in: throughReceiver))
    }

    func testSchemeCreatedThroughReceiverAppliesOverBluetoothDespiteDifferentName() {
        let throughReceiver = mouse(productID: 0xB042, serialNumber: "11D5D259", name: "MX Master 4")
        let scheme = reverseScheme(for: throughReceiver.condition, vertical: true)
        let bluetooth = context([mouse(productID: 0xB042, serialNumber: "11D5D259", name: "MX Master 4 Mac")])

        XCTAssertNil(throughReceiver.condition.productName)
        XCTAssertTrue(scheme.isActive(in: bluetooth))
    }

    func testConditionKeepsNameWithoutStableIdentifiers() {
        var matcher = receiver
        matcher.serialNumber = nil
        XCTAssertEqual(matcher.condition, receiver)
    }

    func testConditionKeepsNameForOtherVendors() {
        // Generic devices may share a product ID and a fixed serial number.
        let generic = DeviceMatcher(
            vendorID: 0x1234,
            productID: 0x5678,
            productName: "Generic Mouse",
            serialNumber: "0001",
            category: [.mouse]
        )
        XCTAssertEqual(generic.condition, generic)
    }

    func testFirstMouseSchemeGoesBetweenReceiverAndReceiverAppSchemes() {
        let schemes = [
            Scheme(if: [.init(device: receiver)]),
            Scheme(if: [.init(device: receiver, app: "com.apple.Safari")])
        ]

        XCTAssertEqual(schemes.insertionIndex(ofDeviceWideSchemeBehind: receiver), 1)
        XCTAssertEqual(Array(schemes.prefix(1)).insertionIndex(ofDeviceWideSchemeBehind: receiver), 1)
        XCTAssertEqual([Scheme]().insertionIndex(ofDeviceWideSchemeBehind: receiver), 0)

        // An app scheme before the receiver's device-wide scheme does not pull it earlier.
        let reordered = [schemes[1], schemes[0]]
        XCTAssertEqual(reordered.insertionIndex(ofDeviceWideSchemeBehind: receiver), 2)
    }

    func testReceiverSchemeKeepsApplyingToDevicesBehindIt() {
        let scheme = reverseScheme(for: receiver, vertical: true)

        XCTAssertTrue(scheme.isActive(in: context([mouse(productID: 0xB042, serialNumber: "A"), receiver])))
        XCTAssertTrue(scheme.isActive(in: context([receiver])))
    }

    func testOtherMouseOnSameReceiverDoesNotMatch() {
        let scheme = reverseScheme(for: mouse(productID: 0xB042, serialNumber: "A").condition, vertical: true)

        XCTAssertFalse(scheme.isActive(in: context([mouse(productID: 0xB042, serialNumber: "B"), receiver])))
        // While the receiver cannot tell its devices apart, only receiver schemes apply.
        XCTAssertFalse(scheme.isActive(in: context([receiver])))
    }

    func testConditionMustMatchOneCandidate() {
        var mixed = mouse(productID: 0xB042, serialNumber: "A")
        mixed.productName = "USB Receiver"
        let scheme = reverseScheme(for: mixed, vertical: true)

        XCTAssertFalse(scheme.isActive(in: context([mouse(productID: 0xB042, serialNumber: "A"), receiver])))
    }

    func testReceiverAndMouseSchemesMergeInFileOrder() {
        let current = mouse(productID: 0xB042, serialNumber: "A")
        let configuration = Configuration(schemes: [
            Scheme(if: [.init(device: receiver)], scrolling: .init(reverse: .init(vertical: true, horizontal: true))),
            reverseScheme(for: current.condition, vertical: false)
        ])

        let merged = configuration.matchScheme(in: context([current, receiver]))

        XCTAssertFalse(merged.scrolling.reverse.vertical ?? true)
        XCTAssertTrue(merged.scrolling.reverse.horizontal ?? false)
    }

    func testSchemeIndexOfMouseFindsSchemeWrittenWithName() {
        let current = mouse(productID: 0xB042, serialNumber: "A")
        let schemes = [
            Scheme(if: [.init(device: receiver)]),
            Scheme(if: [.init(device: current)])
        ]

        XCTAssertEqual(
            schemes.schemeIndex(
                ofDeviceMatcher: current,
                ofApp: nil,
                ofProcessPath: nil,
                ofProcessName: nil,
                ofDisplay: nil
            ),
            .at(1)
        )
        XCTAssertEqual(
            schemes.schemeIndex(
                ofDeviceMatcher: receiver,
                ofApp: nil,
                ofProcessPath: nil,
                ofProcessName: nil,
                ofDisplay: nil
            ),
            .at(0)
        )
    }
}
