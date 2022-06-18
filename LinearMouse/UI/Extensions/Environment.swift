//
//  Environment+Extensions.swift
//  LinearMouse
//
//  Created by Jiahao Lu on 2022/6/18.
//

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
