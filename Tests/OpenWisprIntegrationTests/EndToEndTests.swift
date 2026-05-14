import XCTest
import MoonshineVoice
@testable import OpenWisprCore

/// Drives a real `Transcriber` against a small WAV fixture and feeds the
/// completed lines through `TranscriptBuffer`. This is the end-to-end check
/// that the Moonshine xcframework loads correctly, that the bundled model
/// works, and that OpenWispr's transcript shaping produces sensible output.
final class EndToEndTests: XCTestCase {
    /// Locates the tiny-en model packaged inside the Moonshine xcframework.
    /// Returns nil (and the test skips) if neither the framework bundle nor
    /// the on-disk xcframework next to ../moonshine has a model.
    private func tinyEnModelPath() -> String? {
        if let bundle = Transcriber.frameworkBundle,
           let resources = bundle.resourcePath
        {
            let candidate = (resources as NSString).appendingPathComponent("test-assets/tiny-en")
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        // Fallback: probe ../moonshine/swift/Moonshine.xcframework directly.
        // SwiftPM tests run with cwd at the package root, so we can resolve
        // it relative to the source-file path.
        let here = URL(fileURLWithPath: #filePath)
        let workspaceRoot = here
            .deletingLastPathComponent()  // OpenWisprIntegrationTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // openwispr
            .deletingLastPathComponent()  // workspace root
        let xcframework = workspaceRoot
            .appendingPathComponent("moonshine/swift/Moonshine.xcframework")
            .appendingPathComponent("macos-arm64_x86_64/Resources/test-assets/tiny-en")
        if FileManager.default.fileExists(atPath: xcframework.path) {
            return xcframework.path
        }
        return nil
    }

    private func wavFixturePath() throws -> String {
        let bundle = Bundle.module
        if let url = bundle.url(forResource: "beckett", withExtension: "wav") {
            return url.path
        }
        // `.copy("Fixtures")` preserves the folder structure inside the
        // resource bundle, so the asset lives at Fixtures/beckett.wav.
        if let url = bundle.url(forResource: "beckett", withExtension: "wav", subdirectory: "Fixtures") {
            return url.path
        }
        throw XCTSkip("beckett.wav fixture not bundled")
    }

    func testTranscribesWavAndShapesIntoBufferOutput() throws {
        guard let modelPath = tinyEnModelPath() else {
            throw XCTSkip("Moonshine tiny-en model not available in this test environment")
        }
        let wavPath = try wavFixturePath()

        let transcriber = try Transcriber(modelPath: modelPath, modelArch: .tiny)
        let wav = try loadWAVFile(wavPath)
        let transcript = try transcriber.transcribeWithoutStreaming(
            audioData: wav.audioData,
            sampleRate: Int32(wav.sampleRate)
        )

        // We don't pin exact text (model could revise across versions), but
        // we should get at least one line of non-empty output.
        XCTAssertFalse(transcript.lines.isEmpty, "Expected at least one transcript line")
        let allText = transcript.lines.map(\.text).joined(separator: " ")
        XCTAssertGreaterThan(allText.trimmingCharacters(in: .whitespaces).count, 5,
                             "Transcript was unexpectedly short: \(allText)")

        // Now feed the completed lines through TranscriptBuffer the same way
        // DictationEngine does, and confirm we produce non-empty injected text.
        var buffer = TranscriptBuffer()
        var injected = ""
        for line in transcript.lines {
            if let piece = buffer.ingestCompletedLine(line.text) {
                injected += piece
            }
        }
        XCTAssertEqual(buffer.emittedLineCount, transcript.lines.count)
        XCTAssertTrue(injected.hasSuffix(" "),
                      "Trailing space ensures consecutive sessions don't collide")
    }
}
