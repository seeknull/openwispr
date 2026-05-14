import AppKit
import OSLog
import WhispCore

private let log = Logger(subsystem: "ai.whisp.dev", category: "HotkeyMonitor")

/// Watches for the configured hotkey using **`NSEvent.addGlobalMonitorForEvents`**.
///
/// ## Why this and not CGEventTap
///
/// `CGEventTap` requires the **Input Monitoring** TCC entitlement. macOS 26
/// silently denies that grant for ad-hoc / unsigned apps via
/// `IOHIDRequestAccess` (we verified this by reading tccd's log), with no
/// way to recover programmatically.
///
/// `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` only needs
/// **Accessibility** — and we need Accessibility anyway for keystroke
/// injection. So this halves our TCC surface area: one permission instead
/// of two, and a permission that does work for ad-hoc apps.
///
/// Trade-off: NSEvent global monitors see events but can't *suppress* them.
/// That's fine — Whisp never wanted to swallow Fn+Option anyway. The Fn
/// key's default behaviour (which on recent macOS opens a "Press 🌐 key to"
/// configured action) still fires, but the user can set that to "Do
/// Nothing" in System Settings → Keyboard to silence it.
///
/// Local monitor (`NSEvent.addLocalMonitorForEvents`) covers the case where
/// Whisp itself has key focus — global monitors deliver events only when
/// another app is frontmost. We install both so the hotkey works whether
/// the focus is on Whisp's settings window or on someone else's editor.
final class HotkeyMonitor {
    typealias ToggleHandler = @MainActor (HotkeyStateMachine.Effect) -> Void

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var stateMachine = HotkeyStateMachine()
    private var config: HotkeyConfig
    private let onEffect: ToggleHandler

    init(config: HotkeyConfig = .default, onEffect: @escaping ToggleHandler) {
        self.config = config
        self.onEffect = onEffect
    }

    func updateConfig(_ newConfig: HotkeyConfig) {
        config = newConfig
    }

    @discardableResult
    func start() -> Bool {
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        // Local monitor must return the event (or nil to swallow). We never
        // swallow; just observe.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }

        return globalMonitor != nil
    }

    var isRunning: Bool { globalMonitor != nil }

    func stop() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor  { NSEvent.removeMonitor(l); localMonitor = nil }
    }

    /// Programmatically stop a listening session (e.g. menu bar "Stop" item).
    func forceStop() {
        let effect = stateMachine.forceStop()
        if effect != .none {
            let handler = onEffect
            Task { @MainActor in handler(effect) }
        }
    }

    /// Sync the state machine's `listening` flag without firing an effect.
    /// Call this when an external trigger (menu bar Start item, engine
    /// error) changes the real listening state so the next hotkey press
    /// behaves as a clean toggle.
    func syncListeningState(_ isListening: Bool) {
        stateMachine.setListening(isListening)
    }

    private func handle(_ event: NSEvent) {
        let held = modifiersAllHeld(flags: event.modifierFlags, deviceIndependentFlags: event.modifierFlags.intersection(.deviceIndependentFlagsMask))

        // NSEvent.modifierFlags reports Fn via .function — unlike CGEvent's
        // .maskSecondaryFn, this is a published, supported API. Trace at
        // debug level so we can see what we're getting:
        //   log stream --predicate 'subsystem == "ai.whisp.dev"' --level=debug
        log.debug("flagsChanged raw=\(event.modifierFlags.rawValue, privacy: .public) held=\(held, privacy: .public)")

        let now = Date().timeIntervalSinceReferenceDate
        let effect: HotkeyStateMachine.Effect = held
            ? stateMachine.modifiersPressed(now: now)
            : stateMachine.modifiersReleased()

        if effect != .none {
            log.info("Hotkey effect: \(String(describing: effect), privacy: .public)")
            let handler = onEffect
            Task { @MainActor in handler(effect) }
        }
    }

    private func modifiersAllHeld(flags: NSEvent.ModifierFlags, deviceIndependentFlags: NSEvent.ModifierFlags) -> Bool {
        for m in config.modifiers {
            switch m {
            case .fn:      if !flags.contains(.function) { return false }
            case .option:  if !flags.contains(.option)   { return false }
            case .command: if !flags.contains(.command)  { return false }
            case .control: if !flags.contains(.control)  { return false }
            case .shift:   if !flags.contains(.shift)    { return false }
            }
        }
        return !config.modifiers.isEmpty
    }
}
