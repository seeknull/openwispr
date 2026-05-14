import AVFoundation
import AppKit
import ApplicationServices
import Foundation

/// Coordinates the three macOS permissions Whisp depends on. Each helper
/// either returns the current grant state without prompting, or actively
/// prompts when called. Onboarding asks in this order:
///
///   1. Microphone — needed for the mic transcriber.
///   2. Accessibility — needed to post synthetic input events.
///   3. Input Monitoring — needed for the CGEventTap that watches the hotkey.
///
/// ## Why we always nudge a restart after granting Accessibility / Input Monitoring
///
/// Both `AXIsProcessTrusted()` and `CGEvent.tapCreate(listenOnly:)` cache the
/// permission decision inside the current process. macOS only delivers the
/// **new** grant decision to a freshly-launched process. So if the user grants
/// Accessibility while Whisp is running, our "Re-check" button might *say*
/// it's granted but the underlying CGEvent APIs will still be denied.
///
/// `pendingRestartGrants` tracks which permissions the user has actively
/// gone to grant in System Settings. The UI uses that to flip the
/// "Open Settings" button into "Restart Whisp" once the user comes back.
enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
}

enum PermissionKind: String, CaseIterable {
    case microphone
    case accessibility
    case inputMonitoring
}

@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var microphone: PermissionStatus = .notDetermined
    @Published private(set) var accessibility: PermissionStatus = .notDetermined
    @Published private(set) var inputMonitoring: PermissionStatus = .notDetermined

    /// Permissions for which the user has clicked our "Open Settings" /
    /// "Request" buttons during this Whisp session. Once a permission is in
    /// this set, the UI shows a "Restart Whisp" prompt because the running
    /// process can't actually pick up the new grant.
    @Published private(set) var pendingRestartGrants: Set<PermissionKind> = []

    init() { refresh() }

    /// Re-query every permission. Cheap; safe to call from UI on demand.
    func refresh() {
        microphone = microphoneStatus()
        accessibility = accessibilityStatus()
        inputMonitoring = inputMonitoringStatus()
    }

    var allGranted: Bool {
        microphone == .granted && accessibility == .granted && inputMonitoring == .granted
    }

    var needsRestart: Bool {
        !pendingRestartGrants.isEmpty
    }

    /// Spawn `open -n` to launch a fresh copy of Whisp and exit the current
    /// process. The new instance picks up TCC grants that landed after we
    /// started.
    func restartWhisp() {
        guard let bundlePath = Bundle.main.bundleURL.path as String? else {
            NSApp.terminate(nil)
            return
        }
        // `open -n` always launches a new instance, even if one is "already
        // running" from LaunchServices's POV. We terminate ourselves after
        // a beat so LaunchServices doesn't see the new launch as a
        // re-activation.
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundlePath]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Microphone

    private func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// Prompts the user for mic access if not already determined. Mic
    /// permission *does* flow through to the running process so we do
    /// NOT mark a restart-required.
    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    // MARK: - Accessibility (for posting keyboard events)

    private func accessibilityStatus() -> PermissionStatus {
        AXIsProcessTrusted() ? .granted : .notDetermined
    }

    /// Triggers the system Accessibility prompt and opens System Settings.
    /// macOS will not flip the trust bit for the *running* process — only
    /// for the next launch — so we flag this permission as needing a
    /// restart.
    func requestAccessibility() {
        // `kAXTrustedCheckOptionPrompt` is declared as a mutable C global;
        // Swift 6 won't let us read through it directly. The string literal
        // is the documented key value.
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options: CFDictionary = [key: kCFBooleanTrue!] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSystemSettings(pane: "Privacy_Accessibility")
        pendingRestartGrants.insert(.accessibility)
    }

    // MARK: - Input Monitoring (for CGEventTap)

    /// Cached check result. Re-running `CGEvent.tapCreate` repeatedly is
    /// wasteful and macOS may rate-limit the underlying TCC check.
    private var cachedInputMonitoringStatus: PermissionStatus?

    private func inputMonitoringStatus() -> PermissionStatus {
        if let cached = cachedInputMonitoringStatus { return cached }
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let status: PermissionStatus
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, _, e, _ in Unmanaged.passUnretained(e) },
            userInfo: nil
        ) {
            CGEvent.tapEnable(tap: tap, enable: false)
            status = .granted
        } else {
            status = .notDetermined
        }
        cachedInputMonitoringStatus = status
        return status
    }

    func requestInputMonitoring() {
        // No direct API triggers this prompt; opening the pane and asking
        // the user to enable Whisp is the canonical flow.
        openSystemSettings(pane: "Privacy_ListenEvent")
        pendingRestartGrants.insert(.inputMonitoring)
    }

    // MARK: - Helpers

    private func openSystemSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
