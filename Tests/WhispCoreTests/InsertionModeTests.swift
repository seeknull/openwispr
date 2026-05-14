import XCTest
@testable import WhispCore

final class InsertionModeTests: XCTestCase {
    func testRawValuesAreStable() {
        // These strings get persisted via @AppStorage — changing them
        // would migrate existing users back to the default.
        XCTAssertEqual(InsertionMode.clipboardPaste.rawValue, "clipboardPaste")
        XCTAssertEqual(InsertionMode.keystroke.rawValue, "keystroke")
    }

    func testAllCasesHaveDisplayAndHelpText() {
        for mode in InsertionMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty)
            XCTAssertFalse(mode.helpText.isEmpty)
        }
    }
}
