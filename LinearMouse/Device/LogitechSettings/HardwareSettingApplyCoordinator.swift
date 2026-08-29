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
        let shouldContinue: () -> Bool

        init(
            verifiesCachedValue: Bool,
            number: Int,
            isFinal: Bool,
            shouldContinue: @escaping () -> Bool = { true }
        ) {
            self.verifiesCachedValue = verifiesCachedValue
            self.number = number
            self.isFinal = isFinal
            self.shouldContinue = shouldContinue
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.verifiesCachedValue == rhs.verifiesCachedValue
                && lhs.number == rhs.number
                && lhs.isFinal == rhs.isFinal
        }
    }

    typealias Operation = (_ attempt: Attempt) -> Bool
    typealias Scheduler = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Void

    private enum Phase {
        case apply
        case confirm
    }

    private let retryDelays: [TimeInterval]
    private let confirmationDelay: TimeInterval
    private let scheduler: Scheduler
    private let lock = NSLock()
    private var currentRequestID: UUID?

    init(
        retryDelays: [TimeInterval] = [0.5, 1, 2, 4],
        confirmationDelay: TimeInterval = 3,
        scheduler: @escaping Scheduler
    ) {
        self.retryDelays = retryDelays
        self.confirmationDelay = confirmationDelay
        self.scheduler = scheduler
    }

    func start(_ operation: @escaping Operation) {
        let requestID = UUID()
        lock.lock()
        currentRequestID = requestID
        lock.unlock()

        schedule(
            requestID: requestID,
            phase: .apply,
            retryIndex: 0,
            delay: 0,
            operation: operation
        )
    }

    func cancel() {
        lock.lock()
        currentRequestID = nil
        lock.unlock()
    }

    private func schedule(
        requestID: UUID,
        phase: Phase,
        retryIndex: Int,
        delay: TimeInterval,
        operation: @escaping Operation
    ) {
        scheduler(delay) { [weak self] in
            self?.run(
                requestID: requestID,
                phase: phase,
                retryIndex: retryIndex,
                operation: operation
            )
        }
    }

    private func run(
        requestID: UUID,
        phase: Phase,
        retryIndex: Int,
        operation: @escaping Operation
    ) {
        guard isCurrent(requestID) else {
            return
        }

        let succeeded = operation(.init(
            verifiesCachedValue: phase == .confirm,
            number: retryIndex + 1,
            isFinal: retryIndex >= retryDelays.count
        ) { [weak self] in self?.isCurrent(requestID) == true })
        guard isCurrent(requestID) else {
            return
        }

        if succeeded {
            if phase == .apply {
                schedule(
                    requestID: requestID,
                    phase: .confirm,
                    retryIndex: 0,
                    delay: confirmationDelay,
                    operation: operation
                )
            } else {
                finish(requestID)
            }
            return
        }

        guard retryIndex < retryDelays.count else {
            finish(requestID)
            return
        }

        schedule(
            requestID: requestID,
            phase: phase,
            retryIndex: retryIndex + 1,
            delay: retryDelays[retryIndex],
            operation: operation
        )
    }

    private func isCurrent(_ requestID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentRequestID == requestID
    }

    private func finish(_ requestID: UUID) {
        lock.lock()
        if currentRequestID == requestID {
            currentRequestID = nil
        }
        lock.unlock()
    }
}
