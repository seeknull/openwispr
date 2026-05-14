import SwiftUI
import WhispCore

struct SettingsView: View {
    @ObservedObject var settings: WhispSettings
    @ObservedObject var permissions: PermissionsManager
    let onCheckPermissions: () -> Void

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 360)
        .padding()
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
