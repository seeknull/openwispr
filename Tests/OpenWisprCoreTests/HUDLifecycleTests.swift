import XCTest
@testable import OpenWisprCore

/// Doesn't test the AppKit HUD directly (that needs an NSApplication),
/// but ensures the DictationController emits the right state sequence
/// for the HUD to react to. The HUD bug we hit was triggered by
/// .listening → .stopping → .idle in rapid succession; this confirms
/// the sequence is delivered correctly.
final class HUDLifecycleTests: XCTestCase {
    func testToggleCycle_emitsExpectedStateSequence() {
        let c = DictationController()
        var states: [DictationState] = []
        c.addObserver { states.append($0) }

        c.toggle()              // → .starting
        c.engineDidStart()      // → .listening (HUD show)
        c.toggle()              // → .stopping (HUD hide)
        c.engineDidStop()       // → .idle

        XCTAssertEqual(states, [.idle, .starting, .listening, .stopping, .idle])
    }

    func testRapidToggle_doesNotProduceSpuriousStates() {
        let c = DictationController()
        var states: [DictationState] = []
        c.addObserver { states.append($0) }

        // 5 full toggle cycles back-to-back. HUD show/hide cycles
        // should each happen exactly once per round trip.
        for _ in 0..<5 {
            c.toggle()
            c.engineDidStart()
            c.toggle()
            c.engineDidStop()
        }

        // 1 initial idle + 5 * (.starting, .listening, .stopping, .idle)
        XCTAssertEqual(states.count, 1 + 5 * 4)
        // Last state must be idle.
        XCTAssertEqual(states.last, .idle)
        // Listening must appear exactly 5 times.
        let listeningCount = states.filter { $0 == .listening }.count
        XCTAssertEqual(listeningCount, 5)
    }
}
