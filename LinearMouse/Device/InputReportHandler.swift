// MIT License
// Copyright (c) 2021-2026 LinearMouse

import CoreGraphics
import Foundation

typealias MouseButtonEmitter = (_ button: Int, _ down: Bool) -> Void

enum SyntheticMouseButtonEventEmitter {
    static func post(button: Int, down: Bool) {
        guard let location = CGEvent(source: nil)?.location,
              let mouseButton = CGMouseButton(rawValue: UInt32(button)),
              let event = CGEvent(
                  mouseEventSource: nil,
                  mouseType: down ? .otherMouseDown : .otherMouseUp,
                  mouseCursorPosition: location,
                  mouseButton: mouseButton
              ) else {
            return
        }

        event.flags = ModifierState.normalize(ModifierState.shared.currentFlags)
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        event.isLinearMouseSyntheticEvent = true
        event.post(tap: .cghidEventTap)
    }
}

/// Context passed through the handler chain
class InputReportContext {
    let report: Data
    var lastButtonStates: UInt8

    init(report: Data, lastButtonStates: UInt8) {
        self.report = report
        self.lastButtonStates = lastButtonStates
    }
}

protocol InputReportHandler {
    /// Check if this handler should be used for the given device
    func matches(vendorID: Int, productID: Int) -> Bool

    /// Whether report observation is needed regardless of button count
    /// Most devices only need observation when buttonCount == 3
    func alwaysNeedsReportObservation() -> Bool

    /// Handle input report and simulate button events as needed
    /// Call `next(context)` to pass control to the next handler in the chain
    func handleReport(_ context: InputReportContext, next: (InputReportContext) -> Void)
}

extension InputReportHandler {
    func alwaysNeedsReportObservation() -> Bool {
        false
    }
}

enum InputReportHandlerRegistry {
    static let handlers: [InputReportHandler] = [
        GenericSideButtonHandler(),
        KensingtonSlimbladeHandler()
    ]

    static func handlers(for vendorID: Int, productID: Int) -> [InputReportHandler] {
        handlers.filter { $0.matches(vendorID: vendorID, productID: productID) }
    }
}
