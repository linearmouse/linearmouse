// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class InputReportHandlerTests: XCTestCase {
    /// Captures emissions from the handlers so tests can assert against them without
    /// posting real `otherMouseDown` events into the OS.
    private final class EmissionRecorder {
        private(set) var events: [(button: Int, down: Bool)] = []

        var emit: MouseButtonEmitter {
            { [weak self] button, down in
                self?.events.append((button, down))
            }
        }
    }

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
        let handler = GenericSideButtonHandler { _, _ in }
        let context = InputReportContext(report: Data([0x00, 0x00]), lastButtonStates: 0x00)

        var nextCalled = false
        handler.handleReport(context) { _ in
            nextCalled = true
        }

        XCTAssertTrue(nextCalled)
    }

    func testGenericHandlerCallsNextEvenWithShortReport() {
        let handler = GenericSideButtonHandler { _, _ in }
        let context = InputReportContext(report: Data([0x00]), lastButtonStates: 0x00)

        var nextCalled = false
        handler.handleReport(context) { _ in
            nextCalled = true
        }

        XCTAssertTrue(nextCalled)
    }

    func testGenericHandlerUpdatesButtonStates() {
        let recorder = EmissionRecorder()
        let handler = GenericSideButtonHandler(emit: recorder.emit)
        // Button 3 pressed: bit 3 set (0x08)
        let context = InputReportContext(report: Data([0x00, 0x08]), lastButtonStates: 0x00)

        handler.handleReport(context) { _ in }

        XCTAssertEqual(context.lastButtonStates, 0x08)
    }

    func testGenericHandlerDetectsButton3Toggle() {
        let recorder = EmissionRecorder()
        let handler = GenericSideButtonHandler(emit: recorder.emit)
        // Button 3 pressed: bit 3 set (0x08)
        let context = InputReportContext(report: Data([0x00, 0x08]), lastButtonStates: 0x00)

        handler.handleReport(context) { _ in }

        XCTAssertEqual(context.lastButtonStates, 0x08)
        XCTAssertEqual(recorder.events.map(\.button), [3])
        XCTAssertEqual(recorder.events.map(\.down), [true])
    }

    func testGenericHandlerEmitsButton3ReleaseOnUp() {
        let recorder = EmissionRecorder()
        let handler = GenericSideButtonHandler(emit: recorder.emit)
        let context = InputReportContext(report: Data([0x00, 0x00]), lastButtonStates: 0x08)

        handler.handleReport(context) { _ in }

        XCTAssertEqual(context.lastButtonStates, 0x00)
        XCTAssertEqual(recorder.events.map(\.button), [3])
        XCTAssertEqual(recorder.events.map(\.down), [false])
    }

    func testGenericHandlerDetectsButton4Toggle() {
        let recorder = EmissionRecorder()
        let handler = GenericSideButtonHandler(emit: recorder.emit)
        // Button 4 pressed: bit 4 set (0x10)
        let context = InputReportContext(report: Data([0x00, 0x10]), lastButtonStates: 0x00)

        handler.handleReport(context) { _ in }

        XCTAssertEqual(context.lastButtonStates, 0x10)
        XCTAssertEqual(recorder.events.map(\.button), [4])
        XCTAssertEqual(recorder.events.map(\.down), [true])
    }

    func testGenericHandlerDetectsBothButtonsToggle() {
        let recorder = EmissionRecorder()
        let handler = GenericSideButtonHandler(emit: recorder.emit)
        // Both buttons pressed: bits 3 and 4 set (0x18)
        let context = InputReportContext(report: Data([0x00, 0x18]), lastButtonStates: 0x00)

        handler.handleReport(context) { _ in }

        XCTAssertEqual(context.lastButtonStates, 0x18)
        XCTAssertEqual(recorder.events.map(\.button), [3, 4])
        XCTAssertEqual(recorder.events.map(\.down), [true, true])
    }

    func testGenericHandlerNoChangeWhenNoToggle() {
        let recorder = EmissionRecorder()
        let handler = GenericSideButtonHandler(emit: recorder.emit)
        // Same state as before
        let context = InputReportContext(report: Data([0x00, 0x08]), lastButtonStates: 0x08)

        handler.handleReport(context) { _ in }

        XCTAssertEqual(context.lastButtonStates, 0x08)
        XCTAssertTrue(recorder.events.isEmpty)
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
        let handler = KensingtonSlimbladeHandler { _, _ in }
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
        let handler = KensingtonSlimbladeHandler { _, _ in }
        let context = InputReportContext(report: Data([0x00, 0x00]), lastButtonStates: 0x00)

        var nextCalled = false
        handler.handleReport(context) { _ in
            nextCalled = true
        }

        XCTAssertTrue(nextCalled)
    }

    func testSlimbladeHandlerDetectsTopLeftButton() {
        let recorder = EmissionRecorder()
        let handler = KensingtonSlimbladeHandler(emit: recorder.emit)
        // Top left button pressed: bit 0 set in byte 4
        let context = InputReportContext(
            report: Data([0x00, 0x00, 0x00, 0x00, 0x01]),
            lastButtonStates: 0x00
        )

        handler.handleReport(context) { _ in }

        XCTAssertEqual(context.lastButtonStates, 0x01)
        XCTAssertEqual(recorder.events.map(\.button), [3])
        XCTAssertEqual(recorder.events.map(\.down), [true])
    }

    func testSlimbladeHandlerEmitsTopLeftReleaseOnUp() {
        let recorder = EmissionRecorder()
        let handler = KensingtonSlimbladeHandler(emit: recorder.emit)
        let context = InputReportContext(
            report: Data([0x00, 0x00, 0x00, 0x00, 0x00]),
            lastButtonStates: 0x01
        )

        handler.handleReport(context) { _ in }

        XCTAssertEqual(context.lastButtonStates, 0x00)
        XCTAssertEqual(recorder.events.map(\.button), [3])
        XCTAssertEqual(recorder.events.map(\.down), [false])
    }

    func testSlimbladeHandlerDetectsTopRightButton() {
        let recorder = EmissionRecorder()
        let handler = KensingtonSlimbladeHandler(emit: recorder.emit)
        // Top right button pressed: bit 1 set in byte 4
        let context = InputReportContext(
            report: Data([0x00, 0x00, 0x00, 0x00, 0x02]),
            lastButtonStates: 0x00
        )

        handler.handleReport(context) { _ in }

        XCTAssertEqual(context.lastButtonStates, 0x02)
        XCTAssertEqual(recorder.events.map(\.button), [4])
        XCTAssertEqual(recorder.events.map(\.down), [true])
    }

    func testSlimbladeHandlerDetectsBothTopButtons() {
        let recorder = EmissionRecorder()
        let handler = KensingtonSlimbladeHandler(emit: recorder.emit)
        // Both top buttons pressed: bits 0 and 1 set in byte 4
        let context = InputReportContext(
            report: Data([0x00, 0x00, 0x00, 0x00, 0x03]),
            lastButtonStates: 0x00
        )

        handler.handleReport(context) { _ in }

        XCTAssertEqual(context.lastButtonStates, 0x03)
        XCTAssertEqual(recorder.events.map(\.button), [3, 4])
        XCTAssertEqual(recorder.events.map(\.down), [true, true])
    }

    // MARK: - ElecomTrackballHandler Tests

    /// Builds a report in the format observed from an ELECOM HUGE TrackBall:
    /// byte 0 is the report ID, byte 1 holds the button states.
    private func elecomReport(buttons: UInt8) -> Data {
        Data([0x01, buttons, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    func testElecomHandlerMatchesHugeTrackball() {
        let handler = ElecomTrackballHandler()

        XCTAssertTrue(handler.matches(vendorID: 0x056E, productID: 0x010C))
    }

    func testElecomHandlerDoesNotMatchOtherDevice() {
        let handler = ElecomTrackballHandler()

        XCTAssertFalse(handler.matches(vendorID: 0x1234, productID: 0x5678))
    }

    func testElecomHandlerAlwaysNeedsReportObservation() {
        let handler = ElecomTrackballHandler()

        XCTAssertTrue(handler.alwaysNeedsReportObservation())
    }

    func testElecomHandlerCallsNext() {
        let handler = ElecomTrackballHandler { _, _ in }
        let context = InputReportContext(report: elecomReport(buttons: 0x00), lastButtonStates: 0x00)

        var nextCalled = false
        handler.handleReport(context) { _ in
            nextCalled = true
        }

        XCTAssertTrue(nextCalled)
    }

    func testElecomHandlerCallsNextEvenWithShortReport() {
        let handler = ElecomTrackballHandler { _, _ in }
        let context = InputReportContext(report: Data([0x01]), lastButtonStates: 0x00)

        var nextCalled = false
        handler.handleReport(context) { _ in
            nextCalled = true
        }

        XCTAssertTrue(nextCalled)
    }

    func testElecomHandlerDetectsFnButtons() {
        // Bit 5, 6 and 7 are the three buttons the report descriptor declares as padding.
        for (mask, button) in [(UInt8(0x20), 5), (UInt8(0x40), 6), (UInt8(0x80), 7)] {
            let recorder = EmissionRecorder()
            let handler = ElecomTrackballHandler(emit: recorder.emit)
            let context = InputReportContext(report: elecomReport(buttons: mask), lastButtonStates: 0x00)

            handler.handleReport(context) { _ in }

            XCTAssertEqual(recorder.events.count, 1)
            XCTAssertEqual(recorder.events.first?.button, button)
            XCTAssertEqual(recorder.events.first?.down, true)
            XCTAssertEqual(context.lastButtonStates, mask)
        }
    }

    func testElecomHandlerEmitsReleaseOnUp() {
        let recorder = EmissionRecorder()
        let handler = ElecomTrackballHandler(emit: recorder.emit)
        let context = InputReportContext(report: elecomReport(buttons: 0x00), lastButtonStates: 0x20)

        handler.handleReport(context) { _ in }

        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertEqual(recorder.events.first?.button, 5)
        XCTAssertEqual(recorder.events.first?.down, false)
        XCTAssertEqual(context.lastButtonStates, 0x00)
    }

    func testElecomHandlerDetectsMultipleFnButtonsAtOnce() {
        let recorder = EmissionRecorder()
        let handler = ElecomTrackballHandler(emit: recorder.emit)
        let context = InputReportContext(report: elecomReport(buttons: 0xA0), lastButtonStates: 0x00)

        handler.handleReport(context) { _ in }

        XCTAssertEqual(recorder.events.count, 2)
        XCTAssertEqual(recorder.events.map(\.button), [5, 7])
        XCTAssertTrue(recorder.events.allSatisfy(\.down))
        XCTAssertEqual(context.lastButtonStates, 0xA0)
    }

    /// Buttons 1 to 5 are declared in the report descriptor and already handled by macOS,
    /// so the handler must not emit duplicate events for them.
    func testElecomHandlerIgnoresDeclaredButtons() {
        let recorder = EmissionRecorder()
        let handler = ElecomTrackballHandler(emit: recorder.emit)
        let context = InputReportContext(report: elecomReport(buttons: 0x1F), lastButtonStates: 0x00)

        handler.handleReport(context) { _ in }

        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertEqual(context.lastButtonStates, 0x00)
    }

    func testElecomHandlerEmitsNothingWhenStateUnchanged() {
        let recorder = EmissionRecorder()
        let handler = ElecomTrackballHandler(emit: recorder.emit)
        let context = InputReportContext(report: elecomReport(buttons: 0x20), lastButtonStates: 0x20)

        handler.handleReport(context) { _ in }

        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertEqual(context.lastButtonStates, 0x20)
    }

    /// Only the mouse input report carries button states; the device also sends consumer and
    /// vendor defined reports that must not be parsed as buttons.
    func testElecomHandlerIgnoresOtherReportIDs() {
        let recorder = EmissionRecorder()
        let handler = ElecomTrackballHandler(emit: recorder.emit)
        let context = InputReportContext(report: Data([0x05, 0xE0, 0x00]), lastButtonStates: 0x00)

        handler.handleReport(context) { _ in }

        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertEqual(context.lastButtonStates, 0x00)
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

    func testRegistryFindsElecomHandler() {
        let handlers = InputReportHandlerRegistry.handlers(for: 0x056E, productID: 0x010C)

        XCTAssertEqual(handlers.count, 1)
        XCTAssertTrue(handlers.first is ElecomTrackballHandler)
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
