// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Foundation

struct CustomDecodingError: Error {
    var codingPath: [CodingKey]
    var error: Error
}

extension CustomDecodingError {
    init(in container: SingleValueDecodingContainer, error: Error) {
        codingPath = container.codingPath
        self.error = error
    }

    init(in container: UnkeyedDecodingContainer, error: Error) {
        codingPath = container.codingPath
        self.error = error
    }

    init<K>(in container: KeyedDecodingContainer<K>, error: Error) {
        codingPath = container.codingPath
        self.error = error
    }
}

extension CustomDecodingError: CustomStringConvertible {
    var description: String {
        String(describing: error)
    }
}

extension CustomDecodingError: LocalizedError {
    var errorDescription: String? {
        String(format: NSLocalizedString("%1$@ (%2$@)", comment: ""),
               error.localizedDescription,
               codingPath.map(\.stringValue).joined(separator: "."))
    }
}
