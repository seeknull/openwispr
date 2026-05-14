import AppKit
import SwiftUI

/// A small floating pill shown near the top of the screen while Whisp is
/// listening. Non-activating panel so the user's focused app stays focused
/// and our text injection actually goes to the right window.
@MainActor
final class ListeningHUD {
    private var panel: NSPanel?

    func show() {
        guard panel == nil else { return }
        let view = HUDView()
        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
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
        panel.hasShadow = true
        panel.contentView = host

        // Center horizontally near the top of the active screen.
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = CGSize(width: 200, height: 44)
            panel.setFrame(
                NSRect(
                    x: frame.midX - size.width / 2,
                    y: frame.maxY - size.height - 8,
                    width: size.width,
                    height: size.height
                ),
                display: true
            )
        }

        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct HUDView: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .scaleEffect(pulse ? 1.25 : 1.0)
                .opacity(pulse ? 0.6 : 1.0)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            Text("Listening… Fn+Option to stop")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
        )
        .onAppear { pulse = true }
    }
}
