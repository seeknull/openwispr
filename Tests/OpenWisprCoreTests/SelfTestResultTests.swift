import XCTest
@testable import OpenWisprCore

// SelfTestResult is defined in the app target, not OpenWisprCore — we
// re-declare a compatible structure here for testing the aggregation
// logic, since the .ok / .warning / .failure precedence is the only
// non-trivial bit.
//
// (When we extract SelfTest into OpenWisprCore for full testability, this
// shadow file goes away.)

private struct AggregateTest {
    enum Status: Equatable {
        case ok
        case warning(String)
        case failure(String)
    }

    /// Mirrors SelfTestResult.overall: failure beats warning beats ok.
    static func aggregate(_ statuses: [Status]) -> Status {
        if let failure = statuses.first(where: { if case .failure = $0 { return true }; return false }) {
            return failure
        }
        if let warning = statuses.first(where: { if case .warning = $0 { return true }; return false }) {
            return warning
        }
        return .ok
    }
}

final class SelfTestResultTests: XCTestCase {
    func testAllOk_aggregatesToOk() {
        let result = AggregateTest.aggregate([.ok, .ok, .ok])
        XCTAssertEqual(result, .ok)
    }

    func testAnyWarning_aggregatesToWarning() {
        let result = AggregateTest.aggregate([.ok, .warning("low"), .ok])
        XCTAssertEqual(result, .warning("low"))
    }

    func testAnyFailure_beatsWarning() {
        let result = AggregateTest.aggregate([.warning("low"), .failure("dead"), .ok])
        XCTAssertEqual(result, .failure("dead"))
    }

    func testFailure_beatsMultipleWarnings() {
        let result = AggregateTest.aggregate([.warning("a"), .warning("b"), .failure("worst")])
        XCTAssertEqual(result, .failure("worst"))
    }

    func testEmpty_isOk() {
        XCTAssertEqual(AggregateTest.aggregate([]), .ok)
    }

    func testFirstFailureWins_amongMultipleFailures() {
        let result = AggregateTest.aggregate([.failure("first"), .failure("second")])
        XCTAssertEqual(result, .failure("first"))
    }
}
