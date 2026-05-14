import AVFoundation
import AppKit
import ApplicationServices
import Foundation
import IOKit.hid
import OSLog

/// Coordinates the three macOS permissions Whisp depends on. Each helper
/// either returns the current grant state without prompting, or actively
/// prompts when called. Onboarding asks in this order:
///
///   1. Microphone — needed for the mic transcriber.
///   2. Accessibility — needed to post synthetic input events.
///   3. Input Monitoring — needed for the CGEventTap that watches the hotkey.
///
/// ## The TCC mismatch trap
///
/// Two distinct problems make permissions feel broken:
///
/// 1. **Per-process caching.** `AXIsProcessTrusted()` and
///    `CGEvent.tapCreate(listenOnly:)` cache their decision inside the
///    current process. A grant the user makes while Whisp is running
///    isn't visible until Whisp restarts.
///
/// 2. **Stale TCC entries after rebuild.** TCC keys grants by the bundle
///    id + code-signing requirement (CDHash). Ad-hoc rebuilds produce a
///    different CDHash, so the System Settings row still shows "Whisp"
///    but the underlying decision-check doesn't match. Toggling won't
///    fix it; the row has to be removed with the `−` button and re-added.
///
/// `PermissionsManager` detects (2) by persisting the CDHash present at
/// the moment of the last successful grant and comparing on every launch.
/// When they mismatch, `signatureChangedSinceLastGrant == true` and the
/// UI shows a stronger "Reset grants" affordance.
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
    private let log = Logger(subsystem: "ai.whisp.app", category: "PermissionsManager")

    @Published private(set) var microphone: PermissionStatus = .notDetermined
    @Published private(set) var accessibility: PermissionStatus = .notDetermined
    @Published private(set) var inputMonitoring: PermissionStatus = .notDetermined

    /// Set true on launch if the binary's CDHash differs from the one
    /// stored last time Whisp observed all permissions as granted. Drives
    /// the "your previous grants probably won't match this build" UX.
    @Published private(set) var signatureChangedSinceLastGrant: Bool = false

    init() {
        detectSignatureMismatch()
        refresh()
    }

    /// Re-query every permission. Cheap; safe to call from UI on demand.
    /// Also persists the current signature any time we observe a fully
    /// granted state, so the next launch can detect drift.
    func refresh() {
        microphone = microphoneStatus()
        accessibility = accessibilityStatus()
        inputMonitoring = inputMonitoringStatus()

        if allGranted, let cd = currentCDHash {
            // We're in a good state — remember this signature for next time.
            UserDefaults.standard.set(cd, forKey: lastGrantedCDHashKey)
            signatureChangedSinceLastGrant = false
        }
    }

    var allGranted: Bool {
        microphone == .granted && accessibility == .granted && inputMonitoring == .granted
    }

    /// True whenever a system-level permission may have been granted but the
    /// running process can't observe it (because TCC caches per-process).
    var needsRestart: Bool {
        accessibility != .granted || inputMonitoring != .granted
    }

    /// Reset Accessibility + Input Monitoring TCC entries for this bundle
    /// via `tccutil`, open System Settings to the Accessibility pane, and
    /// post a notification. Returns true if at least one reset succeeded.
    ///
    /// The user still has to manually remove the stale row and toggle on
    /// — macOS does not allow scripts to perform those actions. But we
    /// can do everything *up to* that point.
    @discardableResult
    func runAutoFixup() -> Bool {
        log.info("Running auto-fixup: tccutil reset Accessibility / ListenEvent for \(Bundle.main.bundleIdentifier ?? "?", privacy: .public)")
        let bundleID = Bundle.main.bundleIdentifier ?? "ai.whisp.app"
        var anySuccess = false
        for service in ["Accessibility", "ListenEvent"] {
            if runTccutil(service: service, bundle: bundleID) {
                anySuccess = true
            }
        }
        // Drop the stored CDHash so we don't keep showing the
        // "signature changed" banner after the user has gone through fixup.
        UserDefaults.standard.removeObject(forKey: lastGrantedCDHashKey)
        signatureChangedSinceLastGrant = false
        return anySuccess
    }

    /// Nuclear reset for when TCC has gotten into a confused state with
    /// stale rows in System Settings. We can:
    ///   1. `tccutil reset` every Whisp-relevant service.
    ///   2. Drop our own stored CDHash bookkeeping.
    ///   3. Quit Whisp so the next launch comes up with zero state.
    ///
    /// We CANNOT click the `−` button in System Settings for the user —
    /// macOS forbids any app from doing that. After the reset + quit,
    /// the user manually removes any stale rows that remain visible.
    /// Opens System Settings → Privacy & Security so they're a click
    /// away from doing so.
    func hardReset() {
        log.warning("Hard reset: clearing all TCC grants for ai.whisp.app")
        let bundleID = Bundle.main.bundleIdentifier ?? "ai.whisp.app"
        for service in ["Microphone", "Accessibility", "ListenEvent", "PostEvent"] {
            _ = runTccutil(service: service, bundle: bundleID)
        }
        UserDefaults.standard.removeObject(forKey: lastGrantedCDHashKey)
        UserDefaults.standard.synchronize()
        // Open the parent Privacy & Security pane so the user can sweep
        // the three sub-panes (Microphone, Accessibility, Input Monitoring)
        // and click `−` on any leftover Whisp rows.
        openSystemSettings(pane: "Privacy")
        // Quit after a moment so the user's last action (the open) gets
        // a chance to fire before the process exits.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
            NSApp.terminate(nil)
        }
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

    /// `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` is the canonical
    /// TCC-query for Input Monitoring. The earlier listen-only-tap probe
    /// was wrong: `.listenOnly` taps have a different (lower) privacy
    /// class than the full Input Monitoring grant, so the probe always
    /// returned `.granted` even when Whisp wasn't in the Input Monitoring
    /// list at all — leading the UI to claim everything was fine while
    /// the actual hotkey tap was silently rejected.
    private func inputMonitoringStatus() -> PermissionStatus {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied:  return .denied
        case kIOHIDAccessTypeUnknown: return .notDetermined
        default:                       return .notDetermined
        }
    }

    /// Trigger the system prompt for Input Monitoring. This is the call
    /// that actually adds Whisp to the **Privacy & Security → Input
    /// Monitoring** list in System Settings. Without it, the user can't
    /// flip a toggle for Whisp because there's no row to flip.
    ///
    /// macOS shows the prompt once per app per session; subsequent calls
    /// are no-ops. We follow it by opening the pane so the user can
    /// toggle from there if they dismissed the prompt.
    func requestInputMonitoring() {
        ensureInputMonitoringIsRegistered()
        openSystemSettings(pane: "Privacy_ListenEvent")
    }

    /// Trigger `IOHIDRequestAccess` once so Whisp appears in the Input
    /// Monitoring list in System Settings. Without this call, Whisp is
    /// invisible to the user — there's no row for them to toggle on.
    /// Safe to call on every launch: the underlying API is a no-op if
    /// the request has already been made for this binary.
    func ensureInputMonitoringIsRegistered() {
        // The return value is irrelevant for our purposes — even a
        // "denied" response means Whisp now appears in the System Settings
        // list, where the user can re-enable it.
        let _: Bool = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refresh()
    }

    // MARK: - Open System Settings panes

    func openAccessibilityPane() {
        openSystemSettings(pane: "Privacy_Accessibility")
    }

    func openInputMonitoringPane() {
        openSystemSettings(pane: "Privacy_ListenEvent")
    }

    // MARK: - Signature tracking

    private let lastGrantedCDHashKey = "lastGrantedCDHash"

    /// Reads the CDHash of the currently-running bundle by shelling out
    /// to `codesign -d -v`. Returns nil if the binary isn't signed at all.
    private var currentCDHash: String? {
        let pipe = Pipe()
        let task = Process()
        task.launchPath = "/usr/bin/codesign"
        task.arguments = ["-dvvv", Bundle.main.bundleURL.path]
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8) else {
            return nil
        }
        for line in output.split(separator: "\n") {
            if line.hasPrefix("CDHash=") {
                return String(line.dropFirst("CDHash=".count))
            }
        }
        return nil
    }

    private func detectSignatureMismatch() {
        guard let cd = currentCDHash else { return }
        let stored = UserDefaults.standard.string(forKey: lastGrantedCDHashKey)
        if let stored, stored != cd {
            log.info("CDHash changed since last grant: was \(stored, privacy: .public), now \(cd, privacy: .public). Prior TCC entry may be stale.")
            signatureChangedSinceLastGrant = true
        }
    }

    // MARK: - Subprocess plumbing

    /// `/usr/bin/tccutil reset <service> <bundle-id>`. Returns true on
    /// exit code 0.
    private func runTccutil(service: String, bundle: String) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", service, bundle]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return false
        }
        return task.terminationStatus == 0
    }

    // MARK: - Helpers

    private func openSystemSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
