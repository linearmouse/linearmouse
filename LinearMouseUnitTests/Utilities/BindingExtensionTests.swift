// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

@testable import LinearMouse
import SwiftUI
import XCTest

class BindingExtensionsTests: XCTestCase {
    func testOptionalBinding() throws {
        var scheme: Scheme?
        let schemeBinding = Binding(get: { scheme }, set: { scheme = $0 })

        let verticalReverseBinding = schemeBinding
            .optionalBinding(\.scrolling)
            .optionalBinding(\.reverse)
            .optionalBinding(\.vertical)

        XCTAssertEqual(verticalReverseBinding.wrappedValue, nil)

        verticalReverseBinding.wrappedValue = true
        XCTAssertEqual(scheme?.scrolling?.reverse?.vertical, true)

        scheme = .init(
            if: [],
            scrolling: .init(
                reverse: .init(vertical: true, horizontal: true),
                distance: .init(vertical: .line(3))
            )
        )

        XCTAssertEqual(scheme?.scrolling?.reverse?.vertical, true)
        verticalReverseBinding.wrappedValue = false
        XCTAssertEqual(scheme?.scrolling?.reverse?.vertical, false)

        XCTAssertEqual(scheme?.if?.count, 0)
        XCTAssertEqual(scheme?.scrolling?.distance?.vertical, .line(3))
    }

    func testWithDefaults() throws {
        XCTAssertEqual(Binding.constant(nil).withDefault(42).wrappedValue, 42)
        XCTAssertEqual(Binding.constant(43).withDefault(42).wrappedValue, 43)
    }
}
