import AppKit
import QuartzCore

/// A small floating pill shown near the top of the screen while OpenWispr is
/// listening. Non-activating panel so the user's focused app stays focused
/// and our text injection actually goes to the right window.
///
/// ## Why AppKit and not SwiftUI
///
/// An earlier SwiftUI implementation with `Circle().animation(...)` inside
/// an `NSHostingView` crashed the app every time the HUD was torn down
/// mid-animation. The crash surfaced as
/// `_postWindowNeedsUpdateConstraints` throwing inside the display cycle —
/// SwiftUI's animation driver kept poking at a view whose host window had
/// already been ordered out.
///
/// Plain AppKit + Core Animation has no such issue: when the panel is
/// closed, the CALayer animations stop with it, no dangling SwiftUI
/// state to invalidate.
@MainActor
final class ListeningHUD {
    private var panel: NSPanel?

    func show() {
        guard panel == nil else { return }

        let size = NSSize(width: 220, height: 44)
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

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.maxY - size.height - 8
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

/// Pure AppKit + Core Animation pill. NSView with a CALayer background,
/// a CAShapeLayer dot, and an NSTextField label. No SwiftUI in the loop.
@MainActor
private final class HUDContentView: NSView {
    private let dotLayer = CAShapeLayer()
    private let label = NSTextField(labelWithString: "Listening… Fn+Option to stop")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupLayer()
        setupDot()
        setupLabel()
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    private func setupLayer() {
        guard let layer = layer else { return }
        layer.cornerRadius = bounds.height / 2
        layer.backgroundColor = NSColor.systemRed.withAlphaComponent(0.88).cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowOffset = CGSize(width: 0, height: -2)
        layer.shadowRadius = 8
    }

    private func setupDot() {
        let dotDiameter: CGFloat = 10
        let dotX: CGFloat = 16
        let dotY = (bounds.height - dotDiameter) / 2
        let dotRect = NSRect(x: dotX, y: dotY, width: dotDiameter, height: dotDiameter)
        dotLayer.path = CGPath(ellipseIn: dotRect, transform: nil)
        dotLayer.fillColor = NSColor.white.cgColor
        layer?.addSublayer(dotLayer)
    }

    private func setupLabel() {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 36),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// Smooth opacity pulse on the white dot. Cheap CA animation,
    /// stops cleanly when the layer is deallocated.
    func startPulsing() {
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1.0
        opacity.toValue = 0.4
        opacity.duration = 0.7
        opacity.autoreverses = true
        opacity.repeatCount = .infinity
        opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotLayer.add(opacity, forKey: "pulse")
    }

    func stopPulsing() {
        dotLayer.removeAllAnimations()
    }
}
