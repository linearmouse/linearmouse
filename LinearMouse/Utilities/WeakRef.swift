// MIT License
// Copyright (c) 2021-2024 LinearMouse

import Foundation

class WeakRef<T: AnyObject> {
    weak var value: T?

    init() {}

    init(_ value: T) {
        self.value = value
    }
}

extension WeakRef: Equatable where T: Equatable {
    static func == (lhs: WeakRef<T>, rhs: WeakRef<T>) -> Bool {
        lhs.value == rhs.value
    }
}

extension WeakRef: Hashable where T: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

extension WeakRef: CustomStringConvertible where T: CustomStringConvertible {
    var description: String {
        value?.description ?? "(nil)"
    }
}
