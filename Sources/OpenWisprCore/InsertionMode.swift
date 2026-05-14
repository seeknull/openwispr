import Foundation

/// How OpenWispr inserts transcript text into the focused app.
///
/// Both modes require the **Accessibility** permission so OpenWispr can post
/// synthetic input events to the system.
public enum InsertionMode: String, CaseIterable, Codable, Sendable {
    /// Save current clipboard → write transcript to clipboard → post Cmd+V →
    /// restore clipboard ~80ms later. Works in essentially every app
    /// (Electron, web, native), instant for long transcripts, but briefly
    /// clobbers the clipboard. Default.
    case clipboardPaste

    /// Synthesize one CGEvent keystroke per character. No clipboard
    /// interference but slower for long transcripts and sensitive to
    /// IME state in some apps.
    case keystroke

    public var displayName: String {
        switch self {
        case .clipboardPaste: return "Paste via clipboard"
        case .keystroke:      return "Synthesize keystrokes"
        }
    }

    public var helpText: String {
        switch self {
        case .clipboardPaste:
            return "Fast and works everywhere. Briefly overwrites the clipboard before restoring it."
        case .keystroke:
            return "Types each character. No clipboard interference, but slower for long transcripts."
        }
    }
}
