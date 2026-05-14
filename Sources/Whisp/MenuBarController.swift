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
    private var fixupWindow: NSWindow?
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
            // Keep the hotkey state machine's bookkeeping in sync with the
            // engine. Without this, the next hotkey press could toggle from
            // a stale "true" → "false" and silently no-op against an
            // already-stopped engine, requiring a second press to actually
            // start.
            hotkey.syncListeningState(false)
        case .listening:
            statusItem.button?.image = listeningIcon
            statusItem.button?.image?.isTemplate = false
            if settings.showHUD { hud.show() }
            hotkey.syncListeningState(true)
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

    @objc func openSettings() {
        permissions.refresh()
        if settingsWindow == nil {
            let view = SettingsView(
                settings: settings,
                permissions: permissions,
                onCheckPermissions: { [weak self] in self?.permissions.refresh() }
            )
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "Whisp Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            window.identifier = NSUserInterfaceItemIdentifier("WhispSettingsWindow")
            window.setAccessibilityIdentifier("WhispSettingsWindow")
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openPermissions() {
        openSettings()
    }

    /// Show the rebuild-rescue sheet. Used both automatically on launch
    /// (when PermissionsManager flags a signature mismatch) and from the
    /// menu bar's "Reset Permissions…" item.
    func openFixupSheet(autoReset: Bool) {
        permissions.refresh()
        if autoReset {
            // Run tccutil first so the user opens System Settings into a
            // cleaned-up state. Stale rows still show, but the underlying
            // decision is cleared, which avoids confusion when they re-toggle.
            permissions.runAutoFixup()
        }
        if fixupWindow == nil {
            let view = FixupSheetView(
                permissions: permissions,
                onClose: { [weak self] in self?.fixupWindow?.close() }
            )
            let host = NSHostingController(rootView: view)
            // Pin the hosting controller to the view's intrinsic size and
            // disable SwiftUI's auto-resize negotiation with the window.
            // Without this, switching steps inside the view triggers a
            // window constraint thrash that macOS 26 turns into a fatal
            // exception (-[NSApplication _crashOnException:]).
            host.sizingOptions = []
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = host
            window.title = "Whisp — Re-grant permissions"
            window.isReleasedWhenClosed = false
            // Float above other windows so when the user opens System
            // Settings to grant a permission, the fixup window stays
            // visible and they can see the live status update.
            window.level = .floating
            // Stay open across spaces and when other apps activate.
            window.collectionBehavior = [.canJoinAllSpaces, .moveToActiveSpace]
            window.center()
            window.identifier = NSUserInterfaceItemIdentifier("WhispFixupWindow")
            window.setAccessibilityIdentifier("WhispFixupWindow")
            fixupWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        fixupWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func resetPermissions() {
        openFixupSheet(autoReset: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
