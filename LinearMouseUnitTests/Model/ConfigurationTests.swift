// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

@testable import LinearMouse
import XCTest

class ConfigurationTests: XCTestCase {
    func testDump() throws {
        print(try Configuration(schemes: []).dump())
    }

    func testMergeScheme() throws {
        var scheme = Scheme()

        XCTAssertNil(scheme.scrolling)

        Scheme(scrolling: .init(reverse: .init(vertical: true))).merge(into: &scheme)

        XCTAssertEqual(scheme.scrolling?.reverse?.vertical, true)
        XCTAssertNil(scheme.scrolling?.reverse?.horizontal)

        Scheme(scrolling: .init(reverse: .init(vertical: false, horizontal: true))).merge(into: &scheme)

        XCTAssertEqual(scheme.scrolling?.reverse?.vertical, false)
        XCTAssertEqual(scheme.scrolling?.reverse?.horizontal, true)

        Scheme(scrolling: .init(reverse: .init(vertical: true))).merge(into: &scheme)

        XCTAssertEqual(scheme.scrolling?.reverse?.vertical, true)
        XCTAssertEqual(scheme.scrolling?.reverse?.horizontal, true)
    }
}
