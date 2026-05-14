import XCTest
@testable import OpenWisprCore

final class HotkeyConfigTests: XCTestCase {
    func testDefaultIsFnPlusOption() {
        XCTAssertEqual(HotkeyConfig.default.modifiers, [.fn, .option])
    }

    func testDisplayName_stableOrdering() {
        let cfg = HotkeyConfig(modifiers: [.fn, .shift, .control, .option])
        XCTAssertEqual(cfg.displayName, "⌃ Control + ⌥ Option + ⇧ Shift + Fn")
    }

    func testCodableRoundTrip() throws {
        let cfg = HotkeyConfig(modifiers: [.fn, .option, .command])
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(HotkeyConfig.self, from: data)
        XCTAssertEqual(cfg, decoded)
    }
}
