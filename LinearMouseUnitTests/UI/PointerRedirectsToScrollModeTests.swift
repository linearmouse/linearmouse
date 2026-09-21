// MIT License
// Copyright (c) 2021-2026 LinearMouse

@testable import LinearMouse
import XCTest

/// The picker offers three modes, but the configuration still stores two
/// fields. These cover the reading between them, including the combination
/// that used to be reachable by clearing a trigger and silently meant
/// "convert everything".
final class PointerRedirectsToScrollModeTests: XCTestCase {
    private let trigger = Scheme.Trigger(input: .button(.mouse(3)))

    func testRedirectingOffIsOffWhateverTheTriggerIs() {
        XCTAssertEqual(
            PointerSettingsState.redirectsToScrollMode(redirectsToScroll: false, trigger: nil),
            .off
        )
        XCTAssertEqual(
            PointerSettingsState.redirectsToScrollMode(redirectsToScroll: false, trigger: trigger),
            .off
        )
    }

    func testRedirectingOnWithATriggerIsHoldToConvert() {
        XCTAssertEqual(
            PointerSettingsState.redirectsToScrollMode(redirectsToScroll: true, trigger: trigger),
            .whileHoldingTrigger
        )
    }

    func testRedirectingOnWithoutATriggerIsAlways() {
        XCTAssertEqual(
            PointerSettingsState.redirectsToScrollMode(redirectsToScroll: true, trigger: nil),
            .always
        )
    }

    /// The configurations written before the picker existed are `redirectsToScroll`
    /// on its own, and they have to keep meaning what they meant.
    func testConfigurationsWrittenBeforeTheTriggerExistedStillReadAsAlways() throws {
        let json = """
        { "pointer": { "redirectsToScroll": true } }
        """

        let scheme = try JSONDecoder().decode(Scheme.self, from: Data(json.utf8))

        XCTAssertEqual(
            PointerSettingsState.redirectsToScrollMode(
                redirectsToScroll: scheme.pointer.redirectsToScroll ?? false,
                trigger: scheme.pointer.redirectsToScrollTrigger
            ),
            .always
        )
    }

    func testEveryModeIsReachableFromSomeStoredConfiguration() {
        let stored: [(Bool, Scheme.Trigger?)] = [(false, nil), (true, trigger), (true, nil)]
        let reachable = Set(
            stored.map { PointerSettingsState.redirectsToScrollMode(redirectsToScroll: $0.0, trigger: $0.1) }
        )

        XCTAssertEqual(reachable, Set(PointerSettingsState.RedirectsToScrollMode.allCases))
    }

    func testTheRevertCountdownIsLongEnoughToReactTo() {
        XCTAssertGreaterThanOrEqual(PointerSettingsState.redirectsToScrollAlwaysRevertSeconds, 5)
    }
}
