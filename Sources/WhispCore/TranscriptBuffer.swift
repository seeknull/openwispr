import Foundation

/// Tracks finalized transcript text emitted during a single listening session
/// and produces the delta that should be injected at the cursor each time a
/// transcript line is completed or text-changed.
///
/// Moonshine emits text-changed events as the user is still speaking (the
/// suffix can shrink when the model revises). Whisp can't undo what it's
/// already typed in another app, so the safest strategy is:
///
///   - Wait for `lineCompleted` events.
///   - Emit `line.text` (plus a trailing space) once per completed line.
///
/// `partialMode = true` enables a more eager strategy where text-changed
/// events flow through as well, deferred via a small debounce. This is left
/// off by default — UX is jumpy when revisions land.
public struct TranscriptBuffer: Sendable {
    public private(set) var emittedLineCount: Int = 0
    public let appendsTrailingSpace: Bool

    public init(appendsTrailingSpace: Bool = true) {
        self.appendsTrailingSpace = appendsTrailingSpace
    }

    /// Returns the string to inject for a newly completed line, or `nil`
    /// if there is nothing meaningful to type (empty/whitespace only).
    public mutating func ingestCompletedLine(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        emittedLineCount += 1
        return appendsTrailingSpace ? trimmed + " " : trimmed
    }

    /// Reset between sessions.
    public mutating func reset() {
        emittedLineCount = 0
    }
}
