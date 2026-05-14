import AppKit
import CoreGraphics
import WhispCore

/// Inserts text into whatever app currently has keyboard focus. Two
/// strategies, selectable via `InsertionMode`.
///
/// Both require Accessibility permission (granted in
/// System Settings → Privacy & Security → Accessibility).
@MainActor
final class TextInjector {
    var mode: InsertionMode

    init(mode: InsertionMode) {
        self.mode = mode
    }

    /// Insert `text` at the current cursor location. No-op for empty strings.
    func insert(_ text: String) {
        guard !text.isEmpty else { return }
        switch mode {
        case .clipboardPaste: pasteViaClipboard(text)
        case .keystroke:      typeAsKeystrokes(text)
        }
    }

    // MARK: - Clipboard paste

    private func pasteViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        // Snapshot the current clipboard so we can restore it. Pasteboard
        // contents are typed; we capture each non-empty type.
        let snapshot: [(NSPasteboard.PasteboardType, Data)] = pasteboard.types?.compactMap {
            type in
            guard let data = pasteboard.data(forType: type) else { return nil }
            return (type, data)
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        sendCmdV()

        // Restore after the receiving app has had time to consume the paste.
        // Empirically, 120ms is conservative for slow apps (Slack web, Notion).
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) {
            pasteboard.clearContents()
            for (type, data) in snapshot {
                pasteboard.setData(data, forType: type)
            }
        }
    }

    private func sendCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 0x09 // ANSI "v"
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Synthesized keystrokes

    private func typeAsKeystrokes(_ text: String) {
        // CGEventKeyboardSetUnicodeString lets us post arbitrary Unicode
        // without per-keycode lookup. We send one key-down + key-up per
        // character with the character set as the event's unicode string.
        let src = CGEventSource(stateID: .combinedSessionState)
        for scalar in text.unicodeScalars {
            var chars = [UniChar(scalar.value)]
            // Skip surrogate halves — UniChar can't represent them solo and
            // the resulting events would be invalid.
            if scalar.value > UInt16.max { continue }

            let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)

            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}
