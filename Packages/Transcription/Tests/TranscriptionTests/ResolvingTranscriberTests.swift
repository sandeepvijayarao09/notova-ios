import XCTest
import NotovaCore
@testable import Transcription

final class ResolvingTranscriberTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/x.m4a")

    // MARK: - Fakes

    /// A configurable engine: availability toggled, output tagged with its name.
    private struct FakeEngine: TranscriptionEngine {
        let engineName: String
        let available: Bool
        func isAvailable() async -> Bool { available }
        func transcribe(audioURL: URL, recordingId: UUID) async throws -> Transcript {
            Transcript(recordingId: recordingId, language: "en", fullText: engineName, segments: [])
        }
    }

    // MARK: - Selection

    func testPicksFirstAvailableEngine() async throws {
        let resolver = ResolvingTranscriber(engines: [
            FakeEngine(engineName: "A", available: false),
            FakeEngine(engineName: "B", available: true),
            FakeEngine(engineName: "C", available: true)
        ])
        let transcript = try await resolver.transcribe(audioURL: url, recordingId: UUID())
        XCTAssertEqual(transcript.fullText, "B", "first available engine should handle the request")
    }

    func testFallsThroughToLastWhenOthersUnavailable() async throws {
        let resolver = ResolvingTranscriber(engines: [
            FakeEngine(engineName: "A", available: false),
            FakeEngine(engineName: "B", available: false),
            FakeEngine(engineName: "Stub", available: true)
        ])
        let transcript = try await resolver.transcribe(audioURL: url, recordingId: UUID())
        XCTAssertEqual(transcript.fullText, "Stub")
    }

    func testPrefersHighestPriorityWhenAllAvailable() async throws {
        let resolver = ResolvingTranscriber(engines: [
            FakeEngine(engineName: "Top", available: true),
            FakeEngine(engineName: "Mid", available: true)
        ])
        let transcript = try await resolver.transcribe(audioURL: url, recordingId: UUID())
        XCTAssertEqual(transcript.fullText, "Top")
    }

    func testThrowsWhenNoEngineAvailable() async {
        let resolver = ResolvingTranscriber(engines: [
            FakeEngine(engineName: "A", available: false)
        ])
        do {
            _ = try await resolver.transcribe(audioURL: url, recordingId: UUID())
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? NotovaError, .transcriptionFailed("No transcription engine available"))
        }
    }

    // MARK: - Resolution recording

    func testRecordsActiveEngineAndCandidates() async throws {
        let resolver = ResolvingTranscriber(engines: [
            FakeEngine(engineName: "A", available: false),
            FakeEngine(engineName: "B", available: true)
        ])
        _ = try await resolver.transcribe(audioURL: url, recordingId: UUID())
        let resolution = await resolver.resolution
        XCTAssertEqual(resolution.activeEngineName, "B")
        XCTAssertEqual(resolution.candidates.map(\.name), ["A", "B"])
        XCTAssertEqual(resolution.candidates.map(\.available), [false, true])
    }

    func testInitialResolutionListsChainBeforeAnyCall() async {
        let resolver = ResolvingTranscriber(engines: [
            FakeEngine(engineName: "A", available: true),
            FakeEngine(engineName: "B", available: true)
        ])
        let resolution = await resolver.resolution
        XCTAssertNil(resolution.activeEngineName)
        XCTAssertEqual(resolution.candidates.map(\.name), ["A", "B"])
    }

    // MARK: - Default chain

    func testDefaultChainShapeIsAppleSpeechThenStub() {
        let engines = TranscriptionService.defaultEngines()
        XCTAssertEqual(engines.map(\.engineName), ["Apple Speech (on-device)", "Built-in sample transcriber"])
    }
}
