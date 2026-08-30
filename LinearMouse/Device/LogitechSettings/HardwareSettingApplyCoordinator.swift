// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Reconciles one configured Logitech hardware setting after startup or reconnect. A
/// device may not answer immediately after waking, and some firmware accepts
/// an early write before resetting it during the remainder of its boot sequence.
final class HardwareSettingApplyCoordinator {
    struct Attempt: Equatable {
        let verifiesCachedValue: Bool
        let number: Int
        let isFinal: Bool
        let cancellationToken: CancellationToken

        init(
            verifiesCachedValue: Bool,
            number: Int,
            isFinal: Bool,
            cancellationToken: CancellationToken = CancellationSource().token
        ) {
            self.verifiesCachedValue = verifiesCachedValue
            self.number = number
            self.isFinal = isFinal
            self.cancellationToken = cancellationToken
        }

        func shouldContinue() -> Bool {
            cancellationToken.shouldContinue
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.verifiesCachedValue == rhs.verifiesCachedValue
                && lhs.number == rhs.number
                && lhs.isFinal == rhs.isFinal
        }
    }

    typealias Operation = (_ attempt: Attempt) -> Bool
    typealias Completion = (_ succeeded: Bool) -> Void
    typealias Scheduler = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Void

    private enum Phase {
        case apply
        case confirm
    }

    private let retryDelays: [TimeInterval]
    private let confirmationDelay: TimeInterval
    private let scheduler: Scheduler
    private let lock = NSLock()
    private var currentCancellationSource: CancellationSource?

    init(
        retryDelays: [TimeInterval] = [0.5, 1, 2, 4],
        confirmationDelay: TimeInterval = 3,
        scheduler: @escaping Scheduler
    ) {
        self.retryDelays = retryDelays
        self.confirmationDelay = confirmationDelay
        self.scheduler = scheduler
    }

    func start(_ operation: @escaping Operation, completion: Completion? = nil) {
        let cancellationSource = CancellationSource()
        let previousSource = lock.withLock { () -> CancellationSource? in
            defer { currentCancellationSource = cancellationSource }
            return currentCancellationSource
        }
        previousSource?.cancel()

        schedule(
            cancellationSource: cancellationSource,
            phase: .apply,
            retryIndex: 0,
            delay: 0,
            operation: operation,
            completion: completion
        )
    }

    func cancel() {
        let source = lock.withLock { () -> CancellationSource? in
            defer { currentCancellationSource = nil }
            return currentCancellationSource
        }
        source?.cancel()
    }

    private func schedule(
        cancellationSource: CancellationSource,
        phase: Phase,
        retryIndex: Int,
        delay: TimeInterval,
        operation: @escaping Operation,
        completion: Completion?
    ) {
        scheduler(delay) { [weak self] in
            self?.run(
                cancellationSource: cancellationSource,
                phase: phase,
                retryIndex: retryIndex,
                operation: operation,
                completion: completion
            )
        }
    }

    private func run(
        cancellationSource: CancellationSource,
        phase: Phase,
        retryIndex: Int,
        operation: @escaping Operation,
        completion: Completion?
    ) {
        guard isCurrent(cancellationSource) else {
            return
        }

        let succeeded = operation(.init(
            verifiesCachedValue: phase == .confirm,
            number: retryIndex + 1,
            isFinal: retryIndex >= retryDelays.count,
            cancellationToken: cancellationSource.token
        ))
        guard isCurrent(cancellationSource) else {
            return
        }

        if succeeded {
            if phase == .apply {
                schedule(
                    cancellationSource: cancellationSource,
                    phase: .confirm,
                    retryIndex: 0,
                    delay: confirmationDelay,
                    operation: operation,
                    completion: completion
                )
            } else {
                finish(cancellationSource, succeeded: true, completion: completion)
            }
            return
        }

        guard retryIndex < retryDelays.count else {
            finish(cancellationSource, succeeded: false, completion: completion)
            return
        }

        schedule(
            cancellationSource: cancellationSource,
            phase: phase,
            retryIndex: retryIndex + 1,
            delay: retryDelays[retryIndex],
            operation: operation,
            completion: completion
        )
    }

    private func isCurrent(_ cancellationSource: CancellationSource) -> Bool {
        cancellationSource.token.shouldContinue
            && lock.withLock { currentCancellationSource === cancellationSource }
    }

    private func finish(
        _ cancellationSource: CancellationSource,
        succeeded: Bool,
        completion: Completion?
    ) {
        let wasCurrent = lock.withLock {
            if currentCancellationSource === cancellationSource {
                currentCancellationSource = nil
                return true
            }
            return false
        }
        guard wasCurrent else {
            return
        }
        cancellationSource.cancel()
        completion?(succeeded)
    }
}
