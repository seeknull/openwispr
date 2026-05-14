import AppKit
import MoonshineVoice
import OSLog
import SwiftUI
import WhispCore

@main
struct WhispApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Whisp is a menu-bar-only app, but SwiftUI's @main requires a
        // Scene declaration. We supply a Settings scene that we never
        // actually surface (NSApp activation policy is `.accessory`),
        // so this remains a no-op in practice.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "ai.whisp.app", category: "AppDelegate")

    private let permissions = PermissionsManager()
    private let settings = WhispSettings.shared
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

        // First-launch onboarding: if any AX/IM permission is missing,
        // open the FixupSheet. It's the right surface whether this is a
        // genuine first run or a rebuild that broke previous grants —
        // both cases need the same "open System Settings, toggle on" flow.
        //
        // We only auto-run tccutil reset when we know the signature drifted
        // (so genuine first-launch users don't see a reset they didn't ask
        // for). When triggered manually via the menu bar "Reset Permissions…"
        // item, we always reset.
        permissions.refresh()
        if !permissions.allGranted {
            let autoReset = permissions.signatureChangedSinceLastGrant
            log.info("Permissions incomplete on launch; opening fixup sheet (autoReset: \(autoReset, privacy: .public))")
            menuBar.openFixupSheet(autoReset: autoReset)
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
