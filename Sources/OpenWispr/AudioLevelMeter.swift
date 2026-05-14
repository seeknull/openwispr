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
/// **Critical**: the AVAudioEngine tap callback runs on an audio (real-
/// time) thread, NOT the main thread. This class is therefore
/// **not** `@MainActor`-isolated — that would crash with a
/// `_dispatch_assert_queue_fail` the first time the audio thread tried
/// to touch any property. We use plain non-isolated storage protected
/// by a lock for the small mutable state that's shared between
/// `start()`/`stop()` (called on main) and the tap callback (audio
/// thread).
///
/// The `onLevel` handler is `@Sendable` and called on the audio thread;
/// the caller is responsible for hopping to main before touching UI.
final class AudioLevelMeter: @unchecked Sendable {
    private let log = Logger(subsystem: "dev.openwispr.app", category: "AudioLevelMeter")

    typealias LevelHandler = @Sendable (Float) -> Void

    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var smoothedLevel: Float = 0

    private let onLevel: LevelHandler
    /// Smoothing coefficient: 0.0 = no smoothing (instant, jittery),
    /// 1.0 = never updates. 0.6 sits comfortably between.
    private let smoothing: Float = 0.6

    init(onLevel: @escaping LevelHandler) {
        self.onLevel = onLevel
    }

    /// Start sampling. Idempotent — safe to call on an already-running
    /// meter (no-op).
    func start() {
        lock.lock()
        guard engine == nil else { lock.unlock(); return }
        lock.unlock()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        // 1024 frames @ 48kHz ≈ 21ms — fast enough to feel live, slow
        // enough that we don't waste CPU updating 100×/sec.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let raw = AudioLevelMeter.rms(of: buffer)

            // Read-modify-write under the lock so concurrent stop()
            // can't see a half-updated value.
            self.lock.lock()
            let previous = self.smoothedLevel
            let smoothed = self.smoothing * previous + (1 - self.smoothing) * raw
            self.smoothedLevel = smoothed
            self.lock.unlock()

            self.onLevel(smoothed)
        }

        do {
            engine.prepare()
            try engine.start()
            lock.lock()
            self.engine = engine
            lock.unlock()
            log.info("AudioLevelMeter started")
        } catch {
            log.error("Failed to start audio engine: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stop sampling. Idempotent.
    func stop() {
        lock.lock()
        let engine = self.engine
        self.engine = nil
        smoothedLevel = 0
        lock.unlock()

        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        log.info("AudioLevelMeter stopped")
    }

    /// Compute the RMS amplitude of an audio buffer and map it into
    /// a 0...1 visualization range.
    ///
    /// Raw RMS for normal speech sits around 0.05-0.3; we boost via a
    /// sqrt curve so quiet voices still register visually.
    static func rms(of buffer: AVAudioPCMBuffer) -> Float {
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
