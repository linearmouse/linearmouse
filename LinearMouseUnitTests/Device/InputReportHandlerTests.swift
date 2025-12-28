// MIT License
// Copyright (c) 2021-2025 LinearMouse

@testable import LinearMouse
import XCTest

final class InputReportHandlerTests: XCTestCase {
    // MARK: - InputReportContext Tests

    func testContextInitialization() {
        let report = Data([0x00, 0x18, 0x00])
        let context = InputReportContext(report: report, lastButtonStates: 0x00)

        XCTAssertEqual(context.report, report)
        XCTAssertEqual(context.lastButtonStates, 0x00)
    }

    func testContextMutation() {
        let context = InputReportContext(report: Data(), lastButtonStates: 0x00)
        context.lastButtonStates = 0x18

        XCTAssertEqual(context.lastButtonStates, 0x18)
    }

    // MARK: - GenericSideButtonHandler Tests

    func testGenericHandlerMatchesMiMouse() {
        let handler = GenericSideButtonHandler()

        XCTAssertTrue(handler.matches(vendorID: 0x2717, productID: 0x5014))
    }

    func testGenericHandlerMatchesDeluxMouse() {
        let handler = GenericSideButtonHandler()

        XCTAssertTrue(handler.matches(vendorID: 0x248A, productID: 0x8266))
    }

    func testGenericHandlerDoesNotMatchUnknownDevice() {
        let handler = GenericSideButtonHandler()

        XCTAssertFalse(handler.matches(vendorID: 0x1234, productID: 0x5678))
    }

    func testGenericHandlerDoesNotAlwaysNeedReportObservation() {
        let handler = GenericSideButtonHandler()

        XCTAssertFalse(handler.alwaysNeedsReportObservation())
    }

    func testGenericHandlerCallsNext() {
        let handler = GenericSideButtonHandler()
        let context = InputReportContext(report: Data([0x00, 0x00]), lastButtonStates: 0x00)

        var nextCalled = false
        handler.handleReport(context) { _ in
            nextCalled = true
        }

        XCTAssertTrue(nextCalled)
    }

    func testGenericHandlerCallsNextEvenWithShortReport() {
        let handler = GenericSideButtonHandler()
        let context = InputReportContext(report: Data([0x00]), lastButtonStates: 0x00)

        var nextCalled = false
        handler.handleReport(context) { _ in
            nextCalled = true
        }

        XCTAssertTrue(nextCalled)
    }

    func testGenericHandlerUpdatesButtonStates() {
        let handler = GenericSideButtonHandler()
        // Button 3 pressed: bit 3 set (0x08)
        let context = InputReportContext(report: Data([0x00, 0x08]), lastButtonStates: 0x00)

        handler.handleReport(context) { _ in }

        XCTAssertEqual(context.lastButtonStates, 0x08)
    }

    func testGenericHandlerDetectsButton3Toggle() {
        let handler = GenericSideButtonHandler()
        // Button 3 pressed: bit 3 set (0x08)
        let context = InputReportContext(report: Data([0x00, 0x08]), lastButtonStates: 0x00)

        handler.handleReport(context) { _ in }

        // State should be updated
        XCTAssertEqual(context.lastButtonStates, 0x08)
    }

    func testGenericHandlerDetectsButton4Toggle() {
        let handler = GenericSideButtonHandler()
        // Button 4 pressed: bit 4 set (0x10)
        let context = InputReportContext(report: Data([0x00, 0x10]), lastButtonStates: 0x00)

        handler.handleReport(context) { _ in }

        XCTAssertEqual(context.lastButtonStates, 0x10)
    }

    func testGenericHandlerDetectsBothButtonsToggle() {
        let handler = GenericSideButtonHandler()
        // Both buttons pressed: bits 3 and 4 set (0x18)
        let context = InputReportContext(report: Data([0x00, 0x18]), lastButtonStates: 0x00)

        handler.handleReport(context) { _ in }

        XCTAssertEqual(context.lastButtonStates, 0x18)
    }

    func testGenericHandlerNoChangeWhenNoToggle() {
        let handler = GenericSideButtonHandler()
        // Same state as before
        let context = InputReportContext(report: Data([0x00, 0x08]), lastButtonStates: 0x08)

        handler.handleReport(context) { _ in }

        // State should remain the same
        XCTAssertEqual(context.lastButtonStates, 0x08)
    }

    // MARK: - KensingtonSlimbladeHandler Tests

    func testSlimbladeHandlerMatchesSlimblade() {
        let handler = KensingtonSlimbladeHandler()

        XCTAssertTrue(handler.matches(vendorID: 0x047D, productID: 0x2041))
    }

    func testSlimbladeHandlerDoesNotMatchOtherDevice() {
        let handler = KensingtonSlimbladeHandler()

        XCTAssertFalse(handler.matches(vendorID: 0x1234, productID: 0x5678))
    }

    func testSlimbladeHandlerAlwaysNeedsReportObservation() {
        let handler = KensingtonSlimbladeHandler()

        XCTAssertTrue(handler.alwaysNeedsReportObservation())
    }

    func testSlimbladeHandlerCallsNext() {
        let handler = KensingtonSlimbladeHandler()
        let context = InputReportContext(
            report: Data([0x00, 0x00, 0x00, 0x00, 0x00]),
            lastButtonStates: 0x00
        )

        var nextCalled = false
        handler.handleReport(context) { _ in
            nextCalled = true
        }

        XCTAssertTrue(nextCalled)
    }

    func testSlimbladeHandlerCallsNextEvenWithShortReport() {
        let handler = KensingtonSlimbladeHandler()
        let context = InputReportContext(report: Data([0x00, 0x00]), lastButtonStates: 0x00)

        var nextCalled = false
        handler.handleReport(context) { _ in
            nextCalled = true
        }

        XCTAssertTrue(nextCalled)
    }

    func testSlimbladeHandlerDetectsTopLeftButton() {
        let handler = KensingtonSlimbladeHandler()
        // Top left button pressed: bit 0 set in byte 4
        let context = InputReportContext(
            report: Data([0x00, 0x00, 0x00, 0x00, 0x01]),
            lastButtonStates: 0x00
        )

        handler.handleReport(context) { _ in }

        XCTAssertEqual(context.lastButtonStates, 0x01)
    }

    func testSlimbladeHandlerDetectsTopRightButton() {
        let handler = KensingtonSlimbladeHandler()
        // Top right button pressed: bit 1 set in byte 4
        let context = InputReportContext(
            report: Data([0x00, 0x00, 0x00, 0x00, 0x02]),
            lastButtonStates: 0x00
        )

        handler.handleReport(context) { _ in }

        XCTAssertEqual(context.lastButtonStates, 0x02)
    }

    func testSlimbladeHandlerDetectsBothTopButtons() {
        let handler = KensingtonSlimbladeHandler()
        // Both top buttons pressed: bits 0 and 1 set in byte 4
        let context = InputReportContext(
            report: Data([0x00, 0x00, 0x00, 0x00, 0x03]),
            lastButtonStates: 0x00
        )

        handler.handleReport(context) { _ in }

        XCTAssertEqual(context.lastButtonStates, 0x03)
    }

    // MARK: - InputReportHandlerRegistry Tests

    func testRegistryFindsMiMouseHandler() {
        let handlers = InputReportHandlerRegistry.handlers(for: 0x2717, productID: 0x5014)

        XCTAssertEqual(handlers.count, 1)
        XCTAssertTrue(handlers.first is GenericSideButtonHandler)
    }

    func testRegistryFindsSlimbladeHandler() {
        let handlers = InputReportHandlerRegistry.handlers(for: 0x047D, productID: 0x2041)

        XCTAssertEqual(handlers.count, 1)
        XCTAssertTrue(handlers.first is KensingtonSlimbladeHandler)
    }

    func testRegistryReturnsEmptyForUnknownDevice() {
        let handlers = InputReportHandlerRegistry.handlers(for: 0x1234, productID: 0x5678)

        XCTAssertTrue(handlers.isEmpty)
    }

    // MARK: - Handler Chain Tests

    func testHandlerChainExecutesInOrder() {
        var executionOrder: [String] = []

        let context = InputReportContext(report: Data([0x00, 0x00]), lastButtonStates: 0x00)

        // Create a simple chain manually
        let handler1 = MockHandler(name: "first") { executionOrder.append($0) }
        let handler2 = MockHandler(name: "second") { executionOrder.append($0) }

        let handlers: [InputReportHandler] = [handler1, handler2]

        let chain = handlers.reversed().reduce({ (_: InputReportContext) in }) { next, handler in
            { context in handler.handleReport(context, next: next) }
        }
        chain(context)

        XCTAssertEqual(executionOrder, ["first", "second"])
    }

    func testHandlerChainCanBeInterrupted() {
        var executionOrder: [String] = []

        let context = InputReportContext(report: Data([0x00, 0x00]), lastButtonStates: 0x00)

        // Create a chain where first handler doesn't call next
        let handler1 = MockHandler(name: "first", callNext: false) { executionOrder.append($0) }
        let handler2 = MockHandler(name: "second") { executionOrder.append($0) }

        let handlers: [InputReportHandler] = [handler1, handler2]

        let chain = handlers.reversed().reduce({ (_: InputReportContext) in }) { next, handler in
            { context in handler.handleReport(context, next: next) }
        }
        chain(context)

        XCTAssertEqual(executionOrder, ["first"])
    }

    func testHandlerChainPassesContextThrough() {
        let context = InputReportContext(report: Data([0x00, 0x00]), lastButtonStates: 0x00)

        let handler1 = MockHandler(name: "first", modifyState: 0x01) { _ in }
        let handler2 = MockHandler(name: "second", modifyState: 0x02) { _ in }

        let handlers: [InputReportHandler] = [handler1, handler2]

        let chain = handlers.reversed().reduce({ (_: InputReportContext) in }) { next, handler in
            { context in handler.handleReport(context, next: next) }
        }
        chain(context)

        // Both handlers should have modified the state
        XCTAssertEqual(context.lastButtonStates, 0x03)
    }
}

// MARK: - Mock Handler for Testing

private struct MockHandler: InputReportHandler {
    let name: String
    let callNext: Bool
    let modifyState: UInt8
    let onExecute: (String) -> Void

    init(name: String, callNext: Bool = true, modifyState: UInt8 = 0, onExecute: @escaping (String) -> Void) {
        self.name = name
        self.callNext = callNext
        self.modifyState = modifyState
        self.onExecute = onExecute
    }

    func matches(vendorID _: Int, productID _: Int) -> Bool {
        true
    }

    func handleReport(_ context: InputReportContext, next: (InputReportContext) -> Void) {
        onExecute(name)
        context.lastButtonStates |= modifyState

        if callNext {
            next(context)
        }
    }
}
