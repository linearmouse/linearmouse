// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Foundation
import SwiftUI

protocol OptionalBindable {
    init()
}

extension Binding {
    func optionalBinding<Wrapped: OptionalBindable, Subject>(
        _ keyPath: WritableKeyPath<Wrapped, Subject>,
        defaultValue: Subject
    ) -> Binding<Subject> where Value == Wrapped? {
        Binding<Subject>(
            get: {
                projectedValue.wrappedValue?[keyPath: keyPath] ?? defaultValue
            },
            set: {
                if projectedValue.wrappedValue == nil {
                    projectedValue.wrappedValue = Wrapped()
                }
                projectedValue.wrappedValue![keyPath: keyPath] = $0
            }
        )
    }

    func optionalBinding<Wrapped: OptionalBindable,
        Subject: OptionalBindable>(_ keyPath: WritableKeyPath<Wrapped, Subject?>) -> Binding<Subject?>
        where Value == Wrapped? {
        optionalBinding(keyPath, defaultValue: Subject())
    }

    func optionalBinding<Wrapped: OptionalBindable,
        Subject: ExpressibleByNilLiteral>(_ keyPath: WritableKeyPath<Wrapped, Subject>) -> Binding<Subject>
        where Value == Wrapped? {
        optionalBinding(keyPath, defaultValue: nil)
    }
}

extension Binding {
    func map<T>(get: @escaping (Value) -> T, set: @escaping (T) -> Value) -> Binding<T> {
        Binding<T>(get: {
            get(wrappedValue)
        }, set: {
            wrappedValue = set($0)
        })
    }

    func withDefault<T>(_ defaultValue: T) -> Binding<T> where Value == T? {
        map(get: { $0 ?? defaultValue }, set: { $0 })
    }
}
