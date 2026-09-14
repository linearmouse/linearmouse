// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation
@testable import PointerKit
import XCTest

final class HIDPropertyValueTests: XCTestCase {
    func testMissingOptionalPropertiesAreSkipped() {
        let acceleration: Int32? = nil
        let linearScaling: Int? = nil
        let accelerationType: String? = nil

        XCTAssertNil(hidPropertyValue(acceleration))
        XCTAssertNil(hidPropertyValue(linearScaling))
        XCTAssertNil(hidPropertyValue(accelerationType))
    }

    func testNestedMissingOptionalIsSkipped() {
        // Generic forwarding can wrap a missing value in another Optional.
        let value: Int32?? = .some(nil)

        XCTAssertNil(hidPropertyValue(value))
    }

    func testExplicitNullPropertyIsSkipped() {
        XCTAssertNil(hidPropertyValue(NSNull()))
        XCTAssertNil(hidPropertyValue(kCFNull))
    }

    func testFixedPointValuesRemainValidBinaryPropertyLists() throws {
        // Preserve zero, disabled acceleration (-1 in 16.16), and a fraction.
        for value: Int32 in [0, -65_536, 45_056] {
            let property = try XCTUnwrap(hidPropertyValue(Optional(value)))
            let data = try PropertyListSerialization.data(fromPropertyList: property, format: .binary, options: 0)
            let decoded = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)

            XCTAssertEqual((decoded as? NSNumber)?.int32Value, value)
        }
    }

    func testStringValueRemainsAValidBinaryPropertyList() throws {
        let value: String? = "HIDMouseAcceleration"
        let property = try XCTUnwrap(hidPropertyValue(value))
        let data = try PropertyListSerialization.data(fromPropertyList: property, format: .binary, options: 0)
        let decoded = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)

        XCTAssertEqual(decoded as? String, value)
    }
}
