// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

@testable import LinearMouse
import XCTest

class ImplicitOptionalTests: XCTestCase {
    struct Foo: Codable, Equatable {
        @ImplicitOptional var bar: Bar

        init() {}

        init(bar: Bar? = nil) {
            $bar = bar
        }
    }

    struct Bar: Codable, Equatable {
        @ImplicitOptional var baz: Baz

        init() {}

        init(baz: Baz? = nil) {
            $baz = baz
        }
    }

    struct Baz: Codable, Equatable {
        var qux: Int
    }

    func testEncodingNil() throws {
        let encoder = JSONEncoder()
        XCTAssertEqual(String(decoding: try encoder.encode(Foo()), as: UTF8.self),
                       "{}")
    }

    func testEncodingNestedNil() throws {
        let encoder = JSONEncoder()
        XCTAssertEqual(String(decoding: try encoder.encode(Foo(bar: Bar())), as: UTF8.self),
                       "{\"bar\":{}}")
    }

    func testNestedAssignment() throws {
        var foo = Foo()
        foo.bar.baz.qux += 1
        XCTAssertEqual(foo.bar.baz.qux, 43)
    }

    func testDecodeNil() throws {
        let decoder = JSONDecoder()
        let foo = try decoder.decode(Foo.self, from: "{\"bar\":{}}".data(using: .utf8)!)
        XCTAssertEqual(foo.bar.$baz, nil)
    }
}

extension ImplicitOptionalTests.Foo: ImplicitInitable {}

extension ImplicitOptionalTests.Bar: ImplicitInitable {}

extension ImplicitOptionalTests.Baz: ImplicitInitable {
    init() {
        qux = 42
    }
}
