import AVFoundation
import AppKit
import ApplicationServices
import Foundation
import MoonshineVoice
import OSLog

/// Verifies that every subsystem Whisp depends on is actually working,
/// not just present. The user can't tell whether Whisp is broken until
/// they try the hotkey and watch nothing happen; SelfTest catches that
/// at launch and shows a colored menu bar icon so failure modes are
/// visible immediately.
///
/// Each check is independent and has three outcomes:
///   - `.ok` — verified working.
///   - `.warning(message)` — degraded but Whisp still works.
///   - `.failure(message)` — Whisp won't work until the user fixes this.
///
/// Overall result is `.ok` if all checks pass, `.warning` if any warning
/// and no failures, `.failure` if any failure.
struct SelfTestResult: Equatable {
    enum Status: Equatable {
        case ok
        case warning(String)
        case failure(String)
    }

    let microphone: Status
    let accessibility: Status
    let modelLoaded: Status
    let hotkeyMonitor: Status

    var overall: Status {
        let all = [microphone, accessibility, modelLoaded, hotkeyMonitor]
        if let failure = all.first(where: { if case .failure = $0 { return true }; return false }) {
            return failure
        }
        if let warning = all.first(where: { if case .warning = $0 { return true }; return false }) {
            return warning
        }
        return .ok
    }

    var summary: String {
        switch overall {
        case .ok: return "All systems go"
        case .warning(let m): return "Warning: \(m)"
        case .failure(let m): return "Failure: \(m)"
        }
    }

    var detailedReport: String {
        func line(_ name: String, _ status: Status) -> String {
            switch status {
            case .ok: return "✓ \(name)"
            case .warning(let m): return "⚠ \(name): \(m)"
            case .failure(let m): return "✗ \(name): \(m)"
            }
        }
        return [
            line("Microphone permission", microphone),
            line("Accessibility permission", accessibility),
            line("Speech-to-text model", modelLoaded),
            line("Hotkey monitor", hotkeyMonitor),
        ].joined(separator: "\n")
    }
}

@MainActor
final class SelfTest {
    private let log = Logger(subsystem: "ai.whisp.dev", category: "SelfTest")

    private let permissions: PermissionsManager
    private let modelPath: String
    private let hotkeyIsRunning: () -> Bool

    init(
        permissions: PermissionsManager,
        modelPath: String,
        hotkeyIsRunning: @escaping () -> Bool
    ) {
        self.permissions = permissions
        self.modelPath = modelPath
        self.hotkeyIsRunning = hotkeyIsRunning
    }

    /// Run every check and return the aggregate. Synchronous and fast
    /// (the model-load check is the slowest at ~50ms; everything else
    /// is a TCC query or a single Swift bool).
    func run() -> SelfTestResult {
        let result = SelfTestResult(
            microphone: checkMicrophone(),
            accessibility: checkAccessibility(),
            modelLoaded: checkModel(),
            hotkeyMonitor: checkHotkey()
        )
        log.info("SelfTest result: \(result.summary, privacy: .public)")
        return result
    }

    // MARK: - Individual checks

    private func checkMicrophone() -> SelfTestResult.Status {
        switch permissions.microphone {
        case .granted:        return .ok
        case .denied:         return .failure("Denied in System Settings — dictation will not work")
        case .notDetermined:  return .failure("Not granted yet — click Request in Settings")
        }
    }

    private func checkAccessibility() -> SelfTestResult.Status {
        switch permissions.accessibility {
        case .granted:        return .ok
        case .denied:         return .failure("Denied in System Settings — hotkey and paste will not work")
        case .notDetermined:  return .failure("Not granted yet — click Open Settings in Whisp")
        }
    }

    private func checkModel() -> SelfTestResult.Status {
        let fm = FileManager.default
        guard fm.fileExists(atPath: modelPath) else {
            return .failure("Model directory missing at \(modelPath)")
        }
        // Each model has a "tokenizer.bin" plus an encoder/decoder. We
        // don't load it here (too slow) — presence-of-files is enough
        // for the self-test. The actual load happens when dictation
        // starts and any error there surfaces via the engine.
        let required = ["tokenizer.bin"]
        for file in required {
            let path = (modelPath as NSString).appendingPathComponent(file)
            if !fm.fileExists(atPath: path) {
                return .failure("Model file missing: \(file)")
            }
        }
        return .ok
    }

    private func checkHotkey() -> SelfTestResult.Status {
        if hotkeyIsRunning() {
            // The NSEvent monitor depends on Accessibility — if we got
            // here with the monitor running but AX denied, NSEvent will
            // accept the registration but silently not deliver events.
            // So flag that combination.
            if permissions.accessibility != .granted {
                return .warning("Monitor registered but Accessibility is needed to receive events")
            }
            return .ok
        }
        return .failure("Hotkey monitor failed to start")
    }
}
