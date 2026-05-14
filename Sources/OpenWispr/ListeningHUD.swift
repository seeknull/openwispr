import AppKit
import QuartzCore

/// Tiny translucent pill that floats near the bottom of the screen while
/// OpenWispr is listening. Icon-only — a pulsing red record dot next to a
/// small waveform glyph. No text, no hotkey reminder (the menu-bar icon
/// tooltip carries that).
///
/// ## Design choices
///
/// - **Translucent**, not solid: `NSVisualEffectView` with the
///   `.hudWindow` material so it blends with whatever's behind it.
///   The red tint is at a low opacity so the pill never makes content
///   underneath unreadable.
/// - **Icon-only**: the previous label "Listening… Fn+Option to stop"
///   was both wide and noisy. Two glyphs convey the same state with
///   less visual footprint.
/// - **Bottom-center**: out of the way of menu bars, window chrome,
///   and active editing areas which tend to live near the top.
///
/// ## Why AppKit and not SwiftUI
///
/// An earlier SwiftUI implementation with `Circle().animation(...)`
/// inside an `NSHostingView` crashed the app on the second toggle when
/// SwiftUI's animation driver kept poking at a view whose host window
/// had been ordered out. Plain AppKit + Core Animation doesn't have
/// that hazard.
@MainActor
final class ListeningHUD {
    private var panel: NSPanel?

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
    }

    func hide() {
        if let pulser = panel?.contentView as? HUDContentView {
            pulser.stopPulsing()
        }
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Translucent capsule: pulsing red dot + waveform glyph.
@MainActor
private final class HUDContentView: NSView {
    private static let height: CGFloat = 26
    private static let dotDiameter: CGFloat = 7
    private static let leadingInset: CGFloat = 11
    private static let dotToIconGap: CGFloat = 7
    private static let iconSize: CGFloat = 13
    private static let trailingInset: CGFloat = 11

    private let dotLayer = CAShapeLayer()
    private let visualEffect = NSVisualEffectView()
    private let iconView = NSImageView()

    override var intrinsicContentSize: NSSize {
        let width = Self.leadingInset
            + Self.dotDiameter
            + Self.dotToIconGap
            + Self.iconSize
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
        setupIcon()
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

        // Very subtle red wash — just enough that the pill reads as
        // "this is the listening state". 12% so it stays translucent.
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
        layer?.addSublayer(dotLayer)
    }

    private func setupIcon() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let cfg = NSImage.SymbolConfiguration(pointSize: Self.iconSize, weight: .medium)
        iconView.image = NSImage(systemSymbolName: "waveform",
                                 accessibilityDescription: "Listening")?
            .withSymbolConfiguration(cfg)
        // Tint the symbol with the system label color so it adapts to
        // light/dark mode and reads well over the blur.
        iconView.contentTintColor = .labelColor
        addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: Self.leadingInset + Self.dotDiameter + Self.dotToIconGap
            ),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),
        ])
    }

    /// Smooth opacity pulse on the red dot.
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
