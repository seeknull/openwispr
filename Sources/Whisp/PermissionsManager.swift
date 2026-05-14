import AVFoundation
import AppKit
import ApplicationServices
import Foundation
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
