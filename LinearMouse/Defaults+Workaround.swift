// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Defaults
import Foundation

public extension Defaults.Serializable where Self: Codable {
    static var bridge: Defaults.TopLevelCodableBridge<Self> { Defaults.TopLevelCodableBridge() }
}

public extension Defaults.Serializable where Self: Codable & NSSecureCoding {
    static var bridge: Defaults.CodableNSSecureCodingBridge<Self> { Defaults.CodableNSSecureCodingBridge() }
}

public extension Defaults.Serializable where Self: Codable & NSSecureCoding & Defaults.PreferNSSecureCoding {
    static var bridge: Defaults.NSSecureCodingBridge<Self> { Defaults.NSSecureCodingBridge() }
}

public extension Defaults.Serializable where Self: Codable & RawRepresentable {
    static var bridge: Defaults.RawRepresentableCodableBridge<Self> { Defaults.RawRepresentableCodableBridge() }
}

public extension Defaults.Serializable where Self: Codable & RawRepresentable & Defaults.PreferRawRepresentable {
    static var bridge: Defaults.RawRepresentableBridge<Self> { Defaults.RawRepresentableBridge() }
}

public extension Defaults.Serializable where Self: RawRepresentable {
    static var bridge: Defaults.RawRepresentableBridge<Self> { Defaults.RawRepresentableBridge() }
}

public extension Defaults.Serializable where Self: NSSecureCoding {
    static var bridge: Defaults.NSSecureCodingBridge<Self> { Defaults.NSSecureCodingBridge() }
}

public extension Defaults.CollectionSerializable where Element: Defaults.Serializable {
    static var bridge: Defaults.CollectionBridge<Self> { Defaults.CollectionBridge() }
}

public extension Defaults.SetAlgebraSerializable where Element: Defaults.Serializable & Hashable {
    static var bridge: Defaults.SetAlgebraBridge<Self> { Defaults.SetAlgebraBridge() }
}
