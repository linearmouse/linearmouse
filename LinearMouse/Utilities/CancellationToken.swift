// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

private final class CancellationState {
    let lock = NSLock()
    var cancelled = false
}

struct CancellationToken: Equatable {
    fileprivate let state: CancellationState

    var isCancelled: Bool {
        state.lock.withLock { state.cancelled }
    }

    var shouldContinue: Bool {
        !isCancelled
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.state === rhs.state
    }
}

final class CancellationSource {
    private let state = CancellationState()

    var token: CancellationToken {
        CancellationToken(state: state)
    }

    func cancel() {
        state.lock.withLock { state.cancelled = true }
    }
}
