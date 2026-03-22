// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import Foundation

final class SmoothedScrollingEngine {
    enum Axis {
        case horizontal
        case vertical
    }

    struct Emission {
        var deltaX: Double
        var deltaY: Double
        var scrollPhase: CGScrollPhase?
        var momentumPhase: CGMomentumScrollPhase
    }

    private enum SessionState {
        case idle
        case touching
        case momentum
    }

    private enum AxisBehavior {
        case passthrough
        case smoothed(AxisTuning)
    }

    private struct AxisTuning {
        let configuration: Scheme.Scrolling.Smoothed

        init(configuration: Scheme.Scrolling.Smoothed) {
            self.configuration = configuration
        }

        private var presetProfile: Scheme.Scrolling.Smoothed.PresetProfile {
            configuration.resolvedPresetProfile
        }

        private var response: Double {
            (configuration.response?.asTruncatedDouble ?? 0.45).clamped(to: 0.05 ... 1.0)
        }

        private var speed: Double {
            (configuration.speed?.asTruncatedDouble ?? 1).clamped(to: 0 ... 3)
        }

        private var acceleration: Double {
            (configuration.acceleration?.asTruncatedDouble ?? 1.2).clamped(to: 0 ... 3)
        }

        private var inertia: Double {
            (configuration.inertia?.asTruncatedDouble ?? 0.65).clamped(to: 0 ... 3)
        }

        func desiredVelocity(for input: Double) -> Double {
            guard input != 0 else {
                return 0
            }

            let profile = presetProfile
            let baseMagnitude = abs(input)
            let normalizedMagnitude = (baseMagnitude / (baseMagnitude + 24)).clamped(to: 0 ... 1)
            let curvedMagnitude = pow(normalizedMagnitude, profile.inputExponent)
            let magnitude = baseMagnitude * (0.58 + curvedMagnitude * 0.42)
            let speedBoost = 0.85 + speed * 0.4
            let accelerationBoost = 1 + acceleration * profile.accelerationGain
            let velocity = magnitude * profile.velocityScale * speedBoost * accelerationBoost

            return input.sign == .minus ? -velocity : velocity
        }

        private func reengagementDominance(inputVelocity: Double, currentVelocity: Double) -> Double {
            let inputMagnitude = abs(inputVelocity)
            let currentMagnitude = abs(currentVelocity)

            guard inputMagnitude > 0, currentMagnitude > 0 else {
                return 0
            }

            return (currentMagnitude / inputMagnitude).clamped(to: 0 ... 1)
        }

        private func tailRecovery(inputVelocity: Double, currentVelocity: Double) -> Double {
            let dominance = reengagementDominance(inputVelocity: inputVelocity, currentVelocity: currentVelocity)
            return ((0.75 - dominance) / 0.75).clamped(to: 0 ... 1)
        }

        func reengagedDesiredVelocity(for input: Double, currentVelocity: Double) -> Double {
            let inputVelocity = desiredVelocity(for: input)

            guard currentVelocity != 0 else {
                return inputVelocity
            }

            let sameDirection = inputVelocity.sign == currentVelocity.sign
            if sameDirection {
                let carryFactor = (0.06 + response * 0.06 + acceleration * 0.01).clamped(to: 0.06 ... 0.16)
                let ceilingFactor = (1.01 + presetProfile.response * 0.08 + response * 0.06).clamped(to: 1.02 ... 1.12)
                let carriedMagnitude = min(
                    abs(currentVelocity) + abs(inputVelocity) * carryFactor,
                    max(abs(currentVelocity), abs(inputVelocity)) * ceilingFactor
                )
                let recovery = pow(tailRecovery(inputVelocity: inputVelocity, currentVelocity: currentVelocity), 0.8)
                let targetMagnitude = carriedMagnitude + (abs(inputVelocity) - carriedMagnitude) * recovery
                return currentVelocity.sign == .minus ? -targetMagnitude : targetMagnitude
            }

            let brakingBlend = (0.50 + response * 0.20).clamped(to: 0.50 ... 0.82)
            return currentVelocity + (inputVelocity - currentVelocity) * brakingBlend
        }

        func blendFactor(for dt: TimeInterval) -> Double {
            let scaled = presetProfile.response * 0.75 + response * 0.8
            return (scaled * dt * 60).clamped(to: 0.05 ... 1.0)
        }

        func reengagementBlendFactor(for dt: TimeInterval, desiredVelocity: Double, currentVelocity: Double) -> Double {
            let baseBlend = blendFactor(for: dt)
            let softenedBlend = (baseBlend * (0.10 + response * 0.08)).clamped(to: 0.02 ... 0.12)
            let recovery = pow(tailRecovery(inputVelocity: desiredVelocity, currentVelocity: currentVelocity), 0.55)
            return (softenedBlend + (baseBlend - softenedBlend) * recovery).clamped(to: softenedBlend ... baseBlend)
        }

        func reengagementKickFactor(desiredVelocity: Double, currentVelocity: Double) -> Double {
            guard desiredVelocity != 0, currentVelocity != 0, desiredVelocity.sign == currentVelocity.sign else {
                return 0
            }

            let recovery = pow(tailRecovery(inputVelocity: desiredVelocity, currentVelocity: currentVelocity), 0.8)
            let baseKick = (0.04 + response * 0.04).clamped(to: 0.04 ... 0.08)
            let tailKick = (0.14 + response * 0.05 + acceleration * 0.02).clamped(to: 0.14 ... 0.28)
            return (baseKick + tailKick * recovery).clamped(to: 0.04 ... 0.24)
        }

        func momentumDecay(for dt: TimeInterval) -> Double {
            let profile = presetProfile
            let inertiaBoost = ((inertia - 0.65) * 0.05).clamped(to: -0.08 ... 0.10)
            let dtScale = max(dt * 60, 0.25)
            return pow((profile.decay + inertiaBoost).clamped(to: 0.72 ... 0.98), dtScale)
        }
    }

    private let horizontalBehavior: AxisBehavior
    private let verticalBehavior: AxisBehavior

    private var sessionState: SessionState = .idle
    private var lastTickTimestamp: TimeInterval?
    private var lastInputTimestamp: TimeInterval?
    private var pendingInputX = 0.0
    private var pendingInputY = 0.0
    private var desiredVelocityX = 0.0
    private var desiredVelocityY = 0.0
    private var velocityX = 0.0
    private var velocityY = 0.0
    private var touchHasBegun = false
    private var pendingMomentumBegin = false
    private var reengagedFromMomentum = false

    private let inputGrace: TimeInterval = 1.0 / 25.0
    private let stopThreshold = 0.5
    private let axisActivityThreshold = 0.01

    init(smoothed: Scheme.Scrolling.Bidirectional<Scheme.Scrolling.Smoothed>) {
        horizontalBehavior = smoothed.horizontal.map { .smoothed(.init(configuration: $0)) } ?? .passthrough
        verticalBehavior = smoothed.vertical.map { .smoothed(.init(configuration: $0)) } ?? .passthrough
    }

    var isRunning: Bool {
        switch sessionState {
        case .idle:
            return pendingInputX != 0 || pendingInputY != 0
        case .touching, .momentum:
            return true
        }
    }

    var exclusiveActiveAxis: Axis? {
        let horizontalActive = axisIsActive(
            pendingInput: pendingInputX,
            desiredVelocity: desiredVelocityX,
            velocity: velocityX
        )
        let verticalActive = axisIsActive(
            pendingInput: pendingInputY,
            desiredVelocity: desiredVelocityY,
            velocity: velocityY
        )

        switch (horizontalActive, verticalActive) {
        case (true, false):
            return .horizontal
        case (false, true):
            return .vertical
        default:
            return nil
        }
    }

    func resetOtherAxis(ifExclusiveIncomingAxis incomingAxis: Axis) {
        guard let activeAxis = exclusiveActiveAxis,
              activeAxis != incomingAxis else {
            return
        }

        switch activeAxis {
        case .horizontal:
            pendingInputX = 0
            desiredVelocityX = 0
            velocityX = 0
        case .vertical:
            pendingInputY = 0
            desiredVelocityY = 0
            velocityY = 0
        }

        if abs(velocityX) <= stopThreshold,
           abs(velocityY) <= stopThreshold,
           pendingInputX == 0,
           pendingInputY == 0 {
            pendingMomentumBegin = false
            reengagedFromMomentum = false
            if sessionState == .momentum {
                sessionState = .idle
                touchHasBegun = false
            }
        }
    }

    func feed(deltaX: Double, deltaY: Double, timestamp: TimeInterval) {
        pendingInputX += deltaX
        pendingInputY += deltaY
        lastInputTimestamp = timestamp

        if sessionState == .idle, deltaX != 0 || deltaY != 0 {
            sessionState = .touching
            touchHasBegun = false
            pendingMomentumBegin = false
        } else if sessionState == .momentum, deltaX != 0 || deltaY != 0 {
            sessionState = .touching
            touchHasBegun = false
            pendingMomentumBegin = false
            reengagedFromMomentum = true
        }

        if lastTickTimestamp == nil {
            lastTickTimestamp = timestamp
        }
    }

    func advance(to timestamp: TimeInterval) -> Emission? {
        let previousTick = lastTickTimestamp ?? timestamp
        let dt = (timestamp - previousTick).clamped(to: 1.0 / 240.0 ... 1.0 / 24.0)
        lastTickTimestamp = timestamp

        let hasPendingInput = pendingInputX != 0 || pendingInputY != 0
        let hasFreshInput = lastInputTimestamp.map { timestamp - $0 <= inputGrace } ?? false
        let shouldBlendMomentumReengagement = reengagedFromMomentum && hasPendingInput

        let emissionX = advanceAxis(
            behavior: horizontalBehavior,
            pendingInput: &pendingInputX,
            desiredVelocity: &desiredVelocityX,
            velocity: &velocityX,
            hasPendingInput: hasPendingInput,
            hasFreshInput: hasFreshInput,
            reengagedFromMomentum: shouldBlendMomentumReengagement,
            dt: dt
        )
        let emissionY = advanceAxis(
            behavior: verticalBehavior,
            pendingInput: &pendingInputY,
            desiredVelocity: &desiredVelocityY,
            velocity: &velocityY,
            hasPendingInput: hasPendingInput,
            hasFreshInput: hasFreshInput,
            reengagedFromMomentum: shouldBlendMomentumReengagement,
            dt: dt
        )
        reengagedFromMomentum = false

        let hasMovement = abs(emissionX) >= 0.01 || abs(emissionY) >= 0.01
        let shouldContinueMomentum = abs(velocityX) > stopThreshold || abs(velocityY) > stopThreshold

        switch sessionState {
        case .idle:
            return nil

        case .touching:
            if hasFreshInput {
                guard hasMovement else {
                    return nil
                }

                let phase: CGScrollPhase = touchHasBegun ? .changed : .began
                touchHasBegun = true
                return .init(deltaX: emissionX, deltaY: emissionY, scrollPhase: phase, momentumPhase: .none)
            }

            if shouldContinueMomentum {
                sessionState = .momentum
                pendingMomentumBegin = true
                touchHasBegun = false
                return .init(deltaX: 0, deltaY: 0, scrollPhase: .ended, momentumPhase: .none)
            }

            sessionState = .idle
            velocityX = 0
            velocityY = 0
            desiredVelocityX = 0
            desiredVelocityY = 0
            touchHasBegun = false
            return .init(deltaX: emissionX, deltaY: emissionY, scrollPhase: .ended, momentumPhase: .none)

        case .momentum:
            guard hasMovement || shouldContinueMomentum else {
                sessionState = .idle
                velocityX = 0
                velocityY = 0
                desiredVelocityX = 0
                desiredVelocityY = 0
                touchHasBegun = false
                pendingMomentumBegin = false
                return .init(deltaX: 0, deltaY: 0, scrollPhase: nil, momentumPhase: .end)
            }

            if pendingMomentumBegin {
                pendingMomentumBegin = false
                return .init(deltaX: emissionX, deltaY: emissionY, scrollPhase: nil, momentumPhase: .begin)
            }

            return .init(deltaX: emissionX, deltaY: emissionY, scrollPhase: nil, momentumPhase: .continuous)
        }
    }

    private func advanceAxis(
        behavior: AxisBehavior,
        pendingInput: inout Double,
        desiredVelocity: inout Double,
        velocity: inout Double,
        hasPendingInput: Bool,
        hasFreshInput: Bool,
        reengagedFromMomentum: Bool,
        dt: TimeInterval
    ) -> Double {
        switch behavior {
        case .passthrough:
            defer {
                pendingInput = 0
            }
            return pendingInput

        case let .smoothed(tuning):
            if pendingInput != 0 {
                desiredVelocity = reengagedFromMomentum
                    ? tuning.reengagedDesiredVelocity(for: pendingInput, currentVelocity: velocity)
                    : tuning.desiredVelocity(for: pendingInput)
                if reengagedFromMomentum {
                    let kick = tuning.reengagementKickFactor(
                        desiredVelocity: desiredVelocity,
                        currentVelocity: velocity
                    )
                    velocity += (desiredVelocity - velocity) * kick
                }
                pendingInput = 0
            }

            if hasFreshInput || hasPendingInput {
                let blend = reengagedFromMomentum
                    ? tuning.reengagementBlendFactor(
                        for: dt,
                        desiredVelocity: desiredVelocity,
                        currentVelocity: velocity
                    )
                    : tuning.blendFactor(for: dt)
                velocity += (desiredVelocity - velocity) * blend
            } else {
                velocity *= tuning.momentumDecay(for: dt)
            }

            return velocity * dt
        }
    }

    private func axisIsActive(pendingInput: Double, desiredVelocity: Double, velocity: Double) -> Bool {
        abs(pendingInput) >= axisActivityThreshold
            || abs(desiredVelocity) >= axisActivityThreshold
            || abs(velocity) >= axisActivityThreshold
    }
}
