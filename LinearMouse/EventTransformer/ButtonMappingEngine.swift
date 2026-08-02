// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import Foundation

/// Shared timing and movement policy for structured button mappings.
///
/// These values intentionally live outside individual mappings. They can be
/// promoted to application preferences later without changing the mapping
/// schema.
struct ButtonMappingPolicy: Equatable {
    static let `default` = Self(
        chordWindow: 0.08,
        longPressDuration: 0.5,
        swipeThreshold: 50,
        swipeDeadZone: 40
    )

    var chordWindow: TimeInterval
    var longPressDuration: TimeInterval
    var swipeThreshold: Double
    var swipeDeadZone: Double

    var chordWindowNanoseconds: UInt64 {
        UInt64(chordWindow * 1_000_000_000)
    }

    var longPressNanoseconds: UInt64 {
        UInt64(longPressDuration * 1_000_000_000)
    }
}

struct ButtonMappingEngine {
    typealias Mapping = Scheme.Buttons.Mapping
    typealias Button = Mapping.Button
    typealias Action = Mapping.Action
    typealias PressAction = Mapping.PressAction

    enum SwipeDirection: Equatable {
        case up, down, left, right
    }

    enum LifecycleEvent: Equatable {
        case began(PressAction, buttons: Set<Button>)
        case ended(PressAction, buttons: Set<Button>)
    }

    enum PointerHandling: Equatable {
        case forwardAsMovement
        case remap(to: CGMouseButton)
    }

    struct Output: Equatable {
        var consumesEvent = false
        /// The current physical event belongs to an unresolved interaction and
        /// must be retained until that interaction commits or falls back.
        var buffersEvent = false
        var actions = [Action]()
        var lifecycleEvents = [LifecycleEvent]()
        var replaysBufferedEvents = false
        /// A pending interaction committed, so its retained physical events
        /// must not be visible to the system or a later fallback stream.
        var discardsBufferedEvents = false
        /// The current event belongs to a fallback stream whose buffered prefix
        /// has already been replayed and must follow the same delivery path.
        var forwardsCapturedEvent = false
        var pointerHandling: PointerHandling?

        mutating func append(_ output: Self) {
            consumesEvent = consumesEvent || output.consumesEvent
            buffersEvent = buffersEvent || output.buffersEvent
            actions += output.actions
            lifecycleEvents += output.lifecycleEvents
            replaysBufferedEvents = replaysBufferedEvents || output.replaysBufferedEvents
            discardsBufferedEvents = discardsBufferedEvents || output.discardsBufferedEvents
            forwardsCapturedEvent = forwardsCapturedEvent || output.forwardsCapturedEvent
            pointerHandling = output.pointerHandling ?? pointerHandling
        }
    }

    enum State: Equatable {
        case idle
        case waitingForChord
        case tracking
        case committed
    }

    private struct Candidate {
        var index: Int
        var mapping: Mapping
        var trigger: Mapping.Trigger
    }

    private enum Commitment {
        case statefulAction
        case impulse
    }

    private struct Resolution {
        var candidate: Candidate
        var activatedAt: UInt64
    }

    private struct Session {
        var startedAt: UInt64
        var candidates: [Candidate]
        var capturesHeldPrefix: Bool
        var capturedButtons: Set<Button>
        var resolution: Resolution?
        var commitment: Commitment?
        var deltaX = 0.0
        var deltaY = 0.0
    }

    private struct ActiveCapture {
        var buttons: Set<Button>
        var remainingButtons: Set<Button>
        var pressAction: PressAction?
        var blocksImpulses: Bool
    }

    private let mappings: [Mapping]
    private let policy: ButtonMappingPolicy
    private var pressedButtons = Set<Button>()
    private var pressedAt = [Button: UInt64]()
    private var session: Session?
    private var activeCaptures = [ActiveCapture]()
    /// Buttons whose buffered down event has already been replayed after a
    /// failed match. Keep ownership until release so the stream stays balanced.
    private var passthroughButtons = Set<Button>()

    init(
        mappings: [Mapping],
        policy: ButtonMappingPolicy = .default
    ) {
        let normalizedMappings = mappings
            .map { mapping in
                var mapping = mapping
                mapping.normalizeAsStructured()
                return mapping
            }
            .filter(\.valid)
            .reduce(into: [Mapping]()) { merged, mapping in
                guard let trigger = mapping.trigger,
                      let index = merged.firstIndex(where: {
                          $0.trigger?.isEquivalent(to: trigger) == true
                      }) else {
                    merged.append(mapping)
                    return
                }
                merged[index].mergeOutcomes(from: mapping)
            }
        self.mappings = normalizedMappings.filter(Self.hasConfiguredAction)
        self.policy = policy
    }

    var state: State {
        if !activeCaptures.isEmpty {
            return .committed
        }
        guard let session else {
            return .idle
        }
        if session.commitment != nil {
            return .committed
        }
        if session.resolution != nil {
            return .tracking
        }
        return .waitingForChord
    }

    /// Whether this engine still owns input that must be routed back to it.
    ///
    /// `passthroughButtons` are deliberately included even though `state` can
    /// be `.idle`: their down events have already been replayed, so their up
    /// events must follow the same transformer route to keep the click stream
    /// balanced.
    var hasActiveInteraction: Bool {
        session != nil || !activeCaptures.isEmpty || !passthroughButtons.isEmpty
    }

    var nextDeadline: UInt64? {
        guard let session, session.commitment == nil else {
            return nil
        }

        if let resolution = session.resolution {
            guard configuredAction(resolution.candidate.mapping.outcomes?.longPress) != nil else {
                return nil
            }
            return resolution.activatedAt &+ policy.longPressNanoseconds
        }

        guard !session.candidates.isEmpty else {
            return nil
        }
        return session.startedAt &+ policy.chordWindowNanoseconds
    }

    mutating func buttonDown(
        _ button: Button,
        modifierFlags: CGEventFlags,
        at timestamp: UInt64
    ) -> Output {
        var output = advance(to: timestamp)

        if pressedButtons.contains(button) {
            if passthroughButtons.contains(button) {
                output.consumesEvent = true
                output.forwardsCapturedEvent = true
            } else if activeCaptures.contains(where: { $0.remainingButtons.contains(button) }) ||
                session?.capturedButtons.contains(button) == true {
                output.consumesEvent = true
            }
            return output
        }

        pressedButtons.insert(button)
        pressedAt[button] = timestamp

        if activeCaptures.contains(where: { $0.remainingButtons.contains(button) }) {
            output.consumesEvent = true
            return output
        }

        if var session {
            if session.capturedButtons.contains(button) {
                output.consumesEvent = true
                return output
            }

            let genericFlags = ModifierState.generic(from: modifierFlags)
            let orderedCandidates = buttonCandidates(containing: button, modifierFlags: genericFlags)
            let takesOverHeldPrefix = session.commitment == nil && orderedCandidates.contains { candidate in
                let heldButtons = Set(candidate.trigger.whileHeld ?? [])
                return !heldButtons.isEmpty && heldButtons.isSubset(of: session.capturedButtons)
            }
            if takesOverHeldPrefix {
                session = .init(
                    startedAt: timestamp,
                    candidates: orderedCandidates,
                    capturesHeldPrefix: hasHeldPrefix(button, modifierFlags: genericFlags),
                    capturedButtons: session.capturedButtons.union([button])
                )
                self.session = session
                output.consumesEvent = true
                output.buffersEvent = true
                output.append(resolveIfPossible(at: timestamp, force: false))
                return output
            }

            if session.resolution == nil,
               session.candidates.contains(where: { $0.trigger.chordButtons.contains(button) }) {
                session.capturedButtons.insert(button)
                self.session = session
                output.consumesEvent = true
                output.buffersEvent = true
                output.append(resolveIfPossible(at: timestamp, force: false))
                return output
            }

            if session.commitment == nil,
               extendsHeldPrefix(
                   with: button,
                   capturedButtons: session.capturedButtons,
                   modifierFlags: genericFlags
               ) {
                session.capturedButtons.insert(button)
                self.session = session
                output.consumesEvent = true
                output.buffersEvent = true
            }
            return output
        }

        let genericFlags = ModifierState.generic(from: modifierFlags)
        let candidates = buttonCandidates(containing: button, modifierFlags: genericFlags)
        let capturesHeldPrefix = hasHeldPrefix(button, modifierFlags: genericFlags)
        guard !candidates.isEmpty || capturesHeldPrefix else {
            return output
        }

        session = .init(
            startedAt: timestamp,
            candidates: candidates,
            capturesHeldPrefix: capturesHeldPrefix,
            capturedButtons: [button]
        )
        output.consumesEvent = true
        output.buffersEvent = true
        output.append(resolveIfPossible(at: timestamp, force: false))
        return output
    }

    /// Tries aliases for one physical control without letting an inapplicable,
    /// more-specific alias hide a less-specific configured mapping.
    mutating func buttonDown(
        firstMatching buttons: [Button],
        modifierFlags: CGEventFlags,
        at timestamp: UInt64
    ) -> (button: Button?, output: Output) {
        let advancedOutput = advance(to: timestamp)
        let advancedEngine = self

        for button in buttons {
            var candidateEngine = advancedEngine
            let eventOutput = candidateEngine.buttonDown(
                button,
                modifierFlags: modifierFlags,
                at: timestamp
            )
            guard eventOutput.consumesEvent else {
                continue
            }

            self = candidateEngine
            var output = advancedOutput
            output.append(eventOutput)
            return (button, output)
        }

        return (nil, advancedOutput)
    }

    mutating func buttonUp(
        _ button: Button,
        modifierFlags _: CGEventFlags,
        at timestamp: UInt64
    ) -> Output {
        var output = advance(to: timestamp)
        defer {
            pressedButtons.remove(button)
            pressedAt[button] = nil
        }

        if passthroughButtons.remove(button) != nil {
            output.consumesEvent = true
            output.forwardsCapturedEvent = true
            return output
        }

        if let activeIndex = activeCaptures.firstIndex(where: { $0.remainingButtons.contains(button) }) {
            var active = activeCaptures[activeIndex]
            output.consumesEvent = true
            if let pressAction = active.pressAction {
                output.lifecycleEvents.append(.ended(pressAction, buttons: active.buttons))
                active.pressAction = nil
            }
            active.remainingButtons.remove(button)
            if active.remainingButtons.isEmpty {
                activeCaptures.remove(at: activeIndex)
            } else {
                activeCaptures[activeIndex] = active
            }
            return output
        }

        guard var session, session.capturedButtons.contains(button) else {
            return output
        }

        output.consumesEvent = true
        output.buffersEvent = true

        if session.resolution == nil {
            output.append(resolveIfPossible(at: timestamp, force: true, releasingButton: button))
            guard let updatedSession = self.session else {
                return output
            }
            session = updatedSession
        }

        if let resolution = session.resolution,
           !resolution.candidate.trigger.chordButtons.contains(button) {
            if session.commitment == nil {
                if let action = configuredAction(resolution.candidate.mapping.outcomes?.shortPress) {
                    output.actions.append(action)
                    session.commitment = .statefulAction
                    output.discardsBufferedEvents = true
                } else {
                    output.append(abandon(session, releasingButton: button))
                    return output
                }
            }

            let remainingCapturedButtons = session.capturedButtons.subtracting([button])
            if remainingCapturedButtons.isDisjoint(with: pressedButtons.subtracting([button])) {
                self.session = nil
            } else {
                self.session = session
            }
            return output
        }

        if session.commitment == nil {
            if let action = configuredAction(session.resolution?.candidate.mapping.outcomes?.shortPress) {
                output.actions.append(action)
                session.commitment = .statefulAction
                output.discardsBufferedEvents = true
                self.session = session
            } else {
                output.append(abandon(session, releasingButton: button))
                return output
            }
        }

        let remainingCapturedButtons = session.capturedButtons.subtracting([button])
        if remainingCapturedButtons.isDisjoint(with: pressedButtons.subtracting([button])) {
            self.session = nil
        }

        return output
    }

    mutating func buttonUp(
        firstMatching buttons: [Button],
        modifierFlags: CGEventFlags,
        at timestamp: UInt64
    ) -> (button: Button?, output: Output) {
        let advancedOutput = advance(to: timestamp)
        let advancedEngine = self

        for button in buttons {
            var candidateEngine = advancedEngine
            let eventOutput = candidateEngine.buttonUp(
                button,
                modifierFlags: modifierFlags,
                at: timestamp
            )
            guard eventOutput.consumesEvent else {
                continue
            }

            self = candidateEngine
            var output = advancedOutput
            output.append(eventOutput)
            return (button, output)
        }

        return (nil, advancedOutput)
    }

    mutating func pointerMoved(
        for button: Button? = nil,
        deltaX: Double,
        deltaY: Double,
        at timestamp: UInt64
    ) -> Output {
        var output = advance(to: timestamp)

        if let button, passthroughButtons.contains(button) {
            output.consumesEvent = true
            output.forwardsCapturedEvent = true
            return output
        }

        if let button,
           let active = activeCaptures.first(where: { $0.remainingButtons.contains(button) }) {
            output.consumesEvent = true
            switch active.pressAction?.behavior {
            case .repeat, .hold:
                output.pointerHandling = .forwardAsMovement
            case .remap:
                if let target = active.pressAction?.action.remappedMouseButton {
                    output.pointerHandling = .remap(to: target)
                }
            case .perform, nil:
                break
            }
            return output
        }

        guard var session else {
            return output
        }

        output.consumesEvent = true
        output.buffersEvent = true
        guard session.commitment == nil else {
            return output
        }

        session.deltaX += deltaX
        session.deltaY += deltaY
        self.session = session

        guard session.resolution != nil else {
            return output
        }

        guard let direction = swipeDirection(deltaX: session.deltaX, deltaY: session.deltaY),
              let action = configuredAction(swipeAction(in: session, direction: direction)) else {
            return output
        }

        output.actions.append(action)
        output.discardsBufferedEvents = true
        session.commitment = .statefulAction
        commit(session)
        return output
    }

    mutating func wheel(
        _ direction: Mapping.ScrollDirection,
        modifierFlags: CGEventFlags,
        at timestamp: UInt64
    ) -> Output {
        var output = advance(to: timestamp)
        let flags = ModifierState.generic(from: modifierFlags)
        let availableButtons = availableButtonsForImpulse

        let candidate = mappings.enumerated()
            .compactMap { index, mapping -> Candidate? in
                guard let trigger = mapping.trigger,
                      case let .wheel(candidateDirection) = trigger.input,
                      candidateDirection == direction,
                      trigger.modifierFlags == flags,
                      Set(trigger.whileHeld ?? []).isSubset(of: availableButtons),
                      configuredAction(mapping.action) != nil else {
                    return nil
                }
                return .init(index: index, mapping: mapping, trigger: trigger)
            }
            .max { lhs, rhs in
                let lhsSpecificity = lhs.trigger.whileHeld?.count ?? 0
                let rhsSpecificity = rhs.trigger.whileHeld?.count ?? 0
                if lhsSpecificity == rhsSpecificity {
                    return lhs.index < rhs.index
                }
                return lhsSpecificity < rhsSpecificity
            }

        guard let candidate, let action = configuredAction(candidate.mapping.action) else {
            return output
        }

        output.consumesEvent = true
        output.actions.append(action)

        let heldButtons = Set(candidate.trigger.whileHeld ?? [])
        if var session, !heldButtons.isDisjoint(with: session.capturedButtons) {
            session.commitment = .impulse
            commit(session, blocksImpulses: false)
            output.discardsBufferedEvents = true
        }

        return output
    }

    mutating func advance(to timestamp: UInt64) -> Output {
        var output = Output()
        guard let session, session.commitment == nil else {
            return output
        }

        if session.resolution == nil,
           !session.candidates.isEmpty,
           timestamp >= session.startedAt &+ policy.chordWindowNanoseconds {
            output.append(resolveIfPossible(at: timestamp, force: true))
        }

        guard var updatedSession = self.session,
              updatedSession.commitment == nil,
              let resolution = updatedSession.resolution,
              timestamp >= resolution.activatedAt &+ policy.longPressNanoseconds,
              let action = configuredAction(resolution.candidate.mapping.outcomes?.longPress) else {
            return output
        }

        output.actions.append(action)
        output.discardsBufferedEvents = true
        updatedSession.commitment = .statefulAction
        commit(updatedSession)
        return output
    }

    mutating func reset() -> Output {
        let shouldReplay = session != nil && session?.commitment == nil
        let lifecycleEvents = activeCaptures.compactMap { active -> LifecycleEvent? in
            guard let pressAction = active.pressAction else {
                return nil
            }
            return .ended(pressAction, buttons: active.buttons)
        }
        session = nil
        activeCaptures.removeAll()
        passthroughButtons.removeAll()
        pressedButtons.removeAll()
        pressedAt.removeAll()
        return .init(lifecycleEvents: lifecycleEvents, replaysBufferedEvents: shouldReplay)
    }

    /// Cancels an interaction after a higher-priority recognizer claims the
    /// same physical button stream, such as Gesture Button recognizing a drag.
    mutating func cancelInteractions(containing button: Button) -> Output {
        var canceled = false
        var canceledPendingSession = false
        var lifecycleEvents = [LifecycleEvent]()

        if session?.capturedButtons.contains(button) == true {
            session = nil
            canceled = true
            canceledPendingSession = true
        }

        for index in activeCaptures.indices.reversed()
            where activeCaptures[index].buttons.contains(button) {
            var active = activeCaptures[index]
            if let pressAction = active.pressAction {
                lifecycleEvents.append(.ended(pressAction, buttons: active.buttons))
            }

            active.pressAction = nil
            active.remainingButtons.remove(button)
            if active.remainingButtons.isEmpty {
                activeCaptures.remove(at: index)
            } else {
                activeCaptures[index] = active
            }
            canceled = true
        }

        guard canceled else {
            return .init()
        }

        pressedButtons.remove(button)
        pressedAt[button] = nil
        passthroughButtons.remove(button)
        return .init(
            consumesEvent: true,
            lifecycleEvents: lifecycleEvents,
            discardsBufferedEvents: canceledPendingSession
        )
    }

    private var availableButtonsForImpulse: Set<Button> {
        let capturedButtons = activeCaptures.reduce(into: Set<Button>()) {
            if $1.blocksImpulses {
                $0.formUnion($1.remainingButtons)
            }
        }
        return pressedButtons.subtracting(capturedButtons)
    }

    private func buttonCandidates(containing button: Button, modifierFlags: CGEventFlags) -> [Candidate] {
        mappings.enumerated().compactMap { index, mapping in
            guard let trigger = mapping.trigger,
                  case .button = trigger.input,
                  trigger.chordButtons.contains(button),
                  trigger.modifierFlags == modifierFlags,
                  Set(trigger.whileHeld ?? []).isSubset(of: pressedButtons),
                  trigger.statefulButtons.isDisjoint(with: activelyCapturedButtons) else {
                return nil
            }
            return .init(index: index, mapping: mapping, trigger: trigger)
        }
    }

    private func hasHeldPrefix(_ button: Button, modifierFlags: CGEventFlags) -> Bool {
        mappings.contains { mapping in
            guard let trigger = mapping.trigger,
                  trigger.modifierFlags == modifierFlags,
                  trigger.statefulButtons.isDisjoint(with: activelyCapturedButtons) else {
                return false
            }
            return trigger.whileHeld?.contains(button) == true
        }
    }

    private func extendsHeldPrefix(
        with button: Button,
        capturedButtons: Set<Button>,
        modifierFlags: CGEventFlags
    ) -> Bool {
        mappings.contains { mapping in
            guard let trigger = mapping.trigger,
                  trigger.modifierFlags == modifierFlags,
                  let whileHeld = trigger.whileHeld,
                  trigger.statefulButtons.isDisjoint(with: activelyCapturedButtons) else {
                return false
            }
            let heldButtons = Set(whileHeld)
            return heldButtons.contains(button) && capturedButtons.isSubset(of: heldButtons)
        }
    }

    private mutating func resolveIfPossible(
        at timestamp: UInt64,
        force: Bool,
        releasingButton: Button? = nil
    ) -> Output {
        guard var session, session.resolution == nil else {
            return .init()
        }

        let completed = session.candidates.filter { candidate in
            candidate.trigger.chordButtons.isSubset(of: pressedButtons) &&
                chordIsWithinWindow(candidate.trigger.chordButtons) &&
                Set(candidate.trigger.whileHeld ?? []).isSubset(of: pressedButtons)
        }

        guard let best = completed.max(by: candidateIsLessSpecific) else {
            if force, !session.capturesHeldPrefix {
                return abandon(session, releasingButton: releasingButton)
            }
            return .init()
        }

        let shouldWaitForLongerChord = !force && session.candidates.contains { candidate in
            candidate.trigger.chordButtons.count > best.trigger.chordButtons.count &&
                best.trigger.chordButtons.isSubset(of: candidate.trigger.chordButtons) &&
                !candidate.trigger.chordButtons.isSubset(of: pressedButtons)
        }
        guard !shouldWaitForLongerChord else {
            return .init()
        }

        let activatedAt = best.trigger.chordButtons.compactMap { pressedAt[$0] }.max() ?? timestamp
        session.resolution = .init(candidate: best, activatedAt: activatedAt)
        if let pressAction = configuredPressAction(best.mapping.outcomes?.press) {
            session.commitment = .statefulAction
            let buttons = best.trigger.statefulButtons
            self.session = session
            commit(session, pressAction: pressAction)
            return .init(
                lifecycleEvents: [.began(pressAction, buttons: buttons)],
                discardsBufferedEvents: true
            )
        }
        if let direction = swipeDirection(deltaX: session.deltaX, deltaY: session.deltaY),
           let action = configuredAction(swipeAction(in: session, direction: direction)) {
            session.commitment = .statefulAction
            commit(session)
            return .init(actions: [action], discardsBufferedEvents: true)
        }
        self.session = session
        return .init()
    }

    private func candidateIsLessSpecific(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        let lhsSpecificity = lhs.trigger.specificityScore
        let rhsSpecificity = rhs.trigger.specificityScore
        if lhsSpecificity == rhsSpecificity {
            return lhs.index < rhs.index
        }
        return lhsSpecificity < rhsSpecificity
    }

    private func chordIsWithinWindow(_ buttons: Set<Button>) -> Bool {
        let timestamps = buttons.compactMap { pressedAt[$0] }
        guard timestamps.count == buttons.count,
              let first = timestamps.min(),
              let last = timestamps.max() else {
            return false
        }
        return last &- first <= policy.chordWindowNanoseconds
    }

    private func swipeDirection(deltaX: Double, deltaY: Double) -> SwipeDirection? {
        let absX = abs(deltaX)
        let absY = abs(deltaY)
        let magnitude = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard magnitude >= policy.swipeThreshold else {
            return nil
        }

        if absX > absY {
            guard absY < policy.swipeDeadZone else {
                return nil
            }
            return deltaX > 0 ? .right : .left
        }

        guard absX < policy.swipeDeadZone else {
            return nil
        }
        return deltaY > 0 ? .down : .up
    }

    private func swipeAction(in session: Session, direction: SwipeDirection) -> Action? {
        guard let swipe = session.resolution?.candidate.mapping.outcomes?.swipe else {
            return nil
        }
        switch direction {
        case .up:
            return swipe.up
        case .down:
            return swipe.down
        case .left:
            return swipe.left
        case .right:
            return swipe.right
        }
    }

    private func configuredAction(_ action: Action?) -> Action? {
        Self.isConfigured(action) ? action : nil
    }

    private static func hasConfiguredAction(_ mapping: Mapping) -> Bool {
        guard let trigger = mapping.trigger else {
            return false
        }

        switch trigger.input {
        case .wheel:
            return isConfigured(mapping.action)
        case .button:
            let outcomes = mapping.outcomes
            return isConfigured(outcomes?.press?.action) ||
                isConfigured(outcomes?.shortPress) ||
                isConfigured(outcomes?.longPress) ||
                isConfigured(outcomes?.swipe?.up) ||
                isConfigured(outcomes?.swipe?.down) ||
                isConfigured(outcomes?.swipe?.left) ||
                isConfigured(outcomes?.swipe?.right)
        }
    }

    private static func isConfigured(_ action: Action?) -> Bool {
        guard let action else {
            return false
        }
        if case .arg0(.auto) = action {
            return false
        }
        return true
    }

    private func configuredPressAction(_ pressAction: PressAction?) -> PressAction? {
        guard let pressAction, configuredAction(pressAction.action) != nil else {
            return nil
        }
        return pressAction
    }

    private var activelyCapturedButtons: Set<Button> {
        activeCaptures.reduce(into: passthroughButtons) {
            $0.formUnion($1.remainingButtons)
        }
    }

    private mutating func abandon(_ session: Session, releasingButton: Button? = nil) -> Output {
        var remainingButtons = session.capturedButtons.intersection(pressedButtons)
        if let releasingButton {
            remainingButtons.remove(releasingButton)
        }
        passthroughButtons.formUnion(remainingButtons)
        self.session = nil
        return .init(replaysBufferedEvents: true)
    }

    private mutating func commit(
        _ session: Session,
        pressAction: PressAction? = nil,
        blocksImpulses: Bool = true
    ) {
        let buttons = session.resolution?.candidate.trigger.statefulButtons ?? session.capturedButtons
        activeCaptures.append(.init(
            buttons: buttons,
            remainingButtons: buttons.intersection(pressedButtons),
            pressAction: pressAction,
            blocksImpulses: blocksImpulses
        ))
        self.session = nil
    }
}
