// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// State transitions are adapted from libinput's button debouncer.
/// See ThirdPartyNotices/libinput.txt for source and license details.
struct LibinputClickDebouncingEngine {
    enum ButtonState: Equatable {
        case pressed
        case released
    }

    enum Input: Equatable {
        case press
        case release
        case bounceTimeout
        case spuriousTimeout
        case otherButton
    }

    enum Effect: Equatable {
        case emit(ButtonState)
        case setBounceTimer
        case setSpuriousTimer
        case cancelBounceTimer
        case cancelSpuriousTimer
        case spuriousDebouncingEnabled
    }

    enum State: Equatable {
        case isUp
        case isDown
        case isDownWaiting
        case isUpDelaying
        case isUpDelayingSpurious
        case isUpDetectingSpurious
        case isDownDetectingSpurious
        case isUpWaiting
        case isDownDelaying
    }

    private(set) var state: State = .isUp
    private(set) var spuriousDebouncingEnabled = false

    mutating func handle(_ input: Input) -> [Effect] {
        var effects = [Effect]()

        if input == .otherButton {
            effects.append(.cancelBounceTimer)
            effects.append(.cancelSpuriousTimer)
        }

        switch state {
        case .isUp:
            switch input {
            case .press:
                state = .isDownWaiting
                effects.append(.setBounceTimer)
                effects.append(.emit(.pressed))
            case .release:
                // LinearMouse can switch configuration while a button is held.
                // Passing an unmatched release through is safer than risking a
                // stuck button in the receiving application.
                effects.append(.emit(.released))
            case .otherButton, .bounceTimeout, .spuriousTimeout:
                break
            }

        case .isDown:
            switch input {
            case .press:
                // A duplicated press does not change the logical button state.
                break
            case .release:
                effects.append(.setBounceTimer)
                effects.append(.setSpuriousTimer)
                if spuriousDebouncingEnabled {
                    state = .isUpDelayingSpurious
                } else {
                    state = .isUpDetectingSpurious
                    effects.append(.emit(.released))
                }
            case .otherButton, .bounceTimeout, .spuriousTimeout:
                break
            }

        case .isDownWaiting:
            switch input {
            case .release:
                state = .isUpDelaying
                effects.append(.setBounceTimer)
            case .bounceTimeout, .otherButton:
                state = .isDown
            case .press, .spuriousTimeout:
                break
            }

        case .isUpDelaying:
            switch input {
            case .press:
                state = .isDownWaiting
                effects.append(.setBounceTimer)
            case .bounceTimeout, .otherButton:
                state = .isUp
                effects.append(.emit(.released))
            case .release, .spuriousTimeout:
                break
            }

        case .isUpDelayingSpurious:
            switch input {
            case .press:
                state = .isDown
                effects.append(.cancelBounceTimer)
                effects.append(.cancelSpuriousTimer)
            case .spuriousTimeout:
                state = .isUpWaiting
                effects.append(.emit(.released))
            case .otherButton:
                state = .isUp
                effects.append(.emit(.released))
            case .release, .bounceTimeout:
                break
            }

        case .isUpDetectingSpurious:
            switch input {
            case .press:
                state = .isDownDetectingSpurious
                effects.append(.setBounceTimer)
                effects.append(.setSpuriousTimer)
            case .bounceTimeout, .otherButton:
                state = .isUp
            case .spuriousTimeout:
                state = .isUpWaiting
            case .release:
                break
            }

        case .isDownDetectingSpurious:
            switch input {
            case .release:
                state = .isUpDetectingSpurious
                effects.append(.setBounceTimer)
                effects.append(.setSpuriousTimer)
            case .spuriousTimeout:
                state = .isDown
                spuriousDebouncingEnabled = true
                effects.append(.cancelBounceTimer)
                effects.append(.spuriousDebouncingEnabled)
                effects.append(.emit(.pressed))
            case .bounceTimeout, .otherButton:
                state = .isDown
                effects.append(.emit(.pressed))
            case .press:
                break
            }

        case .isUpWaiting:
            switch input {
            case .press:
                state = .isDownDelaying
                effects.append(.setBounceTimer)
            case .bounceTimeout, .otherButton:
                state = .isUp
            case .release, .spuriousTimeout:
                break
            }

        case .isDownDelaying:
            switch input {
            case .release:
                state = .isUpWaiting
                effects.append(.setBounceTimer)
            case .bounceTimeout, .otherButton:
                state = .isDown
                effects.append(.emit(.pressed))
            case .press, .spuriousTimeout:
                break
            }
        }

        return effects
    }
}
