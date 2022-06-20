// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Defaults
import Foundation

struct ConfigurationRoot: Codable {
    let jsonSchema = "https://app.linearmouse.org/schema/\(LinearMouse.appVersion)"

    var schemes: [ConfigurationScheme] = []

    enum CodingKeys: String, CodingKey {
        case jsonSchema = "$schema"
        case schemes
    }
}

enum ConfigurationError: Error {
    case notImplemented
    case parseError(Error)
}

extension ConfigurationRoot {
    static var shared = ConfigurationRoot()

    static func load(from data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            return try decoder.decode(ConfigurationRoot.self, from: data)
        } catch {
            throw ConfigurationError.parseError(error)
        }
    }

    static func load(from url: URL) throws -> Self {
        guard url.isFileURL else {
            throw ConfigurationError.notImplemented
        }

        return try load(from: try Data(contentsOf: url))
    }

    func dump() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(self)
    }

    func dump(to url: URL) throws {
        let parentDirectory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDirectory.path) {
            try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }
        try dump().write(to: url, options: .atomic)
    }

    var activeScheme: ConfigurationScheme? {
        // TODO: Backtrace the merge path
        // TODO: Optimize the algorithm
        var mergedScheme = ConfigurationScheme()

        for scheme in schemes where scheme.isActive {
            scheme.merge(into: &mergedScheme)
        }

        return mergedScheme
    }
}
