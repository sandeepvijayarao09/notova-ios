import XCTest
import NotovaCore
@testable import AISummary

final class AppleFoundationModelsSummarizerTests: XCTestCase {
    private func transcript(_ text: String) -> Transcript {
        Transcript(recordingId: UUID(), language: "en", fullText: text, segments: [])
    }

    // MARK: - Fake generator

    private struct FakeGenerator: FoundationTextGenerator {
        let available: Bool
        let output: String
        init(available: Bool, output: String = "") {
            self.available = available
            self.output = output
        }
        func isAvailable() async -> Bool { available }
        func generate(prompt: String) async throws -> String { output }
    }

    // MARK: - Availability gating

    func testUnavailableWhenGeneratorUnavailable() async {
        let engine = AppleFoundationModelsSummarizer(generator: FakeGenerator(available: false))
        let available = await engine.isAvailable()
        XCTAssertFalse(available)
    }

    func testAvailableWhenGeneratorAvailable() async {
        let engine = AppleFoundationModelsSummarizer(generator: FakeGenerator(available: true))
        let available = await engine.isAvailable()
        XCTAssertTrue(available)
    }

    func testEngineNameStable() {
        XCTAssertEqual(AppleFoundationModelsSummarizer().engineName, "Apple Foundation Models")
    }

    /// The *real* system-backed generator must answer `isAvailable()` without
    /// crashing and consistently with the OS guard: it can only be `true` on
    /// iOS/macOS 26+ where `SystemLanguageModel.default.availability == .available`
    /// (e.g. an Apple-Intelligence Mac host), and is otherwise `false` (simulator,
    /// CI, older OS). Either way the resolver degrades gracefully.
    func testSystemBackedGeneratorAvailabilityMatchesGuard() async {
        let engine = AppleFoundationModelsSummarizer()
        let available = await engine.isAvailable()
        var expectedPossible = false
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) { expectedPossible = true }
        #endif
        if available {
            XCTAssertTrue(expectedPossible, "availability=true is only valid where FoundationModels 26+ exists")
        }
    }

    // MARK: - Prompt

    func testPromptIncludesStyleAndTranscript() {
        let prompt = AppleFoundationModelsSummarizer.buildPrompt(
            transcript: transcript("The meeting went well."), style: "bullet"
        )
        XCTAssertTrue(prompt.contains("bullet"))
        XCTAssertTrue(prompt.contains("The meeting went well."))
    }

    // MARK: - Output mapping / parsing

    func testParsesActionItemsUnderHeading() async throws {
        let output = """
        ## Overview
        We discussed the launch.

        ## Action items
        - Send the deck to marketing
        - [ ] Schedule the review
        * Book the venue
        """
        let engine = AppleFoundationModelsSummarizer(generator: FakeGenerator(available: true, output: output))
        let summary = try await engine.summarize(transcript("irrelevant"), style: "concise")
        XCTAssertEqual(summary.model, "apple-foundation-models")
        XCTAssertEqual(summary.contentMarkdown, output)
        XCTAssertEqual(summary.actionItems.map(\.text), [
            "Send the deck to marketing",
            "Schedule the review",
            "Book the venue"
        ])
    }

    func testActionItemsSectionEndsAtNextHeading() {
        let md = """
        ## Action items
        - Do the thing

        ## Notes
        - This is not an action item
        """
        let items = AppleFoundationModelsSummarizer.parseActionItems(from: md)
        XCTAssertEqual(items.map(\.text), ["Do the thing"])
    }

    func testFallsBackToHeuristicWhenNoActionSection() async throws {
        let output = "## Overview\nSome prose with no action section."
        let engine = AppleFoundationModelsSummarizer(generator: FakeGenerator(available: true, output: output))
        // The transcript contains an action verb, so the heuristic should fire.
        let summary = try await engine.summarize(transcript("Please send the agenda."), style: "concise")
        XCTAssertEqual(summary.actionItems.count, 1)
        XCTAssertTrue(summary.actionItems[0].text.contains("send the agenda"))
    }

    func testNoActionItemsWhenNeitherSectionNorHeuristic() async throws {
        let engine = AppleFoundationModelsSummarizer(
            generator: FakeGenerator(available: true, output: "## Overview\nNice weather today.")
        )
        let summary = try await engine.summarize(transcript("Nice weather today."), style: "concise")
        XCTAssertTrue(summary.actionItems.isEmpty)
    }

    func testRecordingIdAndStylePropagate() async throws {
        let id = UUID()
        let engine = AppleFoundationModelsSummarizer(generator: FakeGenerator(available: true, output: "x"))
        let summary = try await engine.summarize(
            Transcript(recordingId: id, language: "en", fullText: "y", segments: []), style: "detailed"
        )
        XCTAssertEqual(summary.recordingId, id)
        XCTAssertEqual(summary.style, "detailed")
    }
}
