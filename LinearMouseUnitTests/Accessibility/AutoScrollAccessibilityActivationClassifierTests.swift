// MIT License
// Copyright (c) 2021-2026 LinearMouse

import ApplicationServices
@testable import LinearMouse
import XCTest

final class AutoScrollAccessibilityActivationClassifierTests: XCTestCase {
    func testPressableHitPreservesNativeEventWithoutRetry() {
        let hit = AutoScrollActivationHit.pressable(path: ["AXButton[press]"])

        XCTAssertTrue(hit.isPressable)
        XCTAssertFalse(hit.requiresRetry)
        XCTAssertEqual(hit.summary, "pressable")
    }

    func testAccessibilityFailureIsNonPressableWithDiagnostic() {
        let hit = AutoScrollActivationHit.nonPressable(
            diagnostic: "role.cannotComplete",
            path: ["AXGroup"]
        )

        XCTAssertFalse(hit.isPressable)
        XCTAssertTrue(hit.requiresRetry)
        XCTAssertEqual(hit.summary, "nonPressable.role.cannotComplete")
    }

    func testAutoScrollStartsOnlyForNonPressableOrUnavailableHit() {
        XCTAssertFalse(AutoScrollTransformer.shouldStartAutoScroll(for: .pressable(path: [])))
        XCTAssertTrue(AutoScrollTransformer.shouldStartAutoScroll(for: .nonPressable(
            diagnostic: nil,
            path: []
        )))
        XCTAssertTrue(AutoScrollTransformer.shouldStartAutoScroll(for: nil))
    }

    func testPressableActivationElementAcceptsExplicitControls() {
        XCTAssertTrue(AutoScrollAccessibilityActivationClassifier.isPressableActivationElement(
            role: "AXLink",
            actions: []
        ))
        XCTAssertTrue(AutoScrollAccessibilityActivationClassifier.isPressableActivationElement(
            role: "AXButton",
            actions: [kAXPressAction as String]
        ))
        XCTAssertTrue(AutoScrollAccessibilityActivationClassifier.isPressableActivationElement(
            role: "AXCheckBox",
            actions: [kAXPressAction as String]
        ))
        XCTAssertTrue(AutoScrollAccessibilityActivationClassifier.isPressableActivationElement(
            role: "AXComboBox",
            actions: [kAXPressAction as String]
        ))
    }

    func testPressableActivationElementRejectsGenericGroupEvenWithPressAction() {
        XCTAssertFalse(AutoScrollAccessibilityActivationClassifier.isPressableActivationElement(
            role: "AXGroup",
            actions: [kAXPressAction as String]
        ))
    }

    func testPressableActivationElementRejectsControlWithoutPressActionWhenNeeded() {
        XCTAssertFalse(AutoScrollAccessibilityActivationClassifier.isPressableActivationElement(
            role: "AXButton",
            actions: []
        ))
        XCTAssertFalse(AutoScrollAccessibilityActivationClassifier.isPressableActivationElement(
            role: nil,
            actions: [kAXPressAction as String]
        ))
    }

    func testNativeNonPressableHitDoesNotRetry() {
        let elementQuery = AccessibilityElementQuerySpy(role: "AXStaticText")
        let classifier = AutoScrollAccessibilityActivationClassifier(elementQuery: elementQuery)

        let classification = classifier.classify(at: CGPoint(x: 100, y: 100))

        XCTAssertFalse(classification.resolved.hit.isPressable)
        XCTAssertEqual(elementQuery.hitTestCount, 1)
        XCTAssertEqual(elementQuery.actionNamesCount, 0)
    }

    func testNativeScrollAreaDoesNotTriggerBrowserRetry() {
        let elementQuery = AccessibilityElementQuerySpy(role: "AXScrollArea")
        let classifier = AutoScrollAccessibilityActivationClassifier(elementQuery: elementQuery)

        let classification = classifier.classify(at: CGPoint(x: 100, y: 100))

        XCTAssertFalse(classification.resolved.hit.isPressable)
        XCTAssertEqual(elementQuery.hitTestCount, 1)
    }

    func testWebContentNonPressableHitRetriesOriginalPointOnce() {
        let elementQuery = AccessibilityElementQuerySpy(role: "AXWebArea")
        var retryDelayCount = 0
        let classifier = AutoScrollAccessibilityActivationClassifier(
            elementQuery: elementQuery
        ) {
            retryDelayCount += 1
        }
        let point = CGPoint(x: 100, y: 100)

        let classification = classifier.classify(at: point)

        XCTAssertFalse(classification.resolved.hit.isPressable)
        XCTAssertEqual(elementQuery.hitTestCount, 2)
        XCTAssertEqual(elementQuery.hitTestPoints, [point, point])
        XCTAssertEqual(retryDelayCount, 1)
        XCTAssertEqual(elementQuery.actionNamesCount, 0)
    }

    func testWebContentRetryCanResolvePressableAtOriginalPoint() {
        let elementQuery = AccessibilityElementQuerySpy(rolesByHit: ["AXWebArea", "AXLink"])
        let point = CGPoint(x: 100, y: 100)
        let classifier = AutoScrollAccessibilityActivationClassifier(
            elementQuery: elementQuery
        ) {}

        let classification = classifier.classify(at: point)

        XCTAssertFalse(classification.initial.hit.isPressable)
        XCTAssertTrue(classification.resolved.hit.isPressable)
        XCTAssertEqual(classification.resolved.point, point)
        XCTAssertEqual(elementQuery.hitTestPoints, [point, point])
    }

    func testTransientHitTestFailureRetriesOriginalPoint() {
        let elementQuery = AccessibilityElementQuerySpy(
            role: "AXLink",
            initialHitTestFailure: .notImplemented
        )
        let point = CGPoint(x: 100, y: 100)
        let classifier = AutoScrollAccessibilityActivationClassifier(
            elementQuery: elementQuery
        ) {}

        let classification = classifier.classify(at: point)

        XCTAssertEqual(classification.initial.hit.summary, "nonPressable.hitTest.notImplemented")
        XCTAssertTrue(classification.resolved.hit.isPressable)
        XCTAssertEqual(elementQuery.hitTestPoints, [point, point])
    }

    func testCannotCompleteHitTestFailureRetriesOriginalPoint() {
        let elementQuery = AccessibilityElementQuerySpy(
            role: "AXLink",
            initialHitTestFailure: .cannotComplete
        )
        let point = CGPoint(x: 100, y: 100)
        let classifier = AutoScrollAccessibilityActivationClassifier(
            elementQuery: elementQuery
        ) {}

        let classification = classifier.classify(at: point)

        XCTAssertEqual(classification.initial.hit.summary, "nonPressable.hitTest.cannotComplete")
        XCTAssertTrue(classification.resolved.hit.isPressable)
        XCTAssertEqual(elementQuery.hitTestPoints, [point, point])
    }

    func testPermanentHitTestFailureDoesNotRetry() {
        let elementQuery = AccessibilityElementQuerySpy(
            role: "AXLink",
            initialHitTestFailure: .invalidUIElement
        )
        var retryDelayCount = 0
        let point = CGPoint(x: 100, y: 100)
        let classifier = AutoScrollAccessibilityActivationClassifier(
            elementQuery: elementQuery
        ) {
            retryDelayCount += 1
        }

        let classification = classifier.classify(at: point)

        XCTAssertEqual(classification.resolved.hit.summary, "nonPressable.hitTest.invalidUIElement")
        XCTAssertEqual(elementQuery.hitTestPoints, [point])
        XCTAssertEqual(retryDelayCount, 0)
    }
}

private final class AccessibilityElementQuerySpy: AccessibilityElementQuerying {
    private let element = AXUIElementCreateSystemWide()
    private let rolesByHit: [String]
    private let initialHitTestFailure: AXError?

    private(set) var hitTestCount = 0
    private(set) var hitTestPoints: [CGPoint] = []
    private(set) var actionNamesCount = 0

    init(role: String, initialHitTestFailure: AXError? = nil) {
        rolesByHit = [role]
        self.initialHitTestFailure = initialHitTestFailure
    }

    init(rolesByHit: [String]) {
        self.rolesByHit = rolesByHit
        initialHitTestFailure = nil
    }

    func systemWideElement(at point: CGPoint) -> AccessibilityQueryResult<AXUIElement?> {
        hitTestCount += 1
        hitTestPoints.append(point)
        if hitTestCount == 1, let initialHitTestFailure {
            return .failure(initialHitTestFailure)
        }
        return .success(element)
    }

    func element(at _: CGPoint, in _: AXUIElement) -> AccessibilityQueryResult<AXUIElement?> {
        XCTFail("Unexpected rooted hit test")
        return .success(nil)
    }

    func requiredStringValue(of attribute: CFString, on _: AXUIElement) -> AccessibilityQueryResult<String?> {
        XCTAssertEqual(attribute, kAXRoleAttribute as CFString)
        let roleIndex = min(max(hitTestCount - 1, 0), rolesByHit.count - 1)
        return .success(rolesByHit[roleIndex])
    }

    func optionalStringValue(of _: CFString, on _: AXUIElement) -> AccessibilityQueryResult<String?> {
        .success(nil)
    }

    func optionalElementValue(of _: CFString, on _: AXUIElement) -> AccessibilityQueryResult<AXUIElement?> {
        .success(nil)
    }

    // swiftlint:disable discouraged_optional_collection
    func optionalElementArrayValue(
        of _: CFString,
        on _: AXUIElement
    ) -> AccessibilityQueryResult<[AXUIElement]?> {
        .success(nil)
    }

    // swiftlint:enable discouraged_optional_collection

    func optionalAttributeValue(of _: CFString, on _: AXUIElement) -> AccessibilityQueryResult<CFTypeRef?> {
        .success(nil)
    }

    func optionalPointValue(of _: CFString, on _: AXUIElement) -> AccessibilityQueryResult<CGPoint?> {
        .success(nil)
    }

    func optionalSizeValue(of _: CFString, on _: AXUIElement) -> AccessibilityQueryResult<CGSize?> {
        .success(nil)
    }

    func optionalFrameValue(of _: AXUIElement) -> AccessibilityQueryResult<CGRect?> {
        .success(nil)
    }

    func optionalActionNames(of _: AXUIElement) -> AccessibilityQueryResult<[String]> {
        actionNamesCount += 1
        return .success([])
    }
}
