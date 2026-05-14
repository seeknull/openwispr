import AVFoundation
import Foundation
import OSLog

/// Live microphone input level, sampled in parallel with whatever
/// MoonshineVoice's `MicTranscriber` is doing. Drives the HUD's bar
/// visualizer so users can see at a glance that the mic is hearing
/// them — not just that the app *says* it's listening.
///
/// ## How it works
///
/// We install our own tap on `AVAudioEngine.inputNode`. The tap callback
/// fires ~50× per second (controlled by the buffer size); each callback
/// we compute the RMS of the frames in the buffer, convert to a 0...1
/// magnitude, smooth lightly, and publish.
///
/// This is intentionally separate from MoonshineVoice's tap on the same
/// node — `AVAudioEngine` supports multiple taps on the same bus, so
/// the two coexist without interfering. Going through a parallel tap
/// avoids any coupling to MoonshineVoice's internals.
///
/// ## Threading
///
/// The tap fires on an audio thread. We publish through a closure
/// the caller hands us; the caller is responsible for hopping to the
/// main thread before touching UI. Doing the dispatch here would
/// stack frames per buffer.
@MainActor
final class AudioLevelMeter {
    private let log = Logger(subsystem: "dev.openwispr.app", category: "AudioLevelMeter")

    /// Called on an arbitrary audio thread every time a new buffer is
    /// processed. Caller should `DispatchQueue.main.async` before
    /// touching UI.
    typealias LevelHandler = @Sendable (Float) -> Void

    private var engine: AVAudioEngine?
    private let onLevel: LevelHandler

    /// Smoothing coefficient: 0.0 = no smoothing (instant response,
    /// jittery), 1.0 = never updates. 0.6 sits comfortably between.
    private nonisolated(unsafe) var smoothedLevel: Float = 0
    private let smoothing: Float = 0.6

    init(onLevel: @escaping LevelHandler) {
        self.onLevel = onLevel
    }

    deinit {
        // Tap removal happens on stop(); deinit ordering guarantees the
        // engine is already gone if it ever existed.
    }

    /// Start sampling. Idempotent — safe to call again on an already-
    /// running meter (no-op).
    func start() {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        // 1024 frames @ 48kHz ≈ 21ms — fast enough to feel live, slow
        // enough that we don't waste CPU updating 100×/sec.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let raw = AudioLevelMeter.rms(of: buffer)
            // Exponential smoothing so the visualizer doesn't twitch
            // on transient peaks.
            let smoothed = self.smoothing * self.smoothedLevel + (1 - self.smoothing) * raw
            self.smoothedLevel = smoothed
            self.onLevel(smoothed)
        }
        do {
            engine.prepare()
            try engine.start()
            self.engine = engine
            log.info("AudioLevelMeter started")
        } catch {
            log.error("Failed to start audio engine: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stop sampling. Idempotent.
    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        smoothedLevel = 0
        self.engine = nil
        log.info("AudioLevelMeter stopped")
    }

    /// Compute the RMS amplitude of an audio buffer and map it into
    /// a 0...1 visualization range.
    ///
    /// Raw RMS for normal speech sits around 0.05-0.3; we boost via a
    /// gentle curve so quiet voices still register visually.
    nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        let samples = channels[0]
        var sumOfSquares: Float = 0
        for i in 0..<frameLength {
            let s = samples[i]
            sumOfSquares += s * s
        }
        let mean = sumOfSquares / Float(frameLength)
        let rms = mean.squareRoot()

        // Visualization curve: sqrt(rms) maps the typical speech range
        // ~0.05-0.30 into a comfortably visible 0.22-0.55 band. Clamped
        // so unusually loud input still maxes at 1.0 cleanly.
        let visual = min(1.0, rms.squareRoot() * 1.6)
        return visual
    }
}
