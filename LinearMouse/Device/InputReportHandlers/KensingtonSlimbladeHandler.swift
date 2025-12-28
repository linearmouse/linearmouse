// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation

/// Handles Kensington Slimblade trackball's top buttons.
///
/// The Slimblade has vendor-defined buttons that are reported in a different
/// format than standard HID buttons. This handler parses byte 4 of the input
/// report to detect top-left and top-right button presses.
///
/// Supported devices:
/// - Kensington Slimblade (0x047D:0x2041)
struct KensingtonSlimbladeHandler: InputReportHandler {
    private static let vendorID = 0x047D
    private static let productID = 0x2041

    private static let topLeftMask: UInt8 = 0x1
    private static let topRightMask: UInt8 = 0x2

    func matches(vendorID: Int, productID: Int) -> Bool {
        vendorID == Self.vendorID && productID == Self.productID
    }

    func alwaysNeedsReportObservation() -> Bool {
        // Slimblade needs report monitoring regardless of button count
        true
    }

    func handleReport(_ context: InputReportContext, next: (InputReportContext) -> Void) {
        defer { next(context) }

        guard context.report.count >= 5 else {
            return
        }

        // For Slimblade, byte 4 contains the vendor-defined button states
        let buttonStates = context.report[4]
        let toggled = context.lastButtonStates ^ buttonStates

        guard toggled != 0 else {
            return
        }

        // Check top left button (maps to button 3)
        if toggled & Self.topLeftMask != 0 {
            let down = buttonStates & Self.topLeftMask != 0
            simulateButtonEvent(button: 3, down: down)
        }

        // Check top right button (maps to button 4)
        if toggled & Self.topRightMask != 0 {
            let down = buttonStates & Self.topRightMask != 0
            simulateButtonEvent(button: 4, down: down)
        }

        context.lastButtonStates = buttonStates
    }
}
