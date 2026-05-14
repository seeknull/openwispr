import Foundation

/// Identifies the modifier keys that, when all held simultaneously, toggle
/// the listening state. Independent of CGEvent so it can be tested without
/// the full event-tap pipeline.
public struct HotkeyConfig: Equatable, Codable, Sendable {
    public enum Modifier: String, Codable, CaseIterable, Sendable {
        case fn
        case option   // aka alt
        case command
        case control
        case shift

        public var displayName: String {
            switch self {
            case .fn:      return "Fn"
            case .option:  return "⌥ Option"
            case .command: return "⌘ Command"
            case .control: return "⌃ Control"
            case .shift:   return "⇧ Shift"
            }
        }
    }

    public var modifiers: Set<Modifier>

    public init(modifiers: Set<Modifier>) {
        self.modifiers = modifiers
    }

    /// Default: hold Fn+Option to toggle listening.
    public static let `default` = HotkeyConfig(modifiers: [.fn, .option])

    public var displayName: String {
        // Stable order for display
        let order: [Modifier] = [.control, .option, .shift, .command, .fn]
        return order.filter { modifiers.contains($0) }
            .map(\.displayName)
            .joined(separator: " + ")
    }
}
