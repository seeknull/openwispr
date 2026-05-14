import Foundation
import SwiftUI
import OpenWisprCore

/// User-tunable preferences, persisted via @AppStorage.
///
/// We use plain `@AppStorage` strings/bools so the persisted format stays
/// readable in `defaults read dev.openwispr.app` — useful for support.
@MainActor
final class OpenWisprSettings: ObservableObject {
    static let shared = OpenWisprSettings()

    @AppStorage("insertionMode")      var insertionModeRaw: String = InsertionMode.clipboardPaste.rawValue
    @AppStorage("showHUD")            var showHUD: Bool = true
    @AppStorage("hotkeyModifiersCSV") var hotkeyModifiersCSV: String = "fn,option"

    var insertionMode: InsertionMode {
        get { InsertionMode(rawValue: insertionModeRaw) ?? .clipboardPaste }
        set { insertionModeRaw = newValue.rawValue }
    }

    var hotkeyConfig: HotkeyConfig {
        get {
            let mods = hotkeyModifiersCSV.split(separator: ",")
                .compactMap { HotkeyConfig.Modifier(rawValue: String($0)) }
            return HotkeyConfig(modifiers: Set(mods))
        }
        set {
            hotkeyModifiersCSV = newValue.modifiers
                .map(\.rawValue)
                .sorted()
                .joined(separator: ",")
        }
    }
}
