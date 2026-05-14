import Foundation

/// The high-level state of the dictation session. Drives the menu bar icon,
/// the HUD, and whether the mic + transcriber are running.
public enum DictationState: Equatable, Sendable {
    /// Idle — hotkey not pressed, no audio capture, no transcriber running.
    case idle
    /// Listening — mic is open, audio is being captured and transcribed,
    /// and finalized lines flow to the text injector.
    case listening
    /// A transient error surfaced by the engine. The UI shows the message
    /// and returns to `.idle`.
    case error(String)

    public var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}
