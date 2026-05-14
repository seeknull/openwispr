import Foundation

/// Single source of truth for the dictation lifecycle. Every component
/// (menu bar icon, HUD, hotkey state machine, dictation engine) reads
/// from this and reacts to its transitions — nobody else stores
/// "are we listening?" as a separate boolean.
///
/// We've previously had three drifting copies of this fact
/// (HotkeyStateMachine.listening, DictationEngine.isListening, and the
/// MicTranscriber's internal state). One copy is the only reliable
/// number.
public enum DictationState: Equatable, Sendable {
    /// Idle — hotkey not pressed, no audio capture, no transcriber running.
    case idle
    /// We've been asked to start but the engine is still warming up
    /// (model loading, mic permission prompt, audio device setup). Brief.
    case starting
    /// Listening — mic is open, audio is being captured and transcribed,
    /// and finalized lines flow to the text injector.
    case listening
    /// User pressed the hotkey to stop; we're flushing the final
    /// transcript line. Also brief.
    case stopping
    /// A failure surfaced by the engine. The UI shows the message and
    /// the user can dismiss to return to `.idle`.
    case error(String)

    public var isActive: Bool {
        switch self {
        case .idle, .error: return false
        case .starting, .listening, .stopping: return true
        }
    }

    /// True only when the engine is fully running. Used to drive the
    /// red record-dot menu bar icon.
    public var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}
