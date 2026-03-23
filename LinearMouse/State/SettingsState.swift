// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import Foundation
import SwiftUI

class SettingsState: ObservableObject {
    static let shared = SettingsState()

    struct RecordedVirtualButtonEvent {
        let button: Scheme.Buttons.Mapping.Button
        let modifierFlags: CGEventFlags
    }

    struct VirtualButtonRecordingPreparation: Equatable {
        let sessionID: UUID
        var pendingDeviceIDs: Set<Int32>
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

    /// When `recording` is true, `ButtonActionsTransformer` should be temporarily disabled.
    @Published var recording = false

    /// A short-lived preparation phase used while Logitech monitors temporarily divert all controls
    /// for recording. Standard CGEvents can still be recorded immediately.
    @Published private(set) var virtualButtonRecordingPreparation: VirtualButtonRecordingPreparation?

    /// Set by protocol-backed button monitors when a virtual button is pressed during recording.
    /// The recorder uses the event-time modifier snapshot to avoid races with later key-up events.
    @Published var recordedVirtualButtonEvent: RecordedVirtualButtonEvent?

    var isPreparingVirtualButtonRecording: Bool {
        virtualButtonRecordingPreparation != nil
    }

    var virtualButtonRecordingSessionID: UUID? {
        virtualButtonRecordingPreparation?.sessionID
    }

    func beginVirtualButtonRecordingPreparation(for deviceIDs: Set<Int32>) {
        guard !deviceIDs.isEmpty else {
            virtualButtonRecordingPreparation = nil
            return
        }

        virtualButtonRecordingPreparation = .init(
            sessionID: UUID(),
            pendingDeviceIDs: deviceIDs
        )
    }

    func finishVirtualButtonRecordingPreparation(for deviceID: Int32, sessionID: UUID) {
        guard var preparation = virtualButtonRecordingPreparation,
              preparation.sessionID == sessionID else {
            return
        }

        preparation.pendingDeviceIDs.remove(deviceID)
        virtualButtonRecordingPreparation = preparation.pendingDeviceIDs.isEmpty ? nil : preparation
    }

    func endVirtualButtonRecordingPreparation() {
        virtualButtonRecordingPreparation = nil
    }
}
