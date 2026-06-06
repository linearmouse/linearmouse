// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import Foundation
import SwiftUI

class SettingsState: ObservableObject {
    static let shared = SettingsState()

    struct RecordedButtonMappingEvent {
        let recordingSessionID: UUID
        let button: Scheme.Buttons.Mapping.Button?
        let scroll: Scheme.Buttons.Mapping.ScrollDirection?
        let modifierFlags: CGEventFlags
    }

    struct ButtonMappingRecordingSession: Equatable {
        let id: UUID
        var pendingVirtualButtonDeviceIDs: Set<Int32>
    }

    enum Navigation: String, CaseIterable, Hashable {
        case pointer, scrolling, buttons, general

        var title: LocalizedStringKey {
            switch self {
            case .pointer:
                return "Pointer"
            case .scrolling:
                return "Scrolling"
            case .buttons:
                return "Buttons"
            case .general:
                return "General"
            }
        }

        var imageName: String {
            switch self {
            case .pointer:
                return "Pointer"
            case .scrolling:
                return "Scrolling"
            case .buttons:
                return "Buttons"
            case .general:
                return "General"
            }
        }
    }

    @Published var navigation: Navigation? = .pointer

    @Published private(set) var buttonMappingRecordingSession: ButtonMappingRecordingSession?

    /// Set by event sources when a button mapping input is recorded.
    @Published var recordedButtonMappingEvent: RecordedButtonMappingEvent?

    /// `@Published` emits before storing the new value, so session guards use this reentrancy-safe storage.
    private var currentButtonMappingRecordingSession: ButtonMappingRecordingSession?

    /// When `recording` is true, `ButtonActionsTransformer` should be temporarily disabled.
    var recording: Bool {
        currentButtonMappingRecordingSession != nil
    }

    var buttonMappingRecordingSessionID: UUID? {
        currentButtonMappingRecordingSession?.id
    }

    var isPreparingVirtualButtonRecording: Bool {
        currentButtonMappingRecordingSession?.pendingVirtualButtonDeviceIDs.isEmpty == false
    }

    func beginButtonMappingRecording(
        sessionID: UUID,
        pendingVirtualButtonDeviceIDs: Set<Int32> = []
    ) {
        let session = ButtonMappingRecordingSession(
            id: sessionID,
            pendingVirtualButtonDeviceIDs: pendingVirtualButtonDeviceIDs
        )
        currentButtonMappingRecordingSession = session
        buttonMappingRecordingSession = session
        recordedButtonMappingEvent = nil
    }

    func endButtonMappingRecording(sessionID: UUID? = nil) {
        guard sessionID == nil || currentButtonMappingRecordingSession?.id == sessionID else {
            return
        }

        currentButtonMappingRecordingSession = nil
        buttonMappingRecordingSession = nil
        recordedButtonMappingEvent = nil
    }

    func isCurrentButtonMappingRecordingSession(_ sessionID: UUID) -> Bool {
        currentButtonMappingRecordingSession?.id == sessionID
    }

    func finishVirtualButtonRecordingPreparation(for deviceID: Int32, sessionID: UUID) {
        guard var session = currentButtonMappingRecordingSession,
              session.id == sessionID else {
            return
        }

        guard session.pendingVirtualButtonDeviceIDs.remove(deviceID) != nil else {
            return
        }

        currentButtonMappingRecordingSession = session
        buttonMappingRecordingSession = session
    }
}
