import AVFoundation
import Foundation
import MoonshineVoice
import OSLog
import OpenWisprCore

/// Wraps `MicTranscriber` plus a `TranscriptBuffer` and drives the text
/// injector. One instance lives for the lifetime of the app; `start()`
/// and `stop()` flip listening on the underlying transcriber without
/// reloading the model.
@MainActor
final class DictationEngine {
    private let log = Logger(subsystem: "dev.openwispr.app", category: "DictationEngine")

    private let modelPath: String
    private let modelArch: ModelArch
    private let injector: TextInjector

    private var transcriber: MicTranscriber?
    private var buffer = TranscriptBuffer()
    private var listener: Listener?
    private(set) var isListening: Bool = false

    /// `(state, errorMessage)` — observers in MenuBarController re-render UI.
    var onStateChange: ((DictationState) -> Void)?

    init(modelPath: String, modelArch: ModelArch, injector: TextInjector) {
        self.modelPath = modelPath
        self.modelArch = modelArch
        self.injector = injector
    }

    // We rely on `MicTranscriber`'s own deinit for cleanup. A custom
    // `deinit` here would need to touch the non-Sendable transcriber
    // from a nonisolated context, which Swift 6 rightly flags as a
    // data race.

    func start() {
        guard !isListening else { return }

        do {
            // Lazy-create on first start to avoid spending ~1s of model-load
            // time at app launch. Subsequent starts reuse the same instance.
            if transcriber == nil {
                let mic = try MicTranscriber(
                    modelPath: modelPath,
                    modelArch: modelArch
                )
                let listener = Listener { [weak self] text in
                    guard let self else { return }
                    Task { @MainActor in
                        if let toInject = self.buffer.ingestCompletedLine(text) {
                            self.injector.insert(toInject)
                        }
                    }
                }
                mic.addListener(listener)
                self.transcriber = mic
                self.listener = listener
            }

            buffer.reset()
            try transcriber?.start()
            isListening = true
            onStateChange?(.listening)
            log.info("Listening started")
        } catch {
            let message = "Failed to start dictation: \(error.localizedDescription)"
            log.error("\(message, privacy: .public)")
            onStateChange?(.error(message))
            // Bounce back to idle after surfacing the error.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                self.onStateChange?(.idle)
            }
        }
    }

    func stop() {
        guard isListening, let transcriber else {
            onStateChange?(.idle)
            return
        }
        do {
            try transcriber.stop()
        } catch {
            log.error("Stop error: \(error.localizedDescription, privacy: .public)")
        }
        isListening = false
        onStateChange?(.idle)
        log.info("Listening stopped (lines emitted: \(self.buffer.emittedLineCount))")
    }
}

/// TranscriptEventListener that forwards completed lines to a closure.
/// Stays a separate class so MicTranscriber's `addListener(_:)` can retain it.
private final class Listener: TranscriptEventListener {
    let onCompleted: (String) -> Void

    init(onCompleted: @escaping (String) -> Void) {
        self.onCompleted = onCompleted
    }

    func onLineStarted(_ event: LineStarted) {}
    func onLineUpdated(_ event: LineUpdated) {}
    func onLineTextChanged(_ event: LineTextChanged) {}
    func onLineCompleted(_ event: LineCompleted) {
        onCompleted(event.line.text)
    }
}
