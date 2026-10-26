// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

final class ClickThroughTransformerTests: XCTestCase {
    private static let ownPid: pid_t = 1
    private static let frontmostAppPid: pid_t = 100
    private static let inactiveAppPid: pid_t = 200

    private var frontmostPid: pid_t? = frontmostAppPid
    private var window: (ownerPid: pid_t, layer: Int)? = (inactiveAppPid, 0)
    private var now: TimeInterval = 0
    private var scheduled = [() -> Void]()
    private var posted = [CGEvent]()

    override func setUp() {
        super.setUp()
        frontmostPid = Self.frontmostAppPid
        window = (Self.inactiveAppPid, 0)
        now = 0
        scheduled = []
        posted = []
    }

    // MARK: - shouldArm

    func testShouldArmOnlyForNormalWindowsOfOtherInactiveApps() {
        XCTAssertTrue(ClickThroughTransformer.shouldArm(windowOwnerPid: 200, layer: 0, frontmostPid: 100, ownPid: 1))
        XCTAssertFalse(ClickThroughTransformer.shouldArm(windowOwnerPid: 100, layer: 0, frontmostPid: 100, ownPid: 1))
        XCTAssertFalse(ClickThroughTransformer.shouldArm(windowOwnerPid: 200, layer: 20, frontmostPid: 100, ownPid: 1))
        XCTAssertFalse(ClickThroughTransformer.shouldArm(windowOwnerPid: 1, layer: 0, frontmostPid: 100, ownPid: 1))
    }

    // MARK: - Replay

    func testClickOnInactiveAppReplaysOneClickAfterActivation() throws {
        let transformer = makeTransformer()
        let location = CGPoint(x: 10, y: 20)

        XCTAssertNotNil(try transform(transformer, .leftMouseDown, at: location))
        XCTAssertNotNil(try transform(transformer, .leftMouseUp, at: location))
        XCTAssertTrue(posted.isEmpty)

        // Not yet frontmost: keeps waiting.
        runScheduled()
        XCTAssertTrue(posted.isEmpty)

        frontmostPid = Self.inactiveAppPid
        runScheduled()

        XCTAssertEqual(posted.map(\.type), [.leftMouseDown, .leftMouseUp])
        for event in posted {
            XCTAssertEqual(event.location, location)
            XCTAssertTrue(event.isLinearMouseSyntheticEvent)
            XCTAssertEqual(event.getIntegerValueField(.mouseEventClickState), 1)
        }
        XCTAssertTrue(scheduled.isEmpty)
    }

    func testClickOnFrontmostAppDoesNothing() throws {
        window = (Self.frontmostAppPid, 0)
        let transformer = makeTransformer()

        try click(transformer)

        XCTAssertTrue(scheduled.isEmpty)
        XCTAssertTrue(posted.isEmpty)
    }

    func testClickOnOverlayLayerDoesNothing() throws {
        window = (Self.inactiveAppPid, 20)
        let transformer = makeTransformer()

        try click(transformer)

        XCTAssertTrue(scheduled.isEmpty)
    }

    func testDragBeyondThresholdCancelsReplay() throws {
        let transformer = makeTransformer()

        _ = try transform(transformer, .leftMouseDown, at: .zero)
        _ = try transform(transformer, .leftMouseDragged, at: CGPoint(x: 20, y: 0))
        _ = try transform(transformer, .leftMouseUp, at: CGPoint(x: 20, y: 0))

        XCTAssertTrue(scheduled.isEmpty)
    }

    func testSmallJitterStillReplays() throws {
        let transformer = makeTransformer()

        _ = try transform(transformer, .leftMouseDown, at: .zero)
        _ = try transform(transformer, .leftMouseDragged, at: CGPoint(x: 1, y: 1))
        _ = try transform(transformer, .leftMouseUp, at: CGPoint(x: 1, y: 1))
        frontmostPid = Self.inactiveAppPid
        runScheduled()

        XCTAssertEqual(posted.count, 2)
    }

    func testLongPressDoesNotReplay() throws {
        let transformer = makeTransformer()

        _ = try transform(transformer, .leftMouseDown, at: .zero)
        now += 1
        _ = try transform(transformer, .leftMouseUp, at: .zero)

        XCTAssertTrue(scheduled.isEmpty)
    }

    func testAppThatNeverActivatesDoesNotReplay() throws {
        let transformer = makeTransformer()

        try click(transformer)
        for _ in 0 ..< ClickThroughTransformer.activationPollAttempts + 5 {
            runScheduled()
        }

        XCTAssertTrue(scheduled.isEmpty)
        XCTAssertTrue(posted.isEmpty)
    }

    func testSecondMouseDownCancelsPendingReplay() throws {
        let transformer = makeTransformer()

        try click(transformer)
        _ = try transform(transformer, .leftMouseDown, at: .zero)
        frontmostPid = Self.inactiveAppPid
        runScheduled()

        XCTAssertTrue(posted.isEmpty)
    }

    func testDeactivateCancelsPendingReplay() throws {
        let transformer = makeTransformer()

        try click(transformer)
        transformer.deactivate()
        frontmostPid = Self.inactiveAppPid
        runScheduled()

        XCTAssertTrue(posted.isEmpty)
    }

    func testRightButtonIsIgnored() throws {
        let transformer = makeTransformer()

        _ = try transform(transformer, .rightMouseDown, at: .zero, button: .right)
        _ = try transform(transformer, .rightMouseUp, at: .zero, button: .right)

        XCTAssertTrue(scheduled.isEmpty)
    }

    func testSyntheticEventsAreIgnored() throws {
        let transformer = makeTransformer()

        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let event = try mouseEvent(type: type, at: .zero)
            event.isLinearMouseSyntheticEvent = true
            XCTAssertNotNil(transformer.transform(event, in: .init(device: nil)))
        }

        XCTAssertTrue(scheduled.isEmpty)
    }

    // MARK: - Configuration

    func testClickThroughDecodesEncodesAndMerges() throws {
        let buttons = try JSONDecoder().decode(Scheme.Buttons.self, from: Data(#"{"clickThrough":true}"#.utf8))
        XCTAssertTrue(try XCTUnwrap(buttons.clickThrough))

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(buttons)) as? [String: Any]
        )
        XCTAssertEqual(object["clickThrough"] as? Bool, true)

        var merged = Scheme.Buttons(clickThrough: true)
        Scheme.Buttons().merge(into: &merged)
        XCTAssertTrue(try XCTUnwrap(merged.clickThrough))
        Scheme.Buttons(clickThrough: false).merge(into: &merged)
        XCTAssertFalse(try XCTUnwrap(merged.clickThrough))
    }

    // MARK: - Helpers

    private func makeTransformer() -> ClickThroughTransformer {
        ClickThroughTransformer(
            frontmostPid: { [weak self] in self?.frontmostPid },
            windowAtPoint: { [weak self] _ in self?.window },
            ownPid: Self.ownPid,
            now: { [weak self] in self?.now ?? 0 },
            schedule: { [weak self] _, handler in self?.scheduled.append(handler) },
            eventSink: { [weak self] in self?.posted.append($0) }
        )
    }

    private func runScheduled() {
        let handlers = scheduled
        scheduled = []
        handlers.forEach { $0() }
    }

    private func click(_ transformer: ClickThroughTransformer) throws {
        _ = try transform(transformer, .leftMouseDown, at: .zero)
        _ = try transform(transformer, .leftMouseUp, at: .zero)
    }

    private func transform(
        _ transformer: ClickThroughTransformer,
        _ type: CGEventType,
        at location: CGPoint,
        button: CGMouseButton = .left
    ) throws -> CGEvent? {
        try transformer.transform(mouseEvent(type: type, at: location, button: button), in: .init(device: nil))
    }

    private func mouseEvent(type: CGEventType, at location: CGPoint, button: CGMouseButton = .left) throws -> CGEvent {
        try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        ))
    }
}
