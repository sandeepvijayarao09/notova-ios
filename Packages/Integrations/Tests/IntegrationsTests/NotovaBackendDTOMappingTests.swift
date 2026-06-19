import XCTest
import NotovaCore
@testable import Integrations

/// Pure (no-network) tests for the on-device -> backend DTO mapping used by
/// `NotovaBackendClient.export`. These document the field-name and unit
/// conversions: summary.text <- contentMarkdown, transcript.text <- fullText,
/// and ms -> sec for transcript segments.
final class NotovaBackendDTOMappingTests: XCTestCase {

    func testRecordingDTOMapsAllFields() {
        let id = UUID()
        let recording = Recording(id: id, title: "T", durationSec: 5, source: .bluetooth, status: .processing)
        let dto = NotovaBackendClient.RecordingDTO(recording: recording)
        XCTAssertEqual(dto.id, id.uuidString)
        XCTAssertEqual(dto.title, "T")
        XCTAssertEqual(dto.durationSec, 5)
        XCTAssertEqual(dto.source, "bluetooth")
        XCTAssertEqual(dto.status, "processing")
    }

    func testTranscriptDTOConvertsMillisecondsToSeconds() {
        let transcript = Transcript(recordingId: UUID(), language: "fr", fullText: "bonjour",
                                    segments: [TranscriptSegment(startMs: 250, endMs: 4000, text: "bonjour")])
        let dto = NotovaBackendClient.TranscriptDTO(transcript: transcript)
        XCTAssertEqual(dto.text, "bonjour", "transcript.text maps from on-device fullText")
        XCTAssertEqual(dto.language, "fr")
        // 250ms -> 0.25s, 4000ms -> 4.0s
        XCTAssertEqual(dto.segments?.first?.startSec, 0.25)
        XCTAssertEqual(dto.segments?.first?.endSec, 4.0)
    }

    func testSummaryDTOMapsContentMarkdownToText() {
        let summary = Summary(recordingId: UUID(), style: "x", contentMarkdown: "## Hi",
                              actionItems: [ActionItem(text: "do it", done: true)], model: "m")
        let dto = NotovaBackendClient.SummaryDTO(summary: summary)
        XCTAssertEqual(dto.text, "## Hi", "summary.text maps from on-device contentMarkdown")
        XCTAssertEqual(dto.actionItems?.first?.text, "do it")
        XCTAssertEqual(dto.actionItems?.first?.done, true)
        XCTAssertNotNil(dto.actionItems?.first?.id, "action item id carries the on-device UUID string")
        XCTAssertNil(dto.actionItems?.first?.dueAt, "on-device ActionItem has no dueAt")
    }
}
