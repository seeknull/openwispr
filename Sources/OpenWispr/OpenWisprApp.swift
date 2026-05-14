import AppKit
import MoonshineVoice
import OSLog
import SwiftUI
import OpenWisprCore

@main
struct OpenWisprApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // OpenWispr is a menu-bar-only app, but SwiftUI's @main requires at
        // least one Scene. The Settings window is built manually in
        // MenuBarController so we have full control over its lifecycle.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private let log = Logger(subsystem: "dev.openwispr.app", category: "AppDelegate")

    let permissions = PermissionsManager()
    let settings = OpenWisprSettings.shared
    let dictation = DictationController()
    private var injector: TextInjector!
    private var engine: DictationEngine!
    private var hotkey: HotkeyMonitor!
    private var menuBar: MenuBarController!
    private var selfTest: SelfTest!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        injector = TextInjector(mode: settings.insertionMode)

        let (modelPath, modelArch) = locateBundledModel()
        log.info("Model path: \(modelPath, privacy: .public) (arch: \(modelArch.rawValue))")

        engine = DictationEngine(modelPath: modelPath, modelArch: modelArch, injector: injector)
        hotkey = HotkeyMonitor(config: settings.hotkeyConfig) { [weak self] effect in
            guard let self else { return }
            switch effect {
            case .startListening:
                self.dictation.toggle()
                self.engine.start()
            case .stopListening:
                self.dictation.toggle()
                self.engine.stop()
            case .none:
                break
            }
        }

        selfTest = SelfTest(
            permissions: permissions,
            modelPath: modelPath,
            hotkeyIsRunning: { [weak self] in self?.hotkey.isRunning ?? false }
        )

        menuBar = MenuBarController(
            dictation: dictation,
            engine: engine,
            hotkey: hotkey,
            permissions: permissions,
            settings: settings,
            selfTest: selfTest
        )

        if !hotkey.start() {
            log.warning("Could not start NSEvent monitor — Accessibility may be missing")
        }

        // Run the self-test once on launch so the menu bar icon reflects
        // health from the first frame.
        permissions.refresh()
        menuBar.runSelfTestAndRefreshIcon()

        // Open Settings if anything is missing — landing in the
        // Permissions tab is the most useful starting place.
        if !permissions.allGranted {
            DispatchQueue.main.async { [weak self] in
                self?.menuBar.openSettings()
            }
        }
    }

    private func locateBundledModel() -> (String, ModelArch) {
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("models/medium-streaming-en/quantized"),
            FileManager.default.fileExists(atPath: bundled.path)
        {
            return (bundled.path, .mediumStreaming)
        }
        if let frameworkBundle = Transcriber.frameworkBundle,
           let resourcePath = frameworkBundle.resourcePath
        {
            let fallback = (resourcePath as NSString)
                .appendingPathComponent("test-assets/tiny-en")
            log.warning("Bundled model not found; falling back to tiny-en at \(fallback, privacy: .public)")
            return (fallback, .tiny)
        }
        fatalError("No usable Moonshine model bundled with OpenWispr.app")
    }
}

extension AppDelegate {
    /// Identifier MenuBarController stamps on its Settings NSWindow.
    static let settingsWindowID: String = "OpenWisprSettings"
}
