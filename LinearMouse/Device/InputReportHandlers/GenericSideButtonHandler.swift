// MIT License
// Copyright (c) 2021-2025 LinearMouse

import Foundation

/// Handles side button fixes for devices that report only 3 buttons in HID descriptor
/// but actually have side buttons (button 3 and 4).
///
/// Supported devices:
/// - Mi Dual Mode Wireless Mouse Silent Edition (0x2717:0x5014)
/// - Delux M729DB mouse (0x248A:0x8266)
struct GenericSideButtonHandler: InputReportHandler {
    private struct Product: Hashable {
        let vendorID: Int
        let productID: Int
    }

    private static let supportedProducts: Set<Product> = [
        .init(vendorID: 0x2717, productID: 0x5014), // Mi Silent Mouse
        .init(vendorID: 0x248A, productID: 0x8266) // Delux M729DB mouse
    ]

    func matches(vendorID: Int, productID: Int) -> Bool {
        Self.supportedProducts.contains(.init(vendorID: vendorID, productID: productID))
    }

    func handleReport(_ context: InputReportContext, next: (InputReportContext) -> Void) {
        defer { next(context) }

        guard context.report.count >= 2 else {
            return
        }

        // Report format: | Button 0 (1 bit) | ... | Button 4 (1 bit) | Not Used (3 bits) |
        // We only care about bits 3 and 4 (side buttons)
        let buttonStates = context.report[1] & 0x18
        let toggled = context.lastButtonStates ^ buttonStates

        guard toggled != 0 else {
            return
        }

        for button in 3 ... 4 {
            guard toggled & (1 << button) != 0 else {
                continue
            }
            let down = buttonStates & (1 << button) != 0
            simulateButtonEvent(button: button, down: down)
        }

        context.lastButtonStates = buttonStates
    }
}
