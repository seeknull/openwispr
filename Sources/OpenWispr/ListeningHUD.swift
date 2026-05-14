import AppKit
import QuartzCore

/// Small translucent pill that floats near the bottom of the screen while
/// OpenWispr is listening. Non-activating panel so the user's focused app
/// stays focused and our text injection goes to the right window.
///
/// ## Design choices
///
/// - **Translucent**, not solid: uses `NSVisualEffectView` with the
///   `.hudWindow` material so it blends with whatever's behind it.
///   Matches the visual language of macOS system HUDs (volume overlay,
///   etc.) and never makes the underlying content unreadable.
/// - **Compact**: ~170×30. Wide enough to fit the label, no padding-for-
///   padding's-sake. The previous 220×44 pill was clipping over text in
///   editors / browsers near the top of the screen.
/// - **Bottom-center placement**: out of the way of menu bars, window
///   chrome, and active editing areas which tend to live near the top.
///
/// ## Why AppKit and not SwiftUI
///
/// An earlier SwiftUI implementation with `Circle().animation(...)` inside
/// an `NSHostingView` crashed the app on the second toggle. SwiftUI's
/// animation driver kept poking at a view whose host window had been
/// ordered out, surfacing as `_postWindowNeedsUpdateConstraints`
/// throwing. Plain AppKit + Core Animation doesn't have that hazard.
@MainActor
final class ListeningHUD {
    private var panel: NSPanel?

    func show() {
        guard panel == nil else { return }

        let size = NSSize(width: 170, height: 30)
        let contentView = HUDContentView(frame: NSRect(origin: .zero, size: size))

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

        // Bottom-center of the active screen, with a generous gap from the
        // Dock area. Top of the screen tends to be busy (menu bar, editor
        // tabs, browser address bars) so we steer clear.
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

/// Translucent pill with a subtle red record dot and a tight label.
/// Built on `NSVisualEffectView` so it picks up the system's blur and
/// vibrancy automatically.
@MainActor
private final class HUDContentView: NSView {
    private let dotLayer = CAShapeLayer()
    private let visualEffect = NSVisualEffectView()
    private let label = NSTextField(labelWithString: "Listening… Fn+Option to stop")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupBlur()
        setupDot()
        setupLabel()
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

        // Subtle red wash on top of the blur so the pill reads as
        // "listening" without overwhelming the background.
        let tint = CALayer()
        tint.frame = bounds
        tint.backgroundColor = NSColor.systemRed.withAlphaComponent(0.22).cgColor
        tint.cornerRadius = bounds.height / 2
        tint.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        visualEffect.layer?.addSublayer(tint)
    }

    private func setupDot() {
        let dotDiameter: CGFloat = 7
        let dotX: CGFloat = 12
        let dotY = (bounds.height - dotDiameter) / 2
        let dotRect = NSRect(x: dotX, y: dotY, width: dotDiameter, height: dotDiameter)
        dotLayer.path = CGPath(ellipseIn: dotRect, transform: nil)
        dotLayer.fillColor = NSColor.systemRed.cgColor
        // Sit above the visualEffect's layers
        layer?.addSublayer(dotLayer)
    }

    private func setupLabel() {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        // Use the system label color so it adapts to light/dark mode and
        // sits well against the blurred background.
        label.textColor = .labelColor
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 27),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
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
