import XCTest
@testable import WhispCore

final class DictationControllerTests: XCTestCase {
    func testInitialState_isIdle() {
        let c = DictationController()
        XCTAssertEqual(c.state, .idle)
    }

    func testToggle_idleToStarting() {
        let c = DictationController()
        c.toggle()
        XCTAssertEqual(c.state, .starting)
    }

    func testEngineDidStart_startingToListening() {
        let c = DictationController()
        c.toggle()
        c.engineDidStart()
        XCTAssertEqual(c.state, .listening)
        XCTAssertTrue(c.state.isListening)
    }

    func testToggle_listeningToStopping() {
        let c = DictationController()
        c.toggle()
        c.engineDidStart()
        c.toggle()
        XCTAssertEqual(c.state, .stopping)
    }

    func testEngineDidStop_stoppingToIdle() {
        let c = DictationController()
        c.toggle()
        c.engineDidStart()
        c.toggle()
        c.engineDidStop()
        XCTAssertEqual(c.state, .idle)
    }

    func testToggleWhileStarting_isNoop() {
        let c = DictationController()
        c.toggle()  // → starting
        c.toggle()  // ignored
        XCTAssertEqual(c.state, .starting)
    }

    func testEngineFailed_goesToError() {
        let c = DictationController()
        c.toggle()
        c.engineFailed("model load failed")
        XCTAssertEqual(c.state, .error("model load failed"))
        XCTAssertFalse(c.state.isListening)
    }

    func testDismissError_returnsToIdle() {
        let c = DictationController()
        c.engineFailed("nope")
        c.dismissError()
        XCTAssertEqual(c.state, .idle)
    }

    func testObserver_receivesInitialAndSubsequentStates() {
        let c = DictationController()
        var received: [DictationState] = []
        c.addObserver { received.append($0) }
        XCTAssertEqual(received, [.idle])

        c.toggle()
        c.engineDidStart()
        XCTAssertEqual(received, [.idle, .starting, .listening])
    }

    func testObserver_removalStopsCallbacks() {
        let c = DictationController()
        var received: [DictationState] = []
        let token = c.addObserver { received.append($0) }
        c.removeObserver(token)
        c.toggle()
        XCTAssertEqual(received, [.idle], "Removed observer must not fire")
    }

    func testSameStateTransition_doesNotEmit() {
        let c = DictationController()
        var count = 0
        c.addObserver { _ in count += 1 }
        XCTAssertEqual(count, 1, "initial state delivered once")
        c.engineDidStop() // already idle, should be no-op
        XCTAssertEqual(count, 1)
    }
}
