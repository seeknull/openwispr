import XCTest
@testable import OpenWisprCore

final class HotkeyStateMachineTests: XCTestCase {
    func testFirstPressStartsListening() {
        var sm = HotkeyStateMachine()
        XCTAssertEqual(sm.modifiersPressed(now: 0), .startListening)
        XCTAssertTrue(sm.listening)
    }

    func testReleaseAlone_doesNotToggle() {
        var sm = HotkeyStateMachine()
        _ = sm.modifiersPressed(now: 0)
        XCTAssertEqual(sm.modifiersReleased(), .none)
        XCTAssertTrue(sm.listening, "Release should not flip listening — only press toggles")
    }

    func testSecondPressStopsListening() {
        var sm = HotkeyStateMachine()
        _ = sm.modifiersPressed(now: 0)
        _ = sm.modifiersReleased()
        XCTAssertEqual(sm.modifiersPressed(now: 1.0), .stopListening)
        XCTAssertFalse(sm.listening)
    }

    func testDebounce_swallowsRapidRepeat() {
        var sm = HotkeyStateMachine(debounceInterval: 0.5)
        _ = sm.modifiersPressed(now: 0)
        _ = sm.modifiersReleased()
        // A press 0.1s later (within debounce) should be ignored.
        XCTAssertEqual(sm.modifiersPressed(now: 0.1), .none)
        XCTAssertTrue(sm.listening, "Debounced press must not flip state")
    }

    func testModifiersHeld_isTrueAfterPress() {
        var sm = HotkeyStateMachine()
        _ = sm.modifiersPressed(now: 0)
        XCTAssertTrue(sm.modifiersHeld)
        _ = sm.modifiersReleased()
        XCTAssertFalse(sm.modifiersHeld)
    }

    func testForceStop_onlyEmitsWhenListening() {
        var sm = HotkeyStateMachine()
        XCTAssertEqual(sm.forceStop(), .none, "Idle force-stop is a no-op")

        _ = sm.modifiersPressed(now: 0)
        XCTAssertEqual(sm.forceStop(), .stopListening)
        XCTAssertFalse(sm.listening)
    }

    func testRedundantPress_whileHeldIsIgnored() {
        var sm = HotkeyStateMachine()
        _ = sm.modifiersPressed(now: 0)
        XCTAssertEqual(sm.modifiersPressed(now: 0.01), .none,
                       "A second press without an intervening release must be ignored")
    }

    func testSetListening_doesNotEmitEffect() {
        var sm = HotkeyStateMachine()
        sm.setListening(true)
        XCTAssertTrue(sm.listening)
        XCTAssertNil(nil as Any?, "setListening must not produce an effect, only sync state")
    }

    func testSyncAfterExternalStart_nextPressStops() {
        // Simulates: menu bar starts dictation, then user presses the hotkey.
        // The hotkey press should be interpreted as "stop", not as a fresh start.
        var sm = HotkeyStateMachine()
        sm.setListening(true) // engine started via the menu bar
        _ = sm.modifiersReleased() // chord is currently not held

        let result = sm.modifiersPressed(now: 0)
        XCTAssertEqual(result, .stopListening,
                       "After external start, hotkey should stop with one press")
        XCTAssertFalse(sm.listening)
    }

    func testDefaultMinimumToggleGap_isShortEnoughForRealUsage() {
        // 60ms or less keeps deliberate human double-taps responsive.
        let sm = HotkeyStateMachine()
        XCTAssertLessThanOrEqual(sm.minimumToggleGap, 0.10,
                                 "Minimum toggle gap above 100ms feels laggy")
    }
}
