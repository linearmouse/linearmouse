// MIT License
// Copyright (c) 2021-2024 LinearMouse

import AppKit
import Defaults
import Foundation
import JSONPatcher

struct Configuration: Codable, Equatable {
    let jsonSchema = "https://schema.linearmouse.app/\(LinearMouse.appVersion)"

    var schemes: [Scheme] = []

    enum CodingKeys: String, CodingKey {
        case jsonSchema = "$schema"
        case schemes
    }

    enum ConfigurationError: Error {
        case unsupportedEncoding
        case parseError(Error)
    }
}

extension Configuration.ConfigurationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedEncoding:
            return NSLocalizedString("Unsupported encoding, expected UTF-8", comment: "")
        case let .parseError(underlyingError):
            if let decodingError = underlyingError as? DecodingError {
                switch decodingError {
                case let .typeMismatch(type, context):
                    return String(format: NSLocalizedString("Type mismatch: expected %1$@ at %2$@", comment: ""),
                                  String(describing: type),
                                  String(describing: context.codingPath.map(\.stringValue).joined(separator: ".")))
                case let .keyNotFound(codingKey, context):
                    return String(format: NSLocalizedString("Missing key %1$@ at %2$@", comment: ""),
                                  String(describing: codingKey.stringValue),
                                  String(describing: context.codingPath.map(\.stringValue).joined(separator: ".")))
                default:
                    break
                }
                return String(describing: underlyingError)
            }
            // TODO: More detailed description in underlyingError.
            return String(format: NSLocalizedString("Invalid JSON: %@", comment: ""),
                          underlyingError.localizedDescription)
        }
    }
}

extension Configuration {
    static func load(from string: String) throws -> Configuration {
        do {
            let jsonPatcher = try JSONPatcher(original: string)
            let json = jsonPatcher.json()
            guard let data = json.data(using: .utf8) else {
                throw ConfigurationError.unsupportedEncoding
            }
            let decoder = JSONDecoder()
            return try decoder.decode(Configuration.self, from: data)
        } catch {
            throw ConfigurationError.parseError(error)
        }
    }

    static func load(from data: Data) throws -> Configuration {
        guard let string = String(data: data, encoding: .utf8) else {
            throw ConfigurationError.unsupportedEncoding
        }
        return try load(from: string)
    }

    static func load(from url: URL) throws -> Configuration {
        try load(from: Data(contentsOf: url))
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

    func matchScheme(withDevice device: Device? = nil,
                     withApp app: String? = nil,
                     withParentApp parentApp: String? = nil,
                     withGroupApp groupApp: String? = nil,
                     withScreen screen: String? = nil) -> Scheme {
        // TODO: Backtrace the merge path
        // TODO: Optimize the algorithm

        var mergedScheme = Scheme()

        let `if` = Scheme.If(device: device.map { DeviceMatcher(of: $0) },
                             app: app,
                             parentApp: parentApp,
                             groupApp: groupApp,
                             screen: screen)

        mergedScheme.if = [`if`]

        for scheme in schemes where scheme.isActive(withDevice: device,
                                                    withApp: app,
                                                    withParentApp: parentApp,
                                                    withGroupApp: groupApp,
                                                    withScreen: screen) {
            scheme.merge(into: &mergedScheme)
        }

        return mergedScheme
    }

    func matchScheme(withDevice device: Device? = nil,
                     withPid pid: pid_t? = nil,
                     withScreen screen: String? = nil) -> Scheme {
        matchScheme(withDevice: device,
                    withApp: pid?.bundleIdentifier,
                    withParentApp: pid?.parent?.bundleIdentifier,
                    withGroupApp: pid?.group?.bundleIdentifier,
                    withScreen: screen)
    }
}
