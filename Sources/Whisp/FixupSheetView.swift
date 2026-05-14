import AppKit
import SwiftUI

/// Step-by-step onboarding shown when Whisp detects that its current
/// code-signature differs from the one the user previously granted TCC
/// against (i.e. ad-hoc rebuilt since the last successful grant). The
/// user must still remove the stale row and toggle the new one — macOS
/// doesn't let scripts do those bits — but everything around that is
/// automated.
struct FixupSheetView: View {
    @ObservedObject var permissions: PermissionsManager
    var onClose: () -> Void

    @State private var step: Step = .intro

    enum Step: Int { case intro, accessibility, inputMonitoring, done }

    var body: some View {
        VStack(spacing: 16) {
            header
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        // Fixed width AND height — without a height, SwiftUI lets the
        // hosting NSWindow renegotiate size every time `step` changes,
        // which AppKit's auto-layout machinery in macOS 26 considers
        // an exception-worthy constraint thrash and crashes the app.
        .frame(width: 540, height: 360)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Re-grant Whisp's permissions")
                    .font(.title3.weight(.semibold))
                Text("This build of Whisp has a new code signature, so your previous TCC grants no longer apply.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intro:
            intro
        case .accessibility:
            permissionStep(
                title: "Step 1 of 2 — Accessibility",
                description: "Whisp uses this to paste / type the transcript into your focused app.",
                permissionGranted: permissions.accessibility == .granted,
                openButton: {
                    permissions.openAccessibilityPane()
                }
            )
        case .inputMonitoring:
            permissionStep(
                title: "Step 2 of 2 — Input Monitoring",
                description: "Whisp uses this to watch for the Fn+Option hotkey.",
                permissionGranted: permissions.inputMonitoring == .granted,
                openButton: {
                    permissions.openInputMonitoringPane()
                }
            )
        case .done:
            done
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Whisp just cleared its old grants. Two short steps left:")
                .font(.body)
            stepHint(
                "1. Open the System Settings pane Whisp will jump you to.",
                detail: "If you see an old \"Whisp\" entry there, click it and press the `−` button to remove it."
            )
            stepHint(
                "2. Toggle Whisp on.",
                detail: "Whisp will detect the grant automatically (no need to come back here)."
            )
            Text("If you don't see a stale entry, you can skip step 1 — just toggle on.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }

    private func stepHint(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fontWeight(.medium)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.12)))
    }

    private func permissionStep(
        title: String,
        description: String,
        permissionGranted: Bool,
        openButton: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(description).font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Open System Settings", action: openButton)
                Spacer()
                if permissionGranted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Waiting…", systemImage: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("All set", systemImage: "checkmark.seal.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)
            Text("Whisp now has all the permissions it needs. Press **Restart Whisp** so the new grant takes effect.")
                .font(.callout)
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip", action: onClose)
            Spacer()
            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .intro:
            Button("Start") {
                step = .accessibility
                permissions.openAccessibilityPane()
            }
            .keyboardShortcut(.defaultAction)
        case .accessibility:
            Button(permissions.accessibility == .granted ? "Next" : "I'll do it later") {
                step = .inputMonitoring
                if permissions.inputMonitoring != .granted {
                    permissions.openInputMonitoringPane()
                }
            }
            .keyboardShortcut(.defaultAction)
        case .inputMonitoring:
            Button("Continue") {
                step = .done
            }
            .keyboardShortcut(.defaultAction)
            .disabled(permissions.inputMonitoring != .granted)
        case .done:
            Button("Restart Whisp") {
                permissions.restartWhisp()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
