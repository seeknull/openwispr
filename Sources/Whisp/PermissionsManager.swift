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
/// ## The "running process can't see the new grant" trap
///
/// Both `AXIsProcessTrusted()` and `CGEvent.tapCreate(listenOnly:)` cache
/// their permission decision inside the current process. macOS delivers the
/// **new** grant only to a freshly-launched process. So if you grant
/// Accessibility while Whisp is running, this class's `accessibility`
/// property keeps returning `.notDetermined` regardless of how many times
/// we re-poll — the API itself lies.
///
/// We can't fix that API, so the UX strategy is: any time Accessibility or
/// Input Monitoring is not `.granted`, surface a "Restart Whisp" button.
/// The honest message is "either you haven't granted, or you did and we
/// can't see it — relaunching fixes both."
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

    /// True whenever a system-level permission may have been granted but the
    /// running process can't observe it (because TCC caches per-process).
    /// We treat *any* non-granted state for Accessibility or Input Monitoring
    /// as "user might already have granted, restart to find out."
    var needsRestart: Bool {
        accessibility != .granted || inputMonitoring != .granted
    }

    /// Spawn `open -n` to launch a fresh copy of Whisp and exit the current
    /// process. The new instance picks up any TCC grants that landed while
    /// the old one was running.
    func restartWhisp() {
        let bundlePath = Bundle.main.bundleURL.path
        // `open -n` always launches a new instance, even if LaunchServices
        // thinks the app is "already running." We terminate ourselves after
        // a beat so the new launch isn't merged with the dying instance.
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
    /// permission flows through to the running process so this DOES update
    /// the live status — no restart needed.
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
    /// for the next launch.
    func requestAccessibility() {
        // `kAXTrustedCheckOptionPrompt` is declared as a mutable C global;
        // Swift 6 won't let us read through it directly. The string literal
        // is the documented key value.
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options: CFDictionary = [key: kCFBooleanTrue!] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSystemSettings(pane: "Privacy_Accessibility")
    }

    // MARK: - Input Monitoring (for CGEventTap)

    /// Probes by creating a `listenOnly` event tap. This is the only
    /// reliable signal for Input Monitoring in user code — Apple has no
    /// public TCC-query API for it.
    ///
    /// We deliberately do NOT cache this result. The user can flip the
    /// grant in System Settings at any moment and we want `refresh()` to
    /// pick it up next time the Settings tab is opened.
    private func inputMonitoringStatus() -> PermissionStatus {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, _, e, _ in Unmanaged.passUnretained(e) },
            userInfo: nil
        ) else {
            return .notDetermined
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        return .granted
    }

    func requestInputMonitoring() {
        // No direct API triggers this prompt; opening the pane and asking
        // the user to enable Whisp is the canonical flow.
        openSystemSettings(pane: "Privacy_ListenEvent")
    }

    // MARK: - Helpers

    private func openSystemSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
