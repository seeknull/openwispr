import Foundation
import SwiftUI
import WhispCore

/// User-tunable preferences, persisted via @AppStorage.
///
/// We use plain `@AppStorage` strings/bools so the persisted format stays
/// readable in `defaults read ai.whisp.dev` — useful for support.
@MainActor
final class WhispSettings: ObservableObject {
    static let shared = WhispSettings()

    @AppStorage("insertionMode") var insertionModeRaw: String = InsertionMode.clipboardPaste.rawValue
    @AppStorage("launchAtLogin")  var launchAtLogin: Bool = false
    @AppStorage("showHUD")        var showHUD: Bool = true
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
