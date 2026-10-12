// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class LogitechControlSerialStrippingTests: XCTestCase {
    private typealias Button = Scheme.Buttons.Mapping.Button

    private let controlID = 0x00FD
    private let productID = 16507
    private let serialA = "2DBD340E"
    private let serialB = "EA2DBD34"
    private let otherProductID = 0x405E

    private func identity(serialNumber: String?, productID: Int? = nil) -> LogitechControlIdentity {
        .init(
            controlID: controlID,
            productID: productID ?? self.productID,
            serialNumber: serialNumber
        )
    }

    func testWithoutSerialNumberClearsOnlyTheSerial() throws {
        let button = Button.logitechControl(identity(serialNumber: serialA))

        let result = try XCTUnwrap(button.withoutSerialNumber.logitechControl)

        XCTAssertNil(result.serialNumber)
        XCTAssertEqual(result.controlID, controlID)
        XCTAssertEqual(result.productID, productID)
    }

    func testWithoutSerialNumberLeavesMouseButtonsUnchanged() {
        let button = Button.mouse(4)

        XCTAssertEqual(button.withoutSerialNumber, button)
    }

    func testWithoutSerialNumberIsIdempotent() {
        let button = Button.logitechControl(identity(serialNumber: nil))

        XCTAssertEqual(button.withoutSerialNumber, button)
        XCTAssertEqual(button.withoutSerialNumber.withoutSerialNumber, button)
    }

    func testWithoutSerialNumberLowersSpecificityToProductTier() throws {
        let pinned = identity(serialNumber: serialA)
        let unpinned = try XCTUnwrap(Button.logitechControl(pinned).withoutSerialNumber.logitechControl)

        XCTAssertEqual(pinned.specificityScore, 2)
        XCTAssertEqual(unpinned.specificityScore, 1)
    }

    func testUnpinnedIdentityMatchesEveryUnitOfTheSameProduct() throws {
        let configured = try XCTUnwrap(
            Button.logitechControl(identity(serialNumber: serialA)).withoutSerialNumber.logitechControl
        )

        XCTAssertTrue(identity(serialNumber: serialA).matches(configured))
        XCTAssertTrue(identity(serialNumber: serialB).matches(configured))
        XCTAssertTrue(identity(serialNumber: nil).matches(configured))
    }

    func testUnpinnedIdentityStillRejectsOtherProducts() throws {
        let configured = try XCTUnwrap(
            Button.logitechControl(identity(serialNumber: serialA)).withoutSerialNumber.logitechControl
        )

        XCTAssertFalse(identity(serialNumber: nil, productID: otherProductID).matches(configured))
    }

    func testPinnedIdentityRejectsASecondUnitOfTheSameProduct() {
        let configured = identity(serialNumber: serialA)

        XCTAssertTrue(identity(serialNumber: serialA).matches(configured))
        XCTAssertFalse(identity(serialNumber: serialB).matches(configured))
    }

    func testPinnedIdentityNeedsFallbackWhenTheEventReportsNoSerial() {
        let configured = identity(serialNumber: serialA)
        let event = identity(serialNumber: nil)

        XCTAssertFalse(event.matches(configured))
        XCTAssertTrue(event.matches(configured, allowingIdentityFallback: true))
    }

    func testSerialComparisonIsCaseInsensitive() {
        let configured = identity(serialNumber: serialA.lowercased())

        XCTAssertTrue(identity(serialNumber: serialA).matches(configured))
    }
}
