import AppKit
import QuartzCore

/// Tiny translucent pill that floats near the bottom of the screen while
/// OpenWispr is listening. Shows a pulsing red record dot + 3 small bars
/// that move with the live microphone level.
///
/// ## Design choices
///
/// - **Translucent** `NSVisualEffectView` blur with a subtle red tint.
///   Matches macOS system HUD style.
/// - **Compact**: ~58×24pt. The 132pt-wide "real waveform" design felt
///   too big for an always-on overlay; this is back to indicator-sized.
/// - **Pulsing red dot** carries the "listening on" signal; the bars
///   carry the "mic is hearing you right now" signal. Two roles, two
///   tiny visuals, no competition.
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
                y: frame.minY + 48
            ))
        }

        panel.orderFrontRegardless()
        contentView.startAnimations()
        self.panel = panel
        self.contentView = contentView
    }

    func hide() {
        contentView?.stopAnimations()
        panel?.orderOut(nil)
        panel = nil
        contentView = nil
    }

    /// Update the bar visualizer with a fresh mic level (0...1).
    func setLevel(_ level: Float) {
        contentView?.setLevel(level)
    }
}

/// Translucent capsule: pulsing red dot + 3-bar audio level visualizer.
@MainActor
private final class HUDContentView: NSView {
    private static let height: CGFloat = 24
    private static let dotDiameter: CGFloat = 7
    private static let leadingInset: CGFloat = 10
    private static let dotToBarsGap: CGFloat = 7
    private static let barWidth: CGFloat = 2.5
    private static let barSpacing: CGFloat = 2.5
    private static let barCount: Int = 3
    private static let trailingInset: CGFloat = 10
    private static let minBarHeight: CGFloat = 3
    private static let maxBarHeight: CGFloat = 14

    private let dotLayer = CAShapeLayer()
    private let visualEffect = NSVisualEffectView()
    private var barLayers: [CALayer] = []

    // Per-bar amplitude weights and phase offsets so the bars have a
    // wave-like character rather than moving in perfect lockstep.
    private static let amplitudeWeights: [CGFloat] = [0.78, 1.00, 0.70]
    private static let phaseOffsets: [CGFloat] = [0.0, 0.4, 0.8]

    // Idle 24Hz timer so bars wobble gently even with no audio level.
    private var idleTimer: Timer?
    private var idlePhase: CGFloat = 0
    private var lastInputLevel: CGFloat = 0
    private var lastInputAt: Date = .distantPast

    override var intrinsicContentSize: NSSize {
        let barsBlockWidth = CGFloat(Self.barCount) * Self.barWidth
            + CGFloat(Self.barCount - 1) * Self.barSpacing
        let width = Self.leadingInset
            + Self.dotDiameter
            + Self.dotToBarsGap
            + barsBlockWidth
            + Self.trailingInset
        return NSSize(width: width, height: Self.height)
    }

    init() {
        super.init(frame: NSRect(origin: .zero, size: NSSize(width: 60, height: Self.height)))
        let computed = intrinsicContentSize
        frame = NSRect(origin: .zero, size: computed)
        wantsLayer = true
        setupBlur()
        setupDot()
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
        visualEffect.layer?.cornerRadius = bounds.height / 2
        visualEffect.layer?.masksToBounds = true
        addSubview(visualEffect)

        // Very subtle red wash so the pill reads as "listening".
        let tint = CALayer()
        tint.frame = bounds
        tint.backgroundColor = NSColor.systemRed.withAlphaComponent(0.10).cgColor
        tint.cornerRadius = bounds.height / 2
        tint.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        visualEffect.layer?.addSublayer(tint)
    }

    private func setupDot() {
        let dotY = (bounds.height - Self.dotDiameter) / 2
        let dotRect = NSRect(
            x: Self.leadingInset,
            y: dotY,
            width: Self.dotDiameter,
            height: Self.dotDiameter
        )
        dotLayer.path = CGPath(ellipseIn: dotRect, transform: nil)
        dotLayer.fillColor = NSColor.systemRed.cgColor
        // Render above the blur, not under it.
        visualEffect.layer?.addSublayer(dotLayer)
    }

    private func setupBars() {
        let startX = Self.leadingInset + Self.dotDiameter + Self.dotToBarsGap
        for i in 0..<Self.barCount {
            let layer = CALayer()
            let x = startX + CGFloat(i) * (Self.barWidth + Self.barSpacing)
            let h = Self.minBarHeight
            let y = (bounds.height - h) / 2
            layer.frame = NSRect(x: x, y: y, width: Self.barWidth, height: h)
            layer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.85).cgColor
            layer.cornerRadius = Self.barWidth / 2
            visualEffect.layer?.addSublayer(layer)
            barLayers.append(layer)
        }
    }

    func setLevel(_ level: Float) {
        let clamped = max(0, min(1, CGFloat(level)))
        lastInputLevel = clamped
        lastInputAt = Date()
        renderBars(baseLevel: clamped)
    }

    /// Start the red-dot pulse + the idle bar wobble loop.
    func startAnimations() {
        stopAnimations()

        // Dot pulse: independent of bars; signals "listening on".
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.35
        pulse.duration = 0.85
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotLayer.add(pulse, forKey: "pulse")

        // Idle bar wobble: uses the most-recent real input level if it
        // arrived in the last 200ms, otherwise a 0.05 floor so the bars
        // still have some life when the mic is quiet.
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let recent = Date().timeIntervalSince(self.lastInputAt) < 0.20
                let base: CGFloat = recent ? self.lastInputLevel : 0.05
                self.idlePhase += 0.20
                self.renderBars(baseLevel: base)
            }
        }
    }

    func stopAnimations() {
        dotLayer.removeAllAnimations()
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func renderBars(baseLevel: CGFloat) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.09)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(name: .easeOut)
        )

        for (i, layer) in barLayers.enumerated() {
            let weight = Self.amplitudeWeights[i % Self.amplitudeWeights.count]
            let phase = Self.phaseOffsets[i % Self.phaseOffsets.count]
            // Sinusoidal modulation scaled with the base level so it's
            // tiny at silence and pronounced at peak.
            let modulation = sin(idlePhase + phase) * 0.30 * baseLevel
            let scaled = max(0, min(1, baseLevel * weight + modulation))
            let h = Self.minBarHeight + (Self.maxBarHeight - Self.minBarHeight) * scaled
            var frame = layer.frame
            frame.size.height = h
            frame.origin.y = (bounds.height - h) / 2
            layer.frame = frame
        }
        CATransaction.commit()
    }
}
