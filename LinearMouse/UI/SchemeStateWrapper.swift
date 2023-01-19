// MIT License
// Copyright (c) 2021-2023 Jiahao Lu

import Combine
import Foundation
import SwiftUI

class SchemeStateWrapper: ObservableObject {
    @ObservedObject var schemeState = SchemeState.shared

    private var subscriptions = Set<AnyCancellable>()

    init() {
        schemeState.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)
    }
}
