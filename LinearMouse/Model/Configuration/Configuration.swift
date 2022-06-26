// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import Defaults
import Foundation

struct Configuration: Codable {
    let jsonSchema = "https://app.linearmouse.org/schema/\(LinearMouse.appVersion)"

    var schemes: [Scheme] = []

    enum CodingKeys: String, CodingKey {
        case jsonSchema = "$schema"
        case schemes
    }

    enum ConfigurationError: Error {
        case parseError(Error)
    }
}

extension Configuration.ConfigurationError: LocalizedError {
    var errorDescription: String? {
        switch self {
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
                case let .keyNotFound(codingKey, context):
                    return String(format: NSLocalizedString("Missing key %1$@ at %2$@", comment: ""),
                                  String(describing: codingKey.stringValue),
                                  String(describing: context.codingPath.map(\.stringValue).joined(separator: ".")))
                default:
                    break
                }
                return String(describing: underlyingError)
            }
            return underlyingError.localizedDescription
        }
    }
}

extension Configuration {
    static func load(from data: Data) throws -> Configuration {
        let decoder = JSONDecoder()

        do {
            return try decoder.decode(Configuration.self, from: data)
        } catch {
            throw ConfigurationError.parseError(error)
        }
    }

    static func load(from url: URL) throws -> Configuration {
        try load(from: try Data(contentsOf: url))
    }

    func dump() throws -> Data {
        let encoder = JSONEncoder()

        encoder.outputFormatting = .prettyPrinted

        return try encoder.encode(self)
    }

    func dump(to url: URL) throws {
        let parentDirectory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDirectory.path) {
            try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }
        try dump().write(to: url, options: .atomic)
    }

    func matchedScheme(withDevice device: Device?) -> Scheme {
        // TODO: Backtrace the merge path
        // TODO: Optimize the algorithm

        var mergedScheme = Scheme()

        if let device = device {
            mergedScheme.if = [
                Scheme.If(device: DeviceMatcher(of: device))
            ]
        }

        for scheme in schemes where scheme.isActive(withDevice: device) {
            scheme.merge(into: &mergedScheme)
        }

        return mergedScheme
    }

    var activeScheme: Scheme {
        matchedScheme(withDevice: DeviceManager.shared.lastActiveDevice)
    }
}
