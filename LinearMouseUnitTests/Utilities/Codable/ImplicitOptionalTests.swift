// MIT License
// Copyright (c) 2021-2025 LinearMouse

@testable import LinearMouse
import XCTest

final class ImplicitOptionalTests: XCTestCase {
    fileprivate struct Foo: Codable, Equatable {
        @ImplicitOptional var bar: Bar

        init() {}

        init(bar: Bar? = nil) {
            $bar = bar
        }
    }

    fileprivate struct Bar: Codable, Equatable {
        @ImplicitOptional var baz: Baz

        init() {}

        init(baz: Baz? = nil) {
            $baz = baz
        }
    }

    fileprivate struct Baz: Codable, Equatable {
        var qux: Int
    }

    func testEncodingNil() throws {
        let encoder = JSONEncoder()
        XCTAssertEqual(
            try String(bytes: encoder.encode(Foo()), encoding: .utf8),
            "{}"
        )
    }

    func testEncodingNestedNil() throws {
        let encoder = JSONEncoder()
        XCTAssertEqual(
            try String(bytes: encoder.encode(Foo(bar: Bar())), encoding: .utf8),
            "{\"bar\":{}}"
        )
    }

    func testNestedAssignment() throws {
        var foo = Foo()
        foo.bar.baz.qux += 1
        XCTAssertEqual(foo.bar.baz.qux, 43)
    }

    func testDecodeNil() throws {
        let decoder = JSONDecoder()
        let foo = try decoder.decode(Foo.self, from: Data("{\"bar\":{}}".utf8))
        XCTAssertNil(foo.bar.$baz)
    }
}

extension ImplicitOptionalTests.Foo: ImplicitInitable {}

extension ImplicitOptionalTests.Bar: ImplicitInitable {}

extension ImplicitOptionalTests.Baz: ImplicitInitable {
    init() {
        qux = 42
    }
}
