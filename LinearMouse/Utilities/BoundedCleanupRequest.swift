// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Owns one cleanup completion with a hard deadline.
///
/// Normal cleanup and the deadline race for the same completion right; the
/// winner delivers the result exactly once. Each request is one-shot and is
/// its own identity, so no generation or epoch is needed.
final class BoundedCleanupRequest {
    enum Outcome: Equatable {
        case completed
        case timedOut
    }

    typealias Scheduler = (_ timeout: TimeInterval, _ action: @escaping () -> Void) -> Void
    typealias Delivery = (_ action: @escaping () -> Void) -> Void

    static let defaultTimeout: TimeInterval = 5

    private let lock = NSLock()
    private var finished = false
    private let authorization = CancellationSource()
    private let onTimeout: () -> Void
    private let completion: (Outcome) -> Void
    private let delivery: Delivery

    /// Admission shared by the cleanup workers owned by this request.
    ///
    /// The one-shot winner revokes it before scheduling completion delivery, so
    /// reaching the deadline stops new work even when the main run loop is busy.
    var authorizationToken: CancellationToken {
        authorization.token
    }

    init(
        timeout: TimeInterval = defaultTimeout,
        scheduler: @escaping Scheduler = { timeout, action in
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + timeout,
                execute: action
            )
        },
        delivery: @escaping Delivery = { action in
            let runLoop = CFRunLoopGetMain()
            CFRunLoopPerformBlock(
                runLoop,
                CFRunLoopMode.commonModes.rawValue,
                action
            )
            CFRunLoopWakeUp(runLoop)
        },
        onTimeout: @escaping () -> Void = {},
        completion: @escaping (Outcome) -> Void
    ) {
        self.onTimeout = onTimeout
        self.completion = completion
        self.delivery = delivery

        scheduler(timeout) { [weak self] in
            self?.finish(with: .timedOut)
        }
    }

    func complete() {
        finish(with: .completed)
    }

    private func finish(with outcome: Outcome) {
        let won = lock.withLock { () -> Bool in
            guard !finished else {
                return false
            }
            finished = true
            authorization.cancel()
            return true
        }
        guard won else {
            return
        }

        delivery { [onTimeout, completion] in
            if outcome == .timedOut {
                onTimeout()
            }
            completion(outcome)
        }
    }
}
