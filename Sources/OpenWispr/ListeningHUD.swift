import AppKit
import QuartzCore

/// Tiny translucent pill that floats near the bottom of the screen while
/// OpenWispr is listening. Shows a pulsing red record dot + a 3-bar
/// equalizer that animates from live microphone input level.
///
/// ## Design choices
///
/// - **Translucent** `NSVisualEffectView` blur with a 12% red tint.
///   Never makes the content underneath unreadable.
/// - **3-bar visualizer**, not text: the bars move with the mic input
///   so the user can see at a glance that the microphone is actually
///   hearing them. Solves the "is it on?" doubt without copy.
/// - **Bottom-center placement**: out of the way of menu bars, window
///   chrome, and active editing areas which tend to live near the top.
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
        contentView.startPulsing()
        self.panel = panel
        self.contentView = contentView
    }

    func hide() {
        contentView?.stopPulsing()
        panel?.orderOut(nil)
        panel = nil
        contentView = nil
    }

    /// Update the bar visualizer with a fresh mic level (0...1). Safe
    /// to call at audio-tap rates; the view animates short, so frequent
    /// updates feel smooth without flooding the layer tree.
    func setLevel(_ level: Float) {
        contentView?.setLevel(level)
    }
}

/// Translucent capsule: pulsing red dot + 3-bar audio level visualizer.
@MainActor
private final class HUDContentView: NSView {
    private static let height: CGFloat = 26
    private static let dotDiameter: CGFloat = 7
    private static let leadingInset: CGFloat = 11
    private static let dotToBarsGap: CGFloat = 7
    private static let barWidth: CGFloat = 2.5
    private static let barSpacing: CGFloat = 2.5
    private static let barCount: Int = 3
    private static let trailingInset: CGFloat = 11
    private static let minBarHeight: CGFloat = 4
    private static let maxBarHeight: CGFloat = 16

    private let dotLayer = CAShapeLayer()
    private let visualEffect = NSVisualEffectView()
    private var barLayers: [CALayer] = []

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

        let tint = CALayer()
        tint.frame = bounds
        tint.backgroundColor = NSColor.systemRed.withAlphaComponent(0.12).cgColor
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
        // Add to the visualEffect's layer rather than self.layer —
        // visualEffect renders opaquely on top of the host view's
        // backing layer, so any sublayer of self.layer would be
        // hidden behind it.
        visualEffect.layer?.addSublayer(dotLayer)
    }

    private func setupBars() {
        let startX = Self.leadingInset + Self.dotDiameter + Self.dotToBarsGap
        for i in 0..<Self.barCount {
            let layer = CALayer()
            let x = startX + CGFloat(i) * (Self.barWidth + Self.barSpacing)
            let height = Self.minBarHeight
            let y = (bounds.height - height) / 2
            layer.frame = NSRect(x: x, y: y, width: Self.barWidth, height: height)
            layer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.85).cgColor
            layer.cornerRadius = Self.barWidth / 2
            // Same reason as the dot: add to the visualEffect layer so
            // we render *above* the blur, not underneath it.
            visualEffect.layer?.addSublayer(layer)
            barLayers.append(layer)
        }
    }

    /// Drive the bars from a 0...1 mic level. Each bar gets a slightly
    /// different scale + phase so the visualization looks like activity,
    /// not a single bar tripled.
    func setLevel(_ level: Float) {
        let l = max(0, min(1, CGFloat(level)))
        // Per-bar coefficients give a slight visual variation — the
        // center bar typically loudest, outer bars trail slightly.
        let coefficients: [CGFloat] = [0.80, 1.00, 0.70]
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        for (i, layer) in barLayers.enumerated() {
            let scaled = l * coefficients[i % coefficients.count]
            let h = Self.minBarHeight + (Self.maxBarHeight - Self.minBarHeight) * scaled
            var frame = layer.frame
            frame.size.height = h
            frame.origin.y = (bounds.height - h) / 2
            layer.frame = frame
        }
        CATransaction.commit()
    }

    /// Smooth opacity pulse on the red dot. Independent of the bars —
    /// the dot pulses on the listening cadence, the bars react to mic
    /// activity.
    func startPulsing() {
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1.0
        opacity.toValue = 0.35
        opacity.duration = 0.85
        opacity.autoreverses = true
        opacity.repeatCount = .infinity
        opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotLayer.add(opacity, forKey: "pulse")
    }

    func stopPulsing() {
        dotLayer.removeAllAnimations()
    }
}
