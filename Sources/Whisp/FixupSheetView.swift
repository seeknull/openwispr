import AppKit
import SwiftUI

/// Single-pane onboarding shown when Whisp's permissions are incomplete
/// (first launch, or rebuilt app with stale TCC entries). Shows all three
/// permissions in one view with live status; the user grants them in any
/// order, the view auto-detects each one as it lands, and the "Restart
/// Whisp" button enables only when everything is green.
///
/// Why no step-by-step wizard: each permission lives in a different
/// System Settings pane, and users frequently bounce between them out
/// of order. A flat list also means the window never has to re-render
/// after a grant — which used to crash the app under macOS 26's
/// constraint system (see commit log).
struct FixupSheetView: View {
    @ObservedObject var permissions: PermissionsManager
    var onClose: () -> Void

    /// Re-poll system permissions while this view is visible. macOS gives
    /// no notification when the user toggles Whisp on in System Settings,
    /// so polling is the only way to react in near-real-time.
    private let pollTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            VStack(spacing: 12) {
                permissionRow(
                    title: "Microphone",
                    description: "Capture audio to transcribe.",
                    status: permissions.microphone,
                    actionTitle: "Request"
                ) {
                    permissions.requestMicrophone()
                }

                permissionRow(
                    title: "Accessibility",
                    description: "Paste or type the transcript into the focused app.",
                    status: permissions.accessibility,
                    actionTitle: "Open Settings"
                ) {
                    permissions.requestAccessibility()
                }

                permissionRow(
                    title: "Input Monitoring",
                    description: "Watch for the Fn + Option hotkey.",
                    status: permissions.inputMonitoring,
                    actionTitle: "Open Settings"
                ) {
                    permissions.requestInputMonitoring()
                }
            }

            staleEntryHint

            Spacer(minLength: 0)

            footer
        }
        .padding(24)
        // Fixed width AND height so SwiftUI never tries to renegotiate
        // the window size mid-update — that triggers an AppKit constraint
        // exception under macOS 26 and crashes the app.
        .frame(width: 540, height: 460)
        .onReceive(pollTimer) { _ in permissions.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Whisp needs these permissions to work")
                    .font(.title3.weight(.semibold))
                Text("Grant each one below. Whisp detects every grant automatically — you can take them in any order, and you don't need to come back here between steps.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    // MARK: - Rows

    private func permissionRow(
        title: String,
        description: String,
        status: PermissionStatus,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            statusIcon(status)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if status == .granted {
                Text("Granted")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button(actionTitle, action: action)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(status == .granted
                      ? Color.green.opacity(0.10)
                      : Color.gray.opacity(0.10))
        )
    }

    @ViewBuilder
    private func statusIcon(_ status: PermissionStatus) -> some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.large)
        case .denied:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .imageScale(.large)
        case .notDetermined:
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
                .imageScale(.large)
        }
    }

    // MARK: - Stale entry hint

    private var staleEntryHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Don't see Whisp in System Settings, or it's there but still won't grant?")
                .font(.caption.weight(.medium))
            Text("Find any existing \"Whisp\" row in the System Settings pane and click the **−** button to remove it, then come back here and click **Open Settings** again to add a fresh entry.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.yellow.opacity(0.12)))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Close", action: onClose)
            Spacer()
            Button("Restart Whisp") {
                permissions.restartWhisp()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!permissions.allGranted)
        }
    }
}
