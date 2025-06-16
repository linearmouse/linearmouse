// MIT License
// Copyright (c) 2021-2025 LinearMouse

@testable import LinearMouse
import XCTest

final class BidirectionalTests: XCTestCase {
    private typealias Bidirectional = Scheme.Scrolling.Bidirectional

    private struct Foo: Codable, Equatable {
        var bar: String?
    }

    func testEncodeLiteral() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        var foos = Bidirectional<Bool>()
        XCTAssertEqual(
            try String(data: encoder.encode(foos), encoding: .utf8),
            "null"
        )

        foos.vertical = true
        XCTAssertEqual(
            try String(data: encoder.encode(foos), encoding: .utf8),
            "{\"vertical\":true}"
        )

        foos.horizontal = true
        XCTAssertEqual(
            try String(data: encoder.encode(foos), encoding: .utf8),
            "true"
        )
    }

    func testEncodeStruct() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        var foos = Bidirectional<Foo>()
        XCTAssertEqual(
            try String(data: encoder.encode(foos), encoding: .utf8),
            "null"
        )

        foos.vertical = .init()
        XCTAssertEqual(
            try String(data: encoder.encode(foos), encoding: .utf8),
            "{\"vertical\":{}}"
        )

        foos.horizontal = .init()
        XCTAssertEqual(
            try String(data: encoder.encode(foos), encoding: .utf8),
            "{}"
        )

        foos.vertical = .init(bar: "baz")
        XCTAssertEqual(
            try String(data: encoder.encode(foos), encoding: .utf8),
            "{\"horizontal\":{},\"vertical\":{\"bar\":\"baz\"}}"
        )
    }

    func testDecodeLiteral() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(Bidirectional<Bool>.self, from: Data("null".utf8)),
            .init()
        )

        XCTAssertEqual(
            try decoder.decode(Bidirectional<Bool>.self, from: Data("{\"vertical\":true}".utf8)),
            .init(vertical: true)
        )

        XCTAssertEqual(
            try decoder
                .decode(Bidirectional<Bool>.self, from: Data("{\"horizontal\":false,\"vertical\":true}".utf8)),
            .init(vertical: true, horizontal: false)
        )

        XCTAssertEqual(
            try decoder.decode(Bidirectional<Bool>.self, from: Data("true".utf8)),
            .init(vertical: true, horizontal: true)
        )
    }

    func testDecodeStruct() throws {
        let decoder = JSONDecoder()

        XCTAssertEqual(
            try decoder.decode(Bidirectional<Foo>.self, from: Data("{\"vertical\":{\"bar\":\"baz\"}}".utf8)),
            .init(vertical: .init(bar: "baz"))
        )

        XCTAssertEqual(
            try decoder.decode(Bidirectional<Foo>.self, from: Data("{\"bar\":\"baz\"}".utf8)),
            .init(vertical: .init(bar: "baz"), horizontal: .init(bar: "baz"))
        )
    }
}
