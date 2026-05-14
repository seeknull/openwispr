import AVFoundation
import AppKit
import ApplicationServices
import Foundation

/// Coordinates the three macOS permissions Whisp depends on. Each helper
/// either returns the current grant state without prompting, or actively
/// prompts when called. Onboarding asks in this order:
///
///   1. Microphone — needed for the mic transcriber.
///   2. Accessibility — needed to post synthetic input events
///      (Cmd+V or per-character keystrokes).
///   3. Input Monitoring — needed for the CGEventTap to observe
///      modifier-flag changes (so we can detect Fn+Option).
///
/// macOS sandboxes each prompt: requesting Accessibility opens System
/// Settings to the right pane but does not bring focus back; users must
/// grant manually and re-launch the app in some cases. We surface the
/// status to the UI so a user can re-check anytime.
enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
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

    // MARK: - Microphone

    private func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// Prompts the user for mic access if not already determined. Updates
    /// `microphone` when the system completes.
    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    // MARK: - Accessibility (for posting keyboard events)

    private func accessibilityStatus() -> PermissionStatus {
        AXIsProcessTrusted() ? .granted : .notDetermined
    }

    /// Triggers the system Accessibility prompt and opens System Settings
    /// to the right pane. macOS will not flip the bit until the user
    /// toggles Whisp on in the list.
    func requestAccessibility() {
        // The system framework declares `kAXTrustedCheckOptionPrompt` as a
        // mutable global; under Swift 6 strict concurrency we can't read
        // through it directly. Constructing the CFString with the known
        // value is safe and equivalent.
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options: CFDictionary = [key: kCFBooleanTrue!] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSystemSettings(pane: "Privacy_Accessibility")
    }

    // MARK: - Input Monitoring (for CGEventTap)

    private func inputMonitoringStatus() -> PermissionStatus {
        // IOHIDCheckAccess is the canonical API but is gated by linking to
        // IOKit and isn't always reliable across macOS versions. As a
        // pragmatic alternative we attempt to create a no-op listen-only
        // event tap and observe whether it succeeds.
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, _, e, _ in Unmanaged.passUnretained(e) },
            userInfo: nil
        ) {
            CGEvent.tapEnable(tap: tap, enable: false)
            return .granted
        }
        return .notDetermined
    }

    func requestInputMonitoring() {
        // No direct API to trigger the prompt; just open the pane and ask
        // the user to enable Whisp.
        openSystemSettings(pane: "Privacy_ListenEvent")
    }

    // MARK: - Helpers

    private func openSystemSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
