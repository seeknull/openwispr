import AppKit
import SwiftUI
import WhispCore

/// Owns the `NSStatusItem` in the menu bar. Subscribes to `DictationController`
/// for state changes and to `SelfTest` for health-check results; renders
/// both into the menu bar icon and tooltip.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let dictation: DictationController
    private let engine: DictationEngine
    private let hotkey: HotkeyMonitor
    private let permissions: PermissionsManager
    private let settings: WhispSettings
    private let selfTest: SelfTest
    private let hud = ListeningHUD()
    private var settingsWindow: NSWindow?
    private var dictationObserver: UUID?
    private var lastSelfTest: SelfTestResult?

    init(
        dictation: DictationController,
        engine: DictationEngine,
        hotkey: HotkeyMonitor,
        permissions: PermissionsManager,
        settings: WhispSettings,
        selfTest: SelfTest
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.dictation = dictation
        self.engine = engine
        self.hotkey = hotkey
        self.permissions = permissions
        self.settings = settings
        self.selfTest = selfTest
        super.init()

        configureStatusItem()
        dictationObserver = dictation.addObserver { [weak self] state in
            Task { @MainActor in self?.applyState(state) }
        }
        // Bridge engine.onStateChange into the controller — when the
        // engine reports listening/idle/error, push it into the
        // controller and observers (including us) get notified.
        engine.onStateChange = { [weak self] engineState in
            guard let self else { return }
            switch engineState {
            case .listening: self.dictation.engineDidStart()
            case .idle:      self.dictation.engineDidStop()
            case .error(let m): self.dictation.engineFailed(m)
            case .starting, .stopping: break  // controller handles
            }
        }
    }

    deinit {
        if let t = dictationObserver { dictation.removeObserver(t) }
    }

    func runSelfTestAndRefreshIcon() {
        lastSelfTest = selfTest.run()
        updateIconAndTooltip()
    }

    private func configureStatusItem() {
        statusItem.menu = buildMenu()
        updateIconAndTooltip()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: dictation.state.isListening ? "Stop Dictating" : "Start Dictating",
            action: #selector(toggleDictation),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        // SelfTest summary as a disabled item so the user can see at-a-
        // glance what's wrong without opening Settings. Greyed out
        // because it's informational.
        if let result = lastSelfTest {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "Status: \(result.summary)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let perms = NSMenuItem(title: "Check Permissions…", action: #selector(openPermissions), keyEquivalent: "")
        perms.target = self
        menu.addItem(perms)

        let resetItem = NSMenuItem(
            title: "Reset Permissions…",
            action: #selector(resetPermissions),
            keyEquivalent: ""
        )
        resetItem.target = self
        menu.addItem(resetItem)

        let runSelfTestItem = NSMenuItem(
            title: "Run Self-Test",
            action: #selector(runSelfTest),
            keyEquivalent: ""
        )
        runSelfTestItem.target = self
        menu.addItem(runSelfTestItem)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Whisp", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit Whisp", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func applyState(_ state: DictationState) {
        switch state {
        case .idle:
            hud.hide()
            hotkey.syncListeningState(false)
        case .starting:
            break  // brief; idle icon is fine
        case .listening:
            if settings.showHUD { hud.show() }
            hotkey.syncListeningState(true)
        case .stopping:
            hud.hide()
        case .error:
            hud.hide()
            hotkey.syncListeningState(false)
        }
        updateIconAndTooltip()
    }

    // MARK: - Icons

    /// Drives the menu bar icon from BOTH `DictationController.state` AND
    /// the latest `SelfTestResult`. Listening always wins (red record dot),
    /// then failures (red triangle), then warnings (amber triangle),
    /// otherwise idle (clean waveform).
    private func updateIconAndTooltip() {
        let state = dictation.state
        let test = lastSelfTest

        let icon: NSImage?
        let tooltip: String

        if state.isListening {
            icon = listeningIcon
            tooltip = "Whisp — listening (\(settings.hotkeyConfig.displayName) to stop)"
        } else if case .failure(let m) = test?.overall {
            icon = warningIcon(color: .systemRed)
            tooltip = "Whisp — not ready: \(m)"
        } else if case .warning(let m) = test?.overall {
            icon = warningIcon(color: .systemOrange)
            tooltip = "Whisp — degraded: \(m)"
        } else {
            icon = idleIcon
            tooltip = "Whisp — \(settings.hotkeyConfig.displayName) to dictate"
        }

        if let button = statusItem.button {
            button.image = icon
            button.toolTip = tooltip
        }
        // Refresh menu so the toggle title and status line reflect state.
        statusItem.menu = buildMenu()
    }

    private var idleIcon: NSImage? {
        let img = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Whisp idle")
        img?.isTemplate = true
        return img
    }

    /// Red record dot — used while listening.
    private var listeningIcon: NSImage? {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.systemRed.setFill()
            let dot = NSBezierPath(ovalIn: NSRect(x: rect.width / 2 - 5,
                                                  y: rect.height / 2 - 5,
                                                  width: 10, height: 10))
            dot.fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Whisp listening"
        return image
    }

    /// Filled triangle, used for failure (red) or warning (amber) states.
    private func warningIcon(color: NSColor) -> NSImage? {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            let path = NSBezierPath()
            let inset: CGFloat = 4
            path.move(to: NSPoint(x: rect.midX, y: rect.maxY - inset))
            path.line(to: NSPoint(x: rect.maxX - inset, y: rect.minY + inset))
            path.line(to: NSPoint(x: rect.minX + inset, y: rect.minY + inset))
            path.close()
            path.fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Whisp needs attention"
        return image
    }

    // MARK: - Menu actions

    @objc private func toggleDictation() {
        // Quick precheck: if permissions are missing, send the user to
        // Settings instead of trying to start a dictation that'll fail
        // with a confusing error.
        permissions.refresh()
        guard permissions.allGranted else {
            openSettings()
            return
        }

        // Hand off to DictationController; engine listens for the
        // resulting state transition and acts.
        let wasListening = dictation.state.isListening
        dictation.toggle()
        // The controller's state transition triggers the engine via
        // the bridge installed in init. We also drive the engine
        // directly here as a belt-and-braces measure.
        if wasListening {
            engine.stop()
        } else {
            engine.start()
        }
    }

    /// Build (lazily) and surface the Settings window.
    @objc func openSettings() {
        permissions.refresh()
        runSelfTestAndRefreshIcon()
        if settingsWindow == nil {
            let view = SettingsView(
                settings: settings,
                permissions: permissions,
                onCheckPermissions: { [weak self] in
                    self?.permissions.refresh()
                    self?.runSelfTestAndRefreshIcon()
                }
            )
            let host = NSHostingController(rootView: view)
            host.sizingOptions = []
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = host
            window.title = "Whisp Settings"
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces]
            window.center()
            window.identifier = NSUserInterfaceItemIdentifier(AppDelegate.settingsWindowID)
            window.setAccessibilityIdentifier(AppDelegate.settingsWindowID)
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openPermissions() {
        openSettings()
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func resetPermissions() {
        permissions.hardReset()
    }

    @objc private func runSelfTest() {
        runSelfTestAndRefreshIcon()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
