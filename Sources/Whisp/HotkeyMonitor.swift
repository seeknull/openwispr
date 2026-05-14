import AppKit
import CoreGraphics
import OSLog
import WhispCore

private let log = Logger(subsystem: "ai.whisp.app", category: "HotkeyMonitor")

/// Watches for the configured hotkey at the HID level using a CGEventTap.
///
/// Why an event tap and not `NSEvent.addGlobalMonitor`:
///   - The Fn (function) key is **not** reported through the standard
///     `NSEvent.modifierFlags` mask. It surfaces only via `CGEventFlags`
///     including `.maskSecondaryFn`, which means we need a tap at the
///     CGEvent level.
///   - We want to suppress the default Fn behaviour (which on macOS
///     opens the emoji/character picker by default in recent versions)
///     while a session is active. An event tap allows that suppression
///     by returning `nil` for the captured event.
///
/// Trade-offs:
///   - The user must grant **Input Monitoring** permission for our app.
///     macOS prompts once on first install when `CGEvent.tapCreate` is called
///     with `listenOnly: false`. We use `listenOnly: true` to avoid asking
///     for that elevated grant — we don't suppress the Fn key today.
final class HotkeyMonitor {
    typealias ToggleHandler = @MainActor (HotkeyStateMachine.Effect) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
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

    /// Starts the event tap. Safe to call when the Input Monitoring permission
    /// has not been granted: the tap creation will fail and the caller can
    /// observe `isRunning == false` to drive a permission prompt.
    @discardableResult
    func start() -> Bool {
        stop()

        // listenOnly: we observe modifier flag changes but never swallow events
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let unmanagedSelf = Unmanaged.passUnretained(self)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: unmanagedSelf.toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        return true
    }

    var isRunning: Bool { eventTap != nil }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
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

    private func handle(type: CGEventType, event: CGEvent) {
        // If the tap was disabled (e.g., system rejected an unusual amount of
        // work in the callback), re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            log.warning("Event tap disabled (\(type.rawValue, privacy: .public)) — re-enabling")
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .flagsChanged else { return }

        let flags = event.flags
        let held = modifiersAllHeld(flags: flags)

        // Trace at debug level: every flagsChanged event we see, with the
        // raw mask, whether our hotkey is satisfied, and what the state
        // machine decides. Surface with:
        //   log stream --predicate 'subsystem == "ai.whisp.app"' --level=debug
        log.debug("flagsChanged raw=\(flags.rawValue, privacy: .public) held=\(held, privacy: .public)")

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

    private func modifiersAllHeld(flags: CGEventFlags) -> Bool {
        for m in config.modifiers {
            switch m {
            case .fn:      if !flags.contains(.maskSecondaryFn)   { return false }
            case .option:  if !flags.contains(.maskAlternate)     { return false }
            case .command: if !flags.contains(.maskCommand)       { return false }
            case .control: if !flags.contains(.maskControl)       { return false }
            case .shift:   if !flags.contains(.maskShift)         { return false }
            }
        }
        return !config.modifiers.isEmpty
    }
}
