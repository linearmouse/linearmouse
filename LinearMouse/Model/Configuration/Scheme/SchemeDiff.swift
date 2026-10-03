// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Pure comparison. Raw schemes retain their inheritance semantics; callers
/// comparing effective values must explicitly normalize after matching/merging.
struct SchemeDiff {
    let previous: Scheme?
    let current: Scheme

    func changed<Value: Equatable>(_ keyPath: KeyPath<Scheme, Value>) -> Bool {
        guard let previous else {
            return true
        }
        return previous[keyPath: keyPath] != current[keyPath: keyPath]
    }
}
