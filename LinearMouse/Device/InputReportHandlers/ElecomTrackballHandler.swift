// MIT License
// Copyright (c) 2021-2026 LinearMouse

import Foundation

/// Handles undeclared button bits of supported ELECOM trackballs.
///
/// These trackballs declare only five HID button usages (1 through 5) in their mouse
/// collection. Their additional Fn buttons are transmitted in the same input report in the
/// three upper bits that the descriptor leaves undeclared. macOS discards those bits and does
/// not emit button events.
///
/// This handler reads those bits from the raw input report and synthesizes buttons 5 through
/// 7, leaving the declared buttons to macOS.
///
/// Add other product IDs only after confirming their report layout on-device.
///
/// Supported devices:
/// - ELECOM HUGE TrackBall (0x056E:0x010C)
/// - ELECOM HUGE Trackball (Wireless) (0x056E:0x011C)
struct ElecomTrackballHandler: InputReportHandler {
    private struct Product: Hashable {
        let vendorID: Int
        let productID: Int
    }

    private static let supportedProducts: Set<Product> = [
        .init(vendorID: 0x056E, productID: 0x010C), // ELECOM HUGE TrackBall
        .init(vendorID: 0x056E, productID: 0x011C) // ELECOM HUGE Trackball (Wireless)
    ]

    /// Report format: | Bits 0-4 (HID Button usages 1-5) | Undeclared masks (3 bits) |
    ///
    /// Bits 0 to 4 are declared in the report descriptor and handled by macOS, so only the
    /// upper three bits are of interest here.
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
        // Both supported IDs declare five native buttons and require raw-report observation
        // to synthesize their undeclared button masks.
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
