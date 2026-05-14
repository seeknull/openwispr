import SwiftUI
import WhispCore

struct SettingsView: View {
    @ObservedObject var settings: WhispSettings
    @ObservedObject var permissions: PermissionsManager
    let onCheckPermissions: () -> Void

    /// Auto-select the Permissions tab when something is missing — the
    /// most common reason to open Settings is to grant a permission, so
    /// landing on General first is annoying.
    @State private var selectedTab: Tab

    enum Tab: Hashable { case general, permissions, about }

    init(
        settings: WhispSettings,
        permissions: PermissionsManager,
        onCheckPermissions: @escaping () -> Void
    ) {
        self.settings = settings
        self.permissions = permissions
        self.onCheckPermissions = onCheckPermissions
        // Default landing tab based on grant status at construction.
        // Re-evaluated only when the view is rebuilt by SwiftUI.
        _selectedTab = State(initialValue: permissions.allGranted ? .general : .permissions)
    }

    /// Re-poll permissions every 2 seconds. macOS gives us no notification
    /// when the user toggles Whisp in System Settings; this is the only
    /// way to update the UI live.
    private let pollTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
                .tag(Tab.permissions)
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(Tab.about)
        }
        .frame(width: 540, height: 460)
        .padding()
        .onReceive(pollTimer) { _ in onCheckPermissions() }
        .onChange(of: selectedTab) { new in
            if new == .permissions { onCheckPermissions() }
        }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                permissionRow(
                    title: "Microphone",
                    status: permissions.microphone,
                    why: "Capture audio to transcribe.",
                    action: "Request"
                ) {
                    permissions.requestMicrophone()
                }

                permissionRow(
                    title: "Accessibility",
                    status: permissions.accessibility,
                    why: "Paste or type the transcript into the focused app.",
                    action: "Open Settings"
                ) {
                    permissions.requestAccessibility()
                }

                permissionRow(
                    title: "Input Monitoring",
                    status: permissions.inputMonitoring,
                    why: "Watch for the Fn + Option hotkey.",
                    action: "Open Settings"
                ) {
                    permissions.requestInputMonitoring()
                }

                if !permissions.allGranted {
                    staleEntryHint
                }

                HStack {
                    Button("Re-check") {
                        onCheckPermissions()
                    }
                    Spacer()
                    Button("Restart Whisp") {
                        permissions.restartWhisp()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!permissions.allGranted)
                }
                .padding(.top, 8)
            }
            .padding()
        }
    }

    /// Yellow callout explaining the rebuild-stale-row trick. Only shown
    /// when something is not yet granted, since users in the steady state
    /// don't need to see it.
    private var staleEntryHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Whisp shows up in System Settings but the toggle won't stick?", systemImage: "exclamationmark.bubble")
                .font(.callout.weight(.medium))
            Text("Find the existing \"Whisp\" row in the System Settings pane, select it, and click the **−** button to remove it. Then come back here and click **Open Settings** again — that adds a fresh entry tied to the current build's signature.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.15)))
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
