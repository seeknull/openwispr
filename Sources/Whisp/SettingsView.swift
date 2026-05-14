import SwiftUI
import WhispCore

struct SettingsView: View {
    @ObservedObject var settings: WhispSettings
    @ObservedObject var permissions: PermissionsManager
    let onCheckPermissions: () -> Void

    /// Polls the system permission state every two seconds while the
    /// Settings window is visible. macOS gives us no notification when a
    /// user toggles Whisp in System Settings, so polling is the only way
    /// to react to an external grant in near-real-time.
    private let pollTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 380)
        .padding()
        .onReceive(pollTimer) { _ in onCheckPermissions() }
    }

    private var generalTab: some View {
        Form {
            Picker("Insertion mode", selection: insertionBinding) {
                ForEach(InsertionMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            Text(settings.insertionMode.helpText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Show listening indicator", isOn: $settings.showHUD)

            HStack {
                Text("Hotkey")
                Spacer()
                Text(settings.hotkeyConfig.displayName)
                    .foregroundStyle(.secondary)
            }
            Text("Hotkey rebinding will land in a future release. Default: Fn + Option.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var insertionBinding: Binding<InsertionMode> {
        Binding(
            get: { settings.insertionMode },
            set: { settings.insertionMode = $0 }
        )
    }

    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if permissions.needsRestart {
                restartBanner
            }

            permissionRow(
                title: "Microphone",
                status: permissions.microphone,
                why: "Whisp captures audio from your microphone to transcribe what you say.",
                action: "Request"
            ) {
                permissions.requestMicrophone()
            }

            permissionRow(
                title: "Accessibility",
                status: permissions.accessibility,
                why: "Whisp posts paste / keystroke events to type the transcript into the focused app.",
                action: "Open Settings"
            ) {
                permissions.requestAccessibility()
            }

            permissionRow(
                title: "Input Monitoring",
                status: permissions.inputMonitoring,
                why: "Whisp watches for the Fn + Option hotkey to start and stop listening.",
                action: "Open Settings"
            ) {
                permissions.requestInputMonitoring()
            }

            Spacer()

            HStack {
                Spacer()
                Button("Re-check") {
                    onCheckPermissions()
                }
            }
        }
        .padding()
    }

    /// Shown whenever Accessibility or Input Monitoring is not observably
    /// granted. macOS caches both decisions per-process, so a grant the
    /// user has *actually* made may still look like `.notDetermined` to
    /// this running process — a relaunch is the only way to find out.
    /// We always show this when either is missing, regardless of who
    /// did what.
    private var restartBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(.tint)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text("Already granted in System Settings? Restart Whisp.")
                    .font(.headline)
                Text("macOS caches Accessibility and Input Monitoring decisions inside the running process. If you've toggled Whisp on but it still says \"Needed\" here, relaunching is what lets Whisp see the new grant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Restart Whisp") {
                permissions.restartWhisp()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.12))
        )
    }

    private func permissionRow(
        title: String,
        status: PermissionStatus,
        why: String,
        action: String,
        onTap: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                statusBadge(status)
                if status != .granted {
                    Button(action, action: onTap)
                }
            }
            Text(why).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func statusBadge(_ status: PermissionStatus) -> some View {
        switch status {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.green)
        case .denied:
            Label("Denied", systemImage: "xmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.red)
        case .notDetermined:
            Label("Needed", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.orange)
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(.tint)
            Text("Whisp").font(.title)
            Text("Open-source dictation for macOS, powered by Moonshine.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Link("github.com/your-org/whisp",
                 destination: URL(string: "https://github.com/your-org/whisp")!)
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
