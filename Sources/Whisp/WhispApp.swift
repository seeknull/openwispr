import AppKit
import MoonshineVoice
import OSLog
import SwiftUI
import WhispCore

/// Identifies the SwiftUI-managed Settings window so the AppDelegate can
/// programmatically open it via the `openWindow` environment action.
private let settingsWindowID = "WhispSettingsWindow"

@main
struct WhispApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Whisp is a menu-bar-only app, but SwiftUI's @main requires at
        // least one Scene. The window itself is built manually in
        // MenuBarController so we have full control over its lifecycle —
        // crucial under macOS 26 where SwiftUI's Settings scene doesn't
        // surface reliably under `.accessory` activation policy.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private let log = Logger(subsystem: "ai.whisp.app", category: "AppDelegate")

    let permissions = PermissionsManager()
    let settings = WhispSettings.shared
    private var injector: TextInjector!
    private var engine: DictationEngine!
    private var hotkey: HotkeyMonitor!
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar only, no Dock icon

        injector = TextInjector(mode: settings.insertionMode)

        let (modelPath, modelArch) = locateBundledModel()
        log.info("Model path: \(modelPath, privacy: .public) (arch: \(modelArch.rawValue))")

        engine = DictationEngine(modelPath: modelPath, modelArch: modelArch, injector: injector)
        hotkey = HotkeyMonitor(config: settings.hotkeyConfig) { [weak self] effect in
            guard let self else { return }
            switch effect {
            case .startListening: self.engine.start()
            case .stopListening:  self.engine.stop()
            case .none: break
            }
        }
        menuBar = MenuBarController(
            engine: engine,
            hotkey: hotkey,
            permissions: permissions,
            settings: settings
        )

        if !hotkey.start() {
            log.warning("Could not start event tap — Input Monitoring permission may be missing")
        }

        // Always call IOHIDRequestAccess so Whisp appears in the System
        // Settings → Input Monitoring list. CGEvent.tapCreate alone does
        // NOT add the app to that list — without this call, the user
        // has no row to toggle.
        permissions.ensureInputMonitoringIsRegistered()

        // First-launch onboarding: open the Settings window's Permissions
        // tab if anything is missing. If a signature drift was detected,
        // pre-clear stale TCC entries with tccutil so the user opens System
        // Settings into a clean state.
        permissions.refresh()
        // Always surface Settings on launch when permissions are missing OR
        // when the build signature drifted (since a stale grant for a
        // different CDHash can return `allGranted == true` even though TCC
        // will reject the actual API calls). Letting the user see the
        // current state on launch is friendlier than a silent menu-bar app
        // that doesn't respond to the hotkey.
        if !permissions.allGranted || permissions.signatureChangedSinceLastGrant {
            if permissions.signatureChangedSinceLastGrant {
                log.info("Signature drift detected — auto-resetting TCC entries")
                permissions.runAutoFixup()
            }
            // Defer the window open by one tick. Showing a window from
            // inside applicationDidFinishLaunching sometimes races with
            // SwiftUI's own scene setup and the window doesn't actually
            // surface — by the time the run loop spins once, the app is
            // fully ready and `openSettings` reliably brings it up.
            DispatchQueue.main.async { [weak self] in
                self?.menuBar.openSettings()
            }
        }
    }

    /// Resolve the bundled model directory.
    ///
    /// The build script bundles `medium-streaming-en/quantized` into the app's
    /// resources. For developer builds where the bundle hasn't been populated
    /// yet, we fall back to `MoonshineVoice`'s test-assets/tiny-en (shipped
    /// inside `Moonshine.xcframework`) so the app launches at all.
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
        fatalError("No usable Moonshine model bundled with Whisp.app")
    }
}

extension AppDelegate {
    /// Identifier MenuBarController stamps on its Settings NSWindow.
    static let settingsWindowID: String = "WhispSettings"
}
