import Foundation

/// Pure-logic toggle for the global dictation hotkey. The `HotkeyMonitor`
/// (AppKit/CoreGraphics layer) feeds raw key events here; this struct
/// decides when to start/stop a session.
///
/// macOS emits a `flagsChanged` event for *each* modifier key independently.
/// Pressing Fn+Option as a chord produces two events: Fn-down, then Option-
/// down. We treat the moment the **full chord** transitions from "not all
/// held" to "all held" as one logical press. Releasing any key takes us
/// out of that state, so the next time the chord goes fully held again,
/// it's another logical press.
///
/// A short "minimum-gap" guard keeps OS-level autorepeat from re-firing the
/// chord within a few milliseconds. We deliberately keep this short (60ms)
/// — anything longer eats genuine human double-taps.
public struct HotkeyStateMachine: Sendable {
    /// Result of feeding a key event in.
    public enum Effect: Equatable, Sendable {
        case none
        case startListening
        case stopListening
    }

    /// Tracks whether the configured hotkey modifiers are currently held
    /// (e.g. Fn+Option are both down).
    public private(set) var modifiersHeld: Bool = false

    /// Tracks whether the session is "armed" — i.e., the user has triggered
    /// a toggle and we're currently in a listening state.
    public private(set) var listening: Bool = false

    /// Minimum gap between two consecutive toggles. Guards against autorepeat
    /// and event jitter — *not* meant to throttle real human input. 60ms is
    /// well below any deliberate tap cadence.
    public let minimumToggleGap: TimeInterval

    private var lastToggleAt: TimeInterval?

    public init(minimumToggleGap: TimeInterval = 0.06) {
        self.minimumToggleGap = minimumToggleGap
    }

    /// Backwards-compatible alias for older test code that called the
    /// previous parameter name `debounceInterval`.
    public init(debounceInterval: TimeInterval) {
        self.init(minimumToggleGap: debounceInterval)
    }

    public var debounceInterval: TimeInterval { minimumToggleGap }

    /// Call when the hotkey modifier mask transitions to "all held".
    /// `now` is provided as a parameter to keep this deterministic in tests.
    public mutating func modifiersPressed(now: TimeInterval) -> Effect {
        guard !modifiersHeld else { return .none }
        modifiersHeld = true

        if let last = lastToggleAt, now - last < minimumToggleGap {
            return .none
        }
        lastToggleAt = now

        listening.toggle()
        return listening ? .startListening : .stopListening
    }

    /// Call when the modifier mask transitions away from "all held".
    public mutating func modifiersReleased() -> Effect {
        modifiersHeld = false
        return .none
    }

    /// Programmatic stop (e.g. from the menu bar "Stop" item or an error).
    /// Returns `.stopListening` only if we were actually listening.
    public mutating func forceStop() -> Effect {
        defer { listening = false }
        return listening ? .stopListening : .none
    }

    /// Force the internal `listening` flag without producing an effect.
    /// Used when an external source (menu bar Start item, engine error)
    /// has changed the actual listening state and we just need to keep
    /// our bookkeeping in sync so the next hotkey press toggles correctly.
    public mutating func setListening(_ newValue: Bool) {
        listening = newValue
    }
}
