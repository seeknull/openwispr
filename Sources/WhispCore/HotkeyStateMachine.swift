import Foundation

/// Pure-logic toggle for the global dictation hotkey. The `HotkeyMonitor`
/// (AppKit/CoreGraphics layer) feeds raw key events here; this struct
/// debounces repeats and decides when to start/stop a session.
///
/// Separating this from the event-tap glue keeps the policy testable
/// without spinning up a real CGEventTap.
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

    /// Debounce window: a press that releases and re-presses within this
    /// window is treated as a single press to avoid hotkey chatter from
    /// repeat-fire when the Fn key is held down briefly.
    public let debounceInterval: TimeInterval

    private var lastToggleAt: TimeInterval?

    public init(debounceInterval: TimeInterval = 0.2) {
        self.debounceInterval = debounceInterval
    }

    /// Call when the hotkey modifier mask transitions to "all held".
    /// `now` is provided as a parameter to keep this deterministic in tests.
    public mutating func modifiersPressed(now: TimeInterval) -> Effect {
        guard !modifiersHeld else { return .none }
        modifiersHeld = true

        if let last = lastToggleAt, now - last < debounceInterval {
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
}
