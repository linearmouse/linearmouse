// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Canonicalizes only serials that are safe to use as cross-lifetime hardware
/// identities. Logitech firmware uses all-zero (and occasionally all-`FF`)
/// values as missing-identity sentinels; those must fail closed.
enum LogitechStableSerial {
    static func normalize(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let normalized = value.uppercased().filter {
            !$0.isWhitespace && $0 != ":" && $0 != "-"
        }
        guard !normalized.isEmpty,
              normalized.contains(where: { $0 != "0" }),
              normalized.contains(where: { $0 != "F" }) else {
            return nil
        }
        return normalized
    }

    static func encode(_ bytes: ArraySlice<UInt8>) -> String? {
        guard !bytes.isEmpty,
              bytes.contains(where: { $0 != 0x00 }),
              bytes.contains(where: { $0 != 0xFF }) else {
            return nil
        }
        return bytes.map { String(format: "%02X", $0) }.joined()
    }
}
