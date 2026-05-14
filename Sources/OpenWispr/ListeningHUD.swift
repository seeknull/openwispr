import AppKit
import QuartzCore

/// Small translucent pill that floats near the bottom of the screen while
/// OpenWispr is listening. Renders a 9-bar live waveform driven by the
/// microphone level.
///
/// ## Design choices
///
/// - **Single unified visual**: just an animated waveform. No dot, no
///   label, no extra glyphs competing for the small canvas.
/// - **Clean blur**: `NSVisualEffectView` with `.hudWindow` material,
///   no red wash. Matches macOS system HUDs (volume, brightness) which
///   stay neutral and let the content carry meaning.
/// - **Red bars**: the listening = red signal is preserved via the
///   bar colour. Cleaner than tinting the whole pill.
/// - **Staggered phases**: each bar reacts to the same mic level with a
///   small phase offset so the wave looks alive (like a real waveform),
///   not nine identical bars in sync.
/// - **Bottom-center**: out of the way of menu bars and editor chrome.
///
/// ## Why AppKit and not SwiftUI
///
/// An earlier SwiftUI implementation crashed the app on the second
/// toggle when SwiftUI's animation driver kept poking at a view whose
/// host window had been ordered out. Plain AppKit + Core Animation
/// has no such hazard.
@MainActor
final class ListeningHUD {
    private var panel: NSPanel?
    private var contentView: HUDContentView?

    func show() {
        guard panel == nil else { return }

        let contentView = HUDContentView()
        let size = contentView.intrinsicContentSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = contentView

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + 56
            ))
        }

        panel.orderFrontRegardless()
        contentView.startIdleAnimation()
        self.panel = panel
        self.contentView = contentView
    }

    func hide() {
        contentView?.stopAnimation()
        panel?.orderOut(nil)
        panel = nil
        contentView = nil
    }

    /// Update the bar visualizer with a fresh mic level (0...1). Safe
    /// to call at audio-tap rates.
    func setLevel(_ level: Float) {
        contentView?.setLevel(level)
    }
}

/// Translucent capsule with a live waveform of 9 rounded vertical bars.
/// Each bar reacts to the same input level with a slight phase offset
/// so the visualization looks like an animated waveform rather than 9
/// identical bars.
@MainActor
private final class HUDContentView: NSView {
    // Pill geometry — chosen to feel proportional, not cramped.
    private static let width: CGFloat = 132
    private static let height: CGFloat = 34
    private static let cornerRadius: CGFloat = 17

    // Bar geometry.
    private static let barCount: Int = 9
    private static let barWidth: CGFloat = 3
    private static let barSpacing: CGFloat = 4
    private static let minBarHeight: CGFloat = 4
    private static let maxBarHeight: CGFloat = 22

    private let visualEffect = NSVisualEffectView()
    private var barLayers: [CALayer] = []

    // Per-bar phase offsets (radians) so the wave isn't uniform. Tuned
    // by eye — symmetric around the center bar, edges slightly behind.
    private static let phaseOffsets: [CGFloat] = [
        0.00, 0.18, 0.36, 0.54, 0.72, 0.54, 0.36, 0.18, 0.00
    ]

    // Per-bar amplitude weights — center bar tallest, fading to edges,
    // so the waveform has a natural "speech" silhouette.
    private static let amplitudeWeights: [CGFloat] = [
        0.55, 0.72, 0.88, 0.96, 1.00, 0.96, 0.88, 0.72, 0.55
    ]

    // Idle animation: a gentle sine wobble so the HUD shows it's "alive"
    // even before any audio arrives.
    private var idleTimer: Timer?
    private var idlePhase: CGFloat = 0
    private var lastInputLevel: CGFloat = 0
    private var lastInputAt: Date = .distantPast

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.width, height: Self.height)
    }

    init() {
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: Self.width, height: Self.height)))
        wantsLayer = true
        setupBlur()
        setupBars()
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    private func setupBlur() {
        visualEffect.frame = bounds
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = Self.cornerRadius
        visualEffect.layer?.masksToBounds = true
        addSubview(visualEffect)
    }

    private func setupBars() {
        let barsBlockWidth = CGFloat(Self.barCount) * Self.barWidth
            + CGFloat(Self.barCount - 1) * Self.barSpacing
        let startX = (Self.width - barsBlockWidth) / 2

        for i in 0..<Self.barCount {
            let layer = CALayer()
            let x = startX + CGFloat(i) * (Self.barWidth + Self.barSpacing)
            let h = Self.minBarHeight
            let y = (Self.height - h) / 2
            layer.frame = NSRect(x: x, y: y, width: Self.barWidth, height: h)
            layer.backgroundColor = NSColor.systemRed.cgColor
            layer.cornerRadius = Self.barWidth / 2
            // Render above the blur, not under it.
            visualEffect.layer?.addSublayer(layer)
            barLayers.append(layer)
        }
    }

    /// Drive the bars from a 0...1 mic level.
    func setLevel(_ level: Float) {
        let clamped = max(0, min(1, CGFloat(level)))
        lastInputLevel = clamped
        lastInputAt = Date()
        renderBars(baseLevel: clamped)
    }

    /// Start a low-rate idle animation so the HUD has movement even
    /// when the mic is quiet (or no audio is arriving yet). Cancels
    /// itself as soon as real input starts flowing.
    func startIdleAnimation() {
        stopAnimation()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Use the most-recent real input level if it arrived in
                // the last 200ms; otherwise fall back to a gentle
                // 0.05 floor with a sine wobble.
                let now = Date()
                let recent = now.timeIntervalSince(self.lastInputAt) < 0.20
                let base: CGFloat = recent ? self.lastInputLevel : 0.05
                self.idlePhase += 0.18
                self.renderBars(baseLevel: base)
            }
        }
    }

    func stopAnimation() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    /// Recompute every bar's height from a base level + per-bar weights
    /// and the rolling idle phase. Wrapped in a CATransaction so all 9
    /// bars animate as one frame.
    private func renderBars(baseLevel: CGFloat) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.10)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(name: .easeOut)
        )

        for (i, layer) in barLayers.enumerated() {
            let weight = Self.amplitudeWeights[i % Self.amplitudeWeights.count]
            let phase = Self.phaseOffsets[i % Self.phaseOffsets.count]
            // Sinusoidal modulation on top of the base level so each
            // bar has a slightly different live shape. Modulation
            // amplitude scales with the base level — at silence the
            // wobble is tiny, at full volume it's pronounced.
            let modulation = sin(idlePhase + phase) * 0.25 * baseLevel
            let scaled = max(0, min(1, baseLevel * weight + modulation))
            let h = Self.minBarHeight + (Self.maxBarHeight - Self.minBarHeight) * scaled
            var frame = layer.frame
            frame.size.height = h
            frame.origin.y = (Self.height - h) / 2
            layer.frame = frame
        }
        CATransaction.commit()
    }
}
