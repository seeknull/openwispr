#if canImport(XCTest)
import XCTest

/// Skeleton XCUITest. SwiftPM does not actually run XCUITests (only Xcode
/// projects do); these are kept here so when contributors generate an
/// Xcode project (see scripts/generate-xcodeproj.sh), the UI test target
/// has a starting point.
///
/// To run locally:
///   1. `scripts/generate-xcodeproj.sh`
///   2. Open Whisp.xcodeproj and switch to the "Whisp UI Tests" scheme.
///   3. ⌘U.
final class SettingsWindowUITests: XCTestCase {
    func testSettingsWindowAppearsOnMenuItem() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-WhispUITestMode", "YES"]
        app.launch()

        // The menu bar item lives in the system status bar; we can locate
        // the settings window by its accessibility identifier.
        let settingsWindow = app.windows["WhispSettingsWindow"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
    }
}
#endif
