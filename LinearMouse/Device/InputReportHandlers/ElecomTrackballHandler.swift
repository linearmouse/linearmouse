// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Handles the extra Fn buttons of ELECOM trackballs.
///
/// The HID report descriptor of these devices declares only 5 buttons in its mouse
/// collection, which are taken up by left, right, middle and the two thumb buttons.
/// The remaining Fn buttons are still reported in the same input report, but in the
/// three bits that the descriptor declares as padding, so macOS discards them and no
/// `otherMouseDown` event is ever generated.
///
/// This handler reads those undeclared bits out of the raw input report and simulates
/// the corresponding button events.
///
/// Other ELECOM trackballs share this report layout, so they can be supported by adding
/// their product IDs below once the layout has been confirmed on the device.
///
/// Supported devices:
/// - ELECOM HUGE TrackBall (0x056E:0x010C)
struct ElecomTrackballHandler: InputReportHandler {
    private struct Product: Hashable {
        let vendorID: Int
        let productID: Int
    }

    private static let supportedProducts: Set<Product> = [
        .init(vendorID: 0x056E, productID: 0x010C) // ELECOM HUGE TrackBall
    ]

    /// Report format: | Button 0 (1 bit) | ... | Button 4 (1 bit) | Fn buttons (3 bits) |
    ///
    /// Buttons 0 to 4 are declared in the report descriptor and handled by macOS, so only
    /// the upper three bits are of interest here.
    private static let fnButtonsMask: UInt8 = 0xE0

    /// Bit 5 to 7 are mapped to button 5 to 7, the first button numbers not already used by
    /// the buttons macOS recognizes.
    private static let fnButtonBits = 5 ... 7

    private let emit: MouseButtonEmitter

    init(emit: @escaping MouseButtonEmitter = SyntheticMouseButtonEventEmitter.post) {
        self.emit = emit
    }

    func matches(vendorID: Int, productID: Int) -> Bool {
        Self.supportedProducts.contains(.init(vendorID: vendorID, productID: productID))
    }

    func alwaysNeedsReportObservation() -> Bool {
        // The device reports 5 buttons, so the button count heuristic would not enable
        // report observation on its own.
        true
    }

    func handleReport(_ context: InputReportContext, next: (InputReportContext) -> Void) {
        defer { next(context) }

        // Byte 0 is the report ID, byte 1 holds the button states.
        guard context.report.count >= 2, context.report[0] == 0x01 else {
            return
        }

        let buttonStates = context.report[1] & Self.fnButtonsMask
        let toggled = context.lastButtonStates ^ buttonStates

        guard toggled != 0 else {
            return
        }

        for button in Self.fnButtonBits {
            guard toggled & (1 << button) != 0 else {
                continue
            }
            let down = buttonStates & (1 << button) != 0
            emit(button, down)
        }

        context.lastButtonStates = buttonStates
    }
}
