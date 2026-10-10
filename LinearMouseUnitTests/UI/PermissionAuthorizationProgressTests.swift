// MIT License
// Copyright (c) 2021-2026 LinearMouse

import IOKit.hidsystem
@testable import LinearMouse
import XCTest

final class PermissionAuthorizationProgressTests: XCTestCase {
    private func snapshot(ax: Bool, hid: IOHIDAccessType = kIOHIDAccessTypeDenied) -> AccessibilityPermission.Snapshot {
        .init(accessibility: ax, postEvent: false, hidPostEvent: hid)
    }

    func testNewAXGrantRestartsOnceEvenWhileEventAccessStillReportsDenied() {
        var progress = AccessibilityPermission.AuthorizationProgress(accessibilityInitiallyTrusted: false)
        XCTAssertFalse(progress.shouldRestart(after: snapshot(ax: false), isDragging: false))
        XCTAssertTrue(progress.shouldRestart(after: snapshot(ax: true), isDragging: false))
        XCTAssertFalse(progress.shouldRestart(after: snapshot(ax: true), isDragging: false))
        // The onboarding exception must not weaken runtime permission validation.
        XCTAssertFalse(snapshot(ax: true).enabled)
    }

    func testWaitsForDragToEndWithoutLosingGrantTransition() {
        var progress = AccessibilityPermission.AuthorizationProgress(accessibilityInitiallyTrusted: false)
        XCTAssertFalse(progress.shouldRestart(after: snapshot(ax: true), isDragging: true))
        XCTAssertTrue(progress.shouldRestart(after: snapshot(ax: true), isDragging: false))
    }

    func testExistingAXGrantDoesNotCauseRestartLoopWithDeniedEventAccess() {
        var progress = AccessibilityPermission.AuthorizationProgress(accessibilityInitiallyTrusted: true)
        for _ in 0 ..< 5 {
            XCTAssertFalse(progress.shouldRestart(after: snapshot(ax: true), isDragging: false))
        }
        XCTAssertTrue(progress.shouldRestart(
            after: snapshot(ax: true, hid: kIOHIDAccessTypeGranted),
            isDragging: false
        ))
    }

    func testReauthorizationAfterObservedRevocationCanContinue() {
        var progress = AccessibilityPermission.AuthorizationProgress(accessibilityInitiallyTrusted: true)
        XCTAssertFalse(progress.shouldRestart(after: snapshot(ax: false), isDragging: false))
        XCTAssertTrue(progress.shouldRestart(after: snapshot(ax: true), isDragging: false))
    }
}
