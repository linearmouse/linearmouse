// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

@testable import LinearMouse
import XCTest

class BidirectionalTests: XCTestCase {
    typealias Bidirectional = Scheme.Scrolling.Bidirectional

    struct Foo: Codable, Equatable {
        var bar: String?
    }

    func testEncodeLiteral() throws {
        let encoder = JSONEncoder()

        var foos = Bidirectional<Bool>()
        XCTAssertEqual(String(data: try encoder.encode(foos), encoding: .utf8),
                       "null")

        foos.vertical = true
        XCTAssertEqual(String(data: try encoder.encode(foos), encoding: .utf8),
                       "{\"vertical\":true}")

        foos.horizontal = true
        XCTAssertEqual(String(data: try encoder.encode(foos), encoding: .utf8),
                       "true")
    }

    func testEncodeStruct() throws {
        let encoder = JSONEncoder()

        var foos = Bidirectional<Foo>()
        XCTAssertEqual(String(data: try encoder.encode(foos), encoding: .utf8),
                       "null")

        foos.vertical = .init()
        XCTAssertEqual(String(data: try encoder.encode(foos), encoding: .utf8),
                       "{\"vertical\":{}}")

        foos.horizontal = .init()
        XCTAssertEqual(String(data: try encoder.encode(foos), encoding: .utf8),
                       "{}")

        foos.vertical = .init(bar: "baz")
        XCTAssertEqual(String(data: try encoder.encode(foos), encoding: .utf8),
                       "{\"horizontal\":{},\"vertical\":{\"bar\":\"baz\"}}")
    }

    func testDecodeLiteral() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(try decoder.decode(Bidirectional<Bool>.self, from: "null".data(using: .utf8)!),
                       .init())

        XCTAssertEqual(try decoder.decode(Bidirectional<Bool>.self, from: "{\"vertical\":true}".data(using: .utf8)!),
                       .init(vertical: true))

        XCTAssertEqual(
            try decoder
                .decode(Bidirectional<Bool>.self, from: "{\"horizontal\":false,\"vertical\":true}".data(using: .utf8)!),
            .init(vertical: true, horizontal: false)
        )

        XCTAssertEqual(try decoder.decode(Bidirectional<Bool>.self, from: "true".data(using: .utf8)!),
                       .init(vertical: true, horizontal: true))
    }

    func testDecodeStruct() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(Bidirectional<Foo>.self, from: "{\"vertical\":{\"bar\":\"baz\"}}".data(using: .utf8)!),
            .init(vertical: .init(bar: "baz"))
        )

        XCTAssertEqual(try decoder.decode(Bidirectional<Foo>.self, from: "{\"bar\":\"baz\"}".data(using: .utf8)!),
                       .init(vertical: .init(bar: "baz"), horizontal: .init(bar: "baz")))
    }
}
