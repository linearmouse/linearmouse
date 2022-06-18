// MIT License
// Copyright (c) 2021-2022 Jiahao Lu

import SwiftUI

private struct IsPresentedBindingKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

extension EnvironmentValues {
    var isPresented: Binding<Bool>? {
        get { self[IsPresentedBindingKey.self] }
        set { self[IsPresentedBindingKey.self] = newValue }
    }
}
