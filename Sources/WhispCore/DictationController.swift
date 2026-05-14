import Foundation

/// Pure-logic command dispatcher for the dictation lifecycle. The AppKit
/// layer holds a `DictationController` (which holds the state) and routes
/// commands through it; observers can subscribe to state transitions.
///
/// All inputs are commands (`toggle`, `start`, `stop`, `fail`). All
/// outputs are state transitions. This makes the lifecycle testable
/// without spinning up CGEventTap or MicTranscriber.
public final class DictationController: @unchecked Sendable {
    public private(set) var state: DictationState = .idle {
        didSet {
            guard state != oldValue else { return }
            for observer in observers.values { observer(state) }
        }
    }

    public typealias Observer = (DictationState) -> Void
    private var observers: [UUID: Observer] = [:]
    private let lock = NSLock()

    public init() {}

    /// Subscribe to state transitions. Returns a token; pass it back to
    /// `removeObserver(_:)` to unsubscribe.
    @discardableResult
    public func addObserver(_ block: @escaping Observer) -> UUID {
        lock.lock(); defer { lock.unlock() }
        let token = UUID()
        observers[token] = block
        block(state)
        return token
    }

    public func removeObserver(_ token: UUID) {
        lock.lock(); defer { lock.unlock() }
        observers.removeValue(forKey: token)
    }

    // MARK: - Commands

    /// Toggle is what the hotkey + menu bar Start/Stop item both send.
    /// Idempotent in the sense that a toggle from `.starting` does
    /// nothing (we're already trying to start).
    public func toggle() {
        switch state {
        case .idle, .error:    state = .starting
        case .listening:       state = .stopping
        case .starting, .stopping: break
        }
    }

    /// Engine reports it has fully started.
    public func engineDidStart() {
        switch state {
        case .starting, .idle, .error: state = .listening
        case .listening, .stopping:    break
        }
    }

    /// Engine reports it has fully stopped.
    public func engineDidStop() {
        switch state {
        case .stopping, .listening, .starting: state = .idle
        case .idle, .error: break
        }
    }

    /// Engine reports a failure.
    public func engineFailed(_ message: String) {
        state = .error(message)
    }

    /// User dismissed the error.
    public func dismissError() {
        if case .error = state { state = .idle }
    }
}
