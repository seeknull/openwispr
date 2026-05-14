import Foundation

/// Read the build's version metadata out of the running bundle's
/// Info.plist. Populated by `scripts/build-release.sh` at packaging
/// time — see the stamping section in that script.
///
/// `version` is the marketing version (e.g. "0.1.0").
/// `buildNumber` is a `YYYYMMDDhhmm` UTC stamp injected at build time.
/// `buildDate` is the same instant in ISO-8601 form for human display.
/// `commitSHA` is the short git hash the build was cut from.
enum AppVersion {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "?"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "?"
    }

    static var buildDate: String {
        Bundle.main.object(forInfoDictionaryKey: "OWBuildDate")
            as? String ?? "?"
    }

    static var commitSHA: String {
        Bundle.main.object(forInfoDictionaryKey: "OWBuildCommit")
            as? String ?? "?"
    }

    /// "v0.1.0 · build 202605141845 · g1bc303d"
    /// Suitable for a footer line in the Settings window.
    static var summaryLine: String {
        "v\(version) · build \(buildNumber) · \(commitSHA)"
    }

    /// Human-friendly "Sat May 14, 2026 18:45 UTC" — for the About tab.
    /// Falls back to the raw ISO string if parsing fails.
    static var friendlyBuildDate: String {
        let iso = ISO8601DateFormatter()
        guard let date = iso.date(from: buildDate) else { return buildDate }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        df.timeZone = TimeZone(identifier: "UTC")
        return df.string(from: date) + " UTC"
    }
}
