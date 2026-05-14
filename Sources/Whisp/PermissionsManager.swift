import AVFoundation
import AppKit
import ApplicationServices
import Foundation
import OSLog

/// Coordinates the two macOS permissions Whisp actually needs:
///
///   1. **Microphone** — needed for the mic transcriber.
///   2. **Accessibility** — needed to post synthetic input events AND for
///      `NSEvent.addGlobalMonitorForEvents` to deliver our hotkey.
///
/// We deliberately do NOT request Input Monitoring anymore. The previous
/// CGEventTap-based hotkey required it, but macOS 26 silently denies TCC
/// requests for Input Monitoring from ad-hoc apps (verified via tccd
/// log). The NSEvent-based HotkeyMonitor only needs Accessibility, which
/// macOS 26 does grant via the standard prompt.
///
/// ## Why Accessibility doesn't have the same silent-deny problem
///
/// `AXIsProcessTrustedWithOptions(prompt: true)` triggers System Settings
/// to open and adds Whisp to the Accessibility list — even for ad-hoc
/// apps. We've confirmed this works in practice. The path to grant is:
///   1. Click "Open Settings" in Whisp's Settings → Permissions tab.
///   2. Toggle Whisp on in System Settings → Accessibility.
///   3. Restart Whisp (the running process caches the denied answer).
enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
}

enum PermissionKind: String, CaseIterable {
    case microphone
    case accessibility
}

@MainActor
final class PermissionsManager: ObservableObject {
    private let log = Logger(subsystem: "ai.whisp.dev", category: "PermissionsManager")

    @Published private(set) var microphone: PermissionStatus = .notDetermined
    @Published private(set) var accessibility: PermissionStatus = .notDetermined

    /// Set true on launch if the binary's CDHash differs from the one
    /// stored last time Whisp observed all permissions as granted.
    @Published private(set) var signatureChangedSinceLastGrant: Bool = false

    init() {
        detectSignatureMismatch()
        refresh()
    }

    /// Re-query every permission. Cheap; safe to call from UI on demand.
    func refresh() {
        microphone = microphoneStatus()
        accessibility = accessibilityStatus()
        log.info("Permissions refresh: mic=\(String(describing: self.microphone), privacy: .public) ax=\(String(describing: self.accessibility), privacy: .public)")

        if allGranted, let cd = currentCDHash {
            UserDefaults.standard.set(cd, forKey: lastGrantedCDHashKey)
            signatureChangedSinceLastGrant = false
        }
    }

    var allGranted: Bool {
        microphone == .granted && accessibility == .granted
    }

    /// Accessibility caches its decision per-process: a grant made while
    /// Whisp is running isn't visible until Whisp restarts. Mic doesn't
    /// have this trap.
    var needsRestart: Bool {
        accessibility != .granted
    }

    /// Nuclear reset: clear all Whisp TCC entries and quit so the next
    /// launch comes up clean.
    func hardReset() {
        log.warning("Hard reset: clearing all TCC grants for ai.whisp.dev")
        let bundleID = Bundle.main.bundleIdentifier ?? "ai.whisp.dev"
        _ = runTccutil(service: "All", bundle: bundleID)
        UserDefaults.standard.removeObject(forKey: lastGrantedCDHashKey)
        UserDefaults.standard.synchronize()
        openSystemSettings(pane: "Privacy")
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
            NSApp.terminate(nil)
        }
    }

    /// Spawn `open -n` to launch a fresh copy of Whisp and exit.
    func restartWhisp() {
        let bundlePath = Bundle.main.bundleURL.path
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

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    // MARK: - Accessibility

    private func accessibilityStatus() -> PermissionStatus {
        AXIsProcessTrusted() ? .granted : .notDetermined
    }

    func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options: CFDictionary = [key: kCFBooleanTrue!] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSystemSettings(pane: "Privacy_Accessibility")
    }

    // MARK: - Direct pane opens

    func openAccessibilityPane() {
        openSystemSettings(pane: "Privacy_Accessibility")
    }

    // MARK: - Signature tracking

    private let lastGrantedCDHashKey = "lastGrantedCDHash"

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
            log.info("CDHash changed since last grant: was \(stored, privacy: .public), now \(cd, privacy: .public)")
            signatureChangedSinceLastGrant = true
        }
    }

    // MARK: - Subprocess plumbing

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
