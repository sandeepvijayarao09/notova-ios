import XCTest
import NotovaCore
@testable import AISummary

final class SummaryServiceTests: XCTestCase {
    private func transcript(_ text: String) -> Transcript {
        Transcript(recordingId: UUID(), language: "en", fullText: text, segments: [])
    }

    func testMakeDefaultReturnsAConformingSummarizer() async throws {
        let summarizer = SummaryService.makeDefault()
        let summary = try await summarizer.summarize(transcript("Send the report."), style: "concise")
        XCTAssertEqual(summary.style, "concise")
        XCTAssertFalse(summary.contentMarkdown.isEmpty)
        XCTAssertFalse(summary.model.isEmpty)
    }

    func testMakeDefaultExtractsActionItems() async throws {
        let summary = try await SummaryService.makeDefault()
            .summarize(transcript("Please send the deck. Schedule a call."), style: "concise")
        XCTAssertEqual(summary.actionItems.count, 2)
    }

    func testMakeDefaultPropagatesRecordingId() async throws {
        let id = UUID()
        let summary = try await SummaryService.makeDefault()
            .summarize(Transcript(recordingId: id, language: "en", fullText: "x", segments: []), style: "s")
        XCTAssertEqual(summary.recordingId, id)
    }
}
