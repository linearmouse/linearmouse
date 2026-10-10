// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Main-thread recovery with a finite retry budget and cancellation across sleep, lock and termination.
final class EventTapRecovery {
    enum StartResult {
        case started, permissionRequired, failed
    }

    typealias Attempt = (@escaping (StartResult) -> Void) -> Void
    typealias Schedule = (TimeInterval, @escaping () -> Void) -> Void

    private let attempt: Attempt
    private let schedule: Schedule
    private let onFailure: (StartResult) -> Void
    private let delays: [TimeInterval]
    private var recoveryID = 0
    private var active = false

    init(
        delays: [TimeInterval] = [0.5, 1, 2],
        schedule: @escaping Schedule = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        },
        attempt: @escaping Attempt,
        onFailure: @escaping (StartResult) -> Void
    ) {
        self.delays = delays
        self.schedule = schedule
        self.attempt = attempt
        self.onFailure = onFailure
    }

    func start() {
        guard !active else {
            return
        }
        active = true
        run(recoveryID: recoveryID, retry: 0)
    }

    func stop() {
        recoveryID += 1
        active = false
    }

    private func run(recoveryID expectedRecoveryID: Int, retry: Int) {
        guard active, recoveryID == expectedRecoveryID else {
            return
        }
        attempt { [weak self] result in
            guard let self, active, recoveryID == expectedRecoveryID else {
                return
            }
            switch result {
            case .started:
                break
            case .permissionRequired:
                onFailure(result)
            case .failed:
                guard retry < delays.count else {
                    onFailure(result)
                    return
                }
                schedule(delays[retry]) { [weak self] in
                    self?.run(recoveryID: expectedRecoveryID, retry: retry + 1)
                }
            }
        }
    }
}
