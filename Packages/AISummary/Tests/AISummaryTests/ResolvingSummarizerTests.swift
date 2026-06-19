import XCTest
import NotovaCore
import ModelManagement
@testable import AISummary

final class ResolvingSummarizerTests: XCTestCase {
    private func transcript(_ text: String = "Send the report.") -> Transcript {
        Transcript(recordingId: UUID(), language: "en", fullText: text, segments: [])
    }

    // MARK: - Fakes

    private struct FakeEngine: SummarizationEngine {
        let engineName: String
        let available: Bool
        func isAvailable() async -> Bool { available }
        func summarize(_ transcript: Transcript, style: String) async throws -> Summary {
            Summary(recordingId: transcript.recordingId, style: style,
                    contentMarkdown: engineName, actionItems: [], model: engineName)
        }
    }

    // MARK: - Selection permutations

    func testPicksFirstAvailable() async throws {
        let resolver = ResolvingSummarizer(engines: [
            FakeEngine(engineName: "Gemma", available: false),
            FakeEngine(engineName: "Apple", available: true),
            FakeEngine(engineName: "Stub", available: true)
        ])
        let summary = try await resolver.summarize(transcript(), style: "concise")
        XCTAssertEqual(summary.model, "Apple")
    }

    func testFallsThroughToStub() async throws {
        let resolver = ResolvingSummarizer(engines: [
            FakeEngine(engineName: "Gemma", available: false),
            FakeEngine(engineName: "Apple", available: false),
            FakeEngine(engineName: "Stub", available: true)
        ])
        let summary = try await resolver.summarize(transcript(), style: "concise")
        XCTAssertEqual(summary.model, "Stub")
    }

    func testPrefersTopWhenAllAvailable() async throws {
        let resolver = ResolvingSummarizer(engines: [
            FakeEngine(engineName: "Gemma", available: true),
            FakeEngine(engineName: "Apple", available: true),
            FakeEngine(engineName: "Stub", available: true)
        ])
        let summary = try await resolver.summarize(transcript(), style: "concise")
        XCTAssertEqual(summary.model, "Gemma")
    }

    func testThrowsWhenNoneAvailable() async {
        let resolver = ResolvingSummarizer(engines: [FakeEngine(engineName: "X", available: false)])
        do {
            _ = try await resolver.summarize(transcript(), style: "s")
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? NotovaError, .summarizationFailed("No summarization engine available"))
        }
    }

    // MARK: - Resolution recording

    func testRecordsResolution() async throws {
        let resolver = ResolvingSummarizer(engines: [
            FakeEngine(engineName: "Gemma", available: false),
            FakeEngine(engineName: "Apple", available: true),
            FakeEngine(engineName: "Stub", available: true)
        ])
        _ = try await resolver.summarize(transcript(), style: "s")
        let resolution = await resolver.resolution
        XCTAssertEqual(resolution.activeEngineName, "Apple")
        XCTAssertEqual(resolution.candidates.map(\.name), ["Gemma", "Apple", "Stub"])
        XCTAssertEqual(resolution.candidates.map(\.available), [false, true, true])
    }

    // MARK: - Default chain wiring

    func testDefaultChainShape() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ModelStore(directory: dir)
        let engines = SummaryService.defaultEngines(store: store)
        XCTAssertEqual(engines.map(\.engineName),
                       ["Local Gemma (MLX)", "Apple Foundation Models", "Built-in sample summarizer"])
    }

    func testResolvingFallsBackToStubWhenNoModelOrAppleAI() async throws {
        // With an empty store and (in CI/sim) no Apple Intelligence, the resolver
        // must still produce a summary via the stub.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ModelStore(directory: dir)
        let resolver = SummaryService.makeResolving(store: store)
        let summary = try await resolver.summarize(transcript("Please send the deck."), style: "concise")
        XCTAssertFalse(summary.contentMarkdown.isEmpty)
        let resolution = await resolver.resolution
        // Local Gemma must be unavailable with no model installed.
        XCTAssertEqual(resolution.candidates.first(where: { $0.name == "Local Gemma (MLX)" })?.available, false)
    }
}
