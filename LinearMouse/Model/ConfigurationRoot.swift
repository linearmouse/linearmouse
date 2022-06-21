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

extension ConfigurationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return NSLocalizedString("Not implemented", comment: "")
        case let .parseError(underlyingError):
            if let decodingError = underlyingError as? DecodingError {
                switch decodingError {
                case let .typeMismatch(type, context):
                    return String(format: NSLocalizedString("Type mismatch: expected %1$@ at %2$@", comment: ""),
                                  String(describing: type),
                                  String(describing: context.codingPath.map(\.stringValue).joined(separator: ".")))
                case let .dataCorrupted(context):
                    if let underlyingError = context.underlyingError {
                        if let errorDescription = (underlyingError as NSError).userInfo[NSDebugDescriptionErrorKey] {
                            return String(format: NSLocalizedString("Invalid JSON: %1$@", comment: ""),
                                          String(describing: errorDescription))
                        }
                        return String(format: NSLocalizedString("Invalid JSON: %1$@", comment: ""),
                                      String(describing: underlyingError))
                    } else {
                        return NSLocalizedString("Invalid JSON: Unknown error", comment: "")
                    }
                default:
                    break
                }
                return String(describing: underlyingError)
            }
            return underlyingError.localizedDescription
        }
    }
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
