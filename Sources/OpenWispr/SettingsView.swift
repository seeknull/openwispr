import SwiftUI
import OpenWisprCore

struct SettingsView: View {
    @ObservedObject var settings: OpenWisprSettings
    @ObservedObject var permissions: PermissionsManager
    let onCheckPermissions: () -> Void

    /// Auto-select the Permissions tab when something is missing — the
    /// most common reason to open Settings is to grant a permission, so
    /// landing on General first is annoying.
    @State private var selectedTab: Tab
    @State private var showHardResetConfirm: Bool = false

    enum Tab: Hashable { case general, permissions, about }

    init(
        settings: OpenWisprSettings,
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

    var body: some View {
        VStack(spacing: 0) {
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

            // Persistent footer: build info on every tab so you can
            // tell at a glance which build is running, especially
            // useful while iterating on dev builds.
            Divider()
            HStack {
                Text(AppVersion.summaryLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .frame(width: 540, height: 480)
        .padding()
        // Refresh only on tab change AND when the window becomes key
        // again (after the user came back from System Settings).
        // A 2-second poll timer was the trigger for a recurring AppKit
        // constraint-update crash on macOS 26 — `@Published` mutations
        // inside the host view at arbitrary times caused NSView's
        // updateConstraints cycle to throw. The user can hit Re-check
        // manually in the rare case that auto-refresh doesn't see a grant.
        .onChange(of: selectedTab) { new in
            if new == .permissions { onCheckPermissions() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            onCheckPermissions()
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
                    why: "Paste/type transcript into the focused app, and observe the Fn+Option hotkey.",
                    action: "Open Settings"
                ) {
                    permissions.requestAccessibility()
                }

                if !permissions.allGranted {
                    staleEntryHint
                }

                HStack {
                    Button("Re-check") {
                        onCheckPermissions()
                    }
                    Button(role: .destructive, action: { showHardResetConfirm = true }) {
                        Label("Hard Reset", systemImage: "exclamationmark.arrow.circlepath")
                    }
                    .help("Clear all TCC grants for OpenWispr and quit. Use when permissions are stuck.")
                    Spacer()
                    Button("Restart OpenWispr") {
                        permissions.restartOpenWispr()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!permissions.allGranted)
                }
                .padding(.top, 8)
            }
            .padding()
            .alert("Hard reset OpenWispr's permissions?", isPresented: $showHardResetConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Reset and Quit", role: .destructive) {
                    permissions.hardReset()
                }
            } message: {
                Text("OpenWispr will clear all of its TCC entries (Microphone, Accessibility), open System Settings → Privacy & Security, and quit. From there you can remove any stale \"OpenWispr\" rows that remain visible by clicking the row and pressing the − button, then relaunch OpenWispr from /Applications or your dev build for a clean grant flow.")
            }
        }
    }

    /// Yellow callout explaining the rebuild-stale-row trick. Only shown
    /// when something is not yet granted, since users in the steady state
    /// don't need to see it.
    private var staleEntryHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("OpenWispr not showing up in System Settings? Use the + button.", systemImage: "exclamationmark.bubble.fill")
                .font(.callout.weight(.medium))
            Text("macOS 26 sometimes blocks unsigned apps from auto-appearing in Privacy & Security. The canonical workaround:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 3) {
                Text("1.  Click **Open Settings** above. The System Settings pane opens.")
                Text("2.  Click the **+** button at the bottom of the list.")
                Text("3.  Navigate to **OpenWispr.app** (`Cmd+Shift+G` then paste the path below) and pick it.")
                Text("4.  Toggle OpenWispr **on**. OpenWispr will see the grant within ~2s.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Text("OpenWispr.app path:")
                    .font(.caption.weight(.medium))
                Text(Bundle.main.bundleURL.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Bundle.main.bundleURL.path, forType: .string)
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .help("Copy path")
            }
            .padding(.top, 4)
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
            Text("OpenWispr").font(.title)
            Text("Open-source dictation for macOS, powered by Moonshine.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Link("github.com/seeknull/openwispr",
                 destination: URL(string: "https://github.com/seeknull/openwispr")!)
                .font(.footnote)

            buildInfoBox
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// Detailed build metadata block on the About tab. Stamped at
    /// release-build time by scripts/build-release.sh.
    private var buildInfoBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            buildInfoRow("Version", "v\(AppVersion.version)")
            buildInfoRow("Build", AppVersion.buildNumber)
            buildInfoRow("Built", AppVersion.friendlyBuildDate)
            buildInfoRow("Commit", AppVersion.commitSHA)
        }
        .padding(12)
        .frame(maxWidth: 360)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.10)))
    }

    private func buildInfoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Spacer()
        }
    }
}
