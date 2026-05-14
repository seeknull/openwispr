import AppKit
import Combine
import SwiftUI
import WhispCore

/// Owns the `NSStatusItem` in the menu bar and the right-click/click menu.
/// Listens to `DictationEngine` state and re-renders the icon.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let engine: DictationEngine
    private let hotkey: HotkeyMonitor
    private let permissions: PermissionsManager
    private let settings: WhispSettings
    private let hud = ListeningHUD()
    private var settingsWindow: NSWindow?
    private var currentState: DictationState = .idle

    init(
        engine: DictationEngine,
        hotkey: HotkeyMonitor,
        permissions: PermissionsManager,
        settings: WhispSettings
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.engine = engine
        self.hotkey = hotkey
        self.permissions = permissions
        self.settings = settings
        super.init()

        configureStatusItem()
        engine.onStateChange = { [weak self] state in
            self?.applyState(state)
        }
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = idleIcon
            button.image?.isTemplate = true
            button.toolTip = "Whisp — \(settings.hotkeyConfig.displayName) to dictate"
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: engine.isListening ? "Stop Dictating" : "Start Dictating",
            action: #selector(toggleDictation),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

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

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Whisp", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit Whisp", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    func applyState(_ state: DictationState) {
        currentState = state
        switch state {
        case .idle:
            statusItem.button?.image = idleIcon
            statusItem.button?.image?.isTemplate = true
            hud.hide()
            hotkey.syncListeningState(false)
        case .starting:
            // Same visual as idle; engine will flip us to .listening
            // within ~ms once it warms up. We could draw a pulsing
            // amber dot here but it's brief enough to skip.
            statusItem.button?.image = idleIcon
        case .listening:
            statusItem.button?.image = listeningIcon
            statusItem.button?.image?.isTemplate = false
            if settings.showHUD { hud.show() }
            hotkey.syncListeningState(true)
        case .stopping:
            // Hide the HUD eagerly; engine will flip us to .idle once
            // the final transcript line flushes.
            hud.hide()
        case .error(let msg):
            statusItem.button?.image = idleIcon
            statusItem.button?.toolTip = "Whisp — \(msg)"
            hud.hide()
            hotkey.syncListeningState(false)
        }
        // Refresh menu so the toggle item title matches.
        statusItem.menu = buildMenu()
    }

    // MARK: - Icons

    private var idleIcon: NSImage? {
        let img = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Whisp idle")
        return img
    }

    /// While listening we draw an explicit red record dot so it's obvious
    /// from across the menu bar. SF Symbols' palette colors are sometimes
    /// stripped by the menu bar renderer, so we render a custom NSImage.
    private var listeningIcon: NSImage? {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Soft red record dot, slightly larger than centered
            NSColor.systemRed.setFill()
            let dot = NSBezierPath(ovalIn: NSRect(x: rect.width / 2 - 5,
                                                  y: rect.height / 2 - 5,
                                                  width: 10, height: 10))
            dot.fill()
            return true
        }
        image.isTemplate = false  // preserve the red tint
        image.accessibilityDescription = "Whisp listening"
        return image
    }

    // MARK: - Menu actions

    @objc private func toggleDictation() {
        if engine.isListening {
            engine.stop()
            hotkey.forceStop()
        } else {
            // Make sure permissions are present before starting.
            permissions.refresh()
            guard permissions.allGranted else {
                openPermissions()
                return
            }
            engine.start()
        }
    }

    /// Build (lazily) and surface the Settings window. We build the
    /// NSWindow + NSHostingController by hand for full lifecycle control;
    /// the macOS 26 crash that previously plagued this path was triggered
    /// by a Timer.publish poll inside the SwiftUI view, not by the
    /// hosting setup itself. SettingsView no longer polls.
    @objc func openSettings() {
        permissions.refresh()
        if settingsWindow == nil {
            let view = SettingsView(
                settings: settings,
                permissions: permissions,
                onCheckPermissions: { [weak self] in self?.permissions.refresh() }
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
            // Stay visible when System Settings (or any other app) steals
            // focus. Default behaviour for accessory-policy apps is to
            // hide the window on deactivate, which made the Settings
            // window vanish every time the user clicked "Open Settings".
            window.hidesOnDeactivate = false
            // Float above other apps so the user can see live status
            // updates while interacting with System Settings.
            window.level = .floating
            // `canJoinAllSpaces` and `moveToActiveSpace` are mutually
            // exclusive — combining them throws NSInvalidArgument and
            // aborts the app. Just join all spaces so the window stays
            // visible across desktops.
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

    /// "Reset Permissions…" menu action. Clears TCC entries and opens
    /// Settings → Permissions tab so the user can re-grant.
    func runFixupFlow() {
        permissions.refresh()
        permissions.runAutoFixup()
        openSettings()
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func resetPermissions() {
        runFixupFlow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
