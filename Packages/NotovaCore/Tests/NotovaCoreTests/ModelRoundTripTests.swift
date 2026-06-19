import XCTest
@testable import NotovaCore

/// Comprehensive Codable round-trip and edge-case coverage for every public
/// model. Decodes back through the SAME types and also asserts the stable
/// on-the-wire JSON keys / enum raw values that form the cross-platform
/// contract (changing these silently would break other clients).
final class ModelRoundTripTests: XCTestCase {

    // MARK: - Helpers

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Encode to a `[String: Any]`-style JSON object for key inspection.
    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let obj = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(obj as? [String: Any])
    }

    private let longText = String(repeating: "Lorem ipsum dolor sit amet. ", count: 5_000) // > 100k chars
    private let unicode = "café ☕️ 日本語 🇯🇵 emoji 😀🎉 RTL: مرحبا بالعالم שלום עולם \u{200F}"

    // MARK: - Recording

    func testRecordingRoundTripBasic() throws {
        let original = Recording(
            title: "Standup",
            durationSec: 123.4,
            source: .bluetooth,
            localAudioPath: "/var/audio.m4a",
            status: .ready
        )
        XCTAssertEqual(try roundTrip(original), original)
    }

    func testRecordingRoundTripAllSources() throws {
        for source in Recording.Source.allCases {
            let original = Recording(title: "S-\(source.rawValue)", source: source)
            let decoded = try roundTrip(original)
            XCTAssertEqual(decoded, original)
            XCTAssertEqual(decoded.source, source)
        }
    }

    func testRecordingRoundTripAllStatuses() throws {
        for status in Recording.Status.allCases {
            let original = Recording(title: "S-\(status.rawValue)", status: status)
            let decoded = try roundTrip(original)
            XCTAssertEqual(decoded, original)
            XCTAssertEqual(decoded.status, status)
        }
    }

    func testRecordingRoundTripNilOptional() throws {
        let original = Recording(title: "No path", localAudioPath: nil)
        let decoded = try roundTrip(original)
        XCTAssertNil(decoded.localAudioPath)
        XCTAssertEqual(decoded, original)
    }

    func testRecordingRoundTripEmptyTitle() throws {
        let original = Recording(title: "")
        XCTAssertEqual(try roundTrip(original), original)
    }

    func testRecordingRoundTripVeryLongTitle() throws {
        let original = Recording(title: longText)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded, original)
        XCTAssertGreaterThan(decoded.title.count, 100_000)
    }

    func testRecordingRoundTripUnicodeTitle() throws {
        let original = Recording(title: unicode, localAudioPath: unicode)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.title, unicode)
    }

    func testRecordingRoundTripBoundaryDurations() throws {
        for value in [0.0, -0.0, 0.000_001, 1.0, 86_400.0, Double.greatestFiniteMagnitude, -1.0] {
            let original = Recording(title: "dur", durationSec: value)
            let decoded = try roundTrip(original)
            XCTAssertEqual(decoded.durationSec, value, "duration \(value) should survive round-trip")
        }
    }

    func testRecordingPreservesIdentityAndDate() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let original = Recording(id: id, title: "x", createdAt: date)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
    }

    func testRecordingJSONKeysStable() throws {
        let obj = try jsonObject(Recording(title: "t", localAudioPath: "/p"))
        XCTAssertEqual(Set(obj.keys),
                       ["id", "title", "createdAt", "durationSec", "source", "localAudioPath", "status"])
    }

    func testRecordingOmitsNilOptionalKey() throws {
        // Default encoder omits nil optionals.
        let obj = try jsonObject(Recording(title: "t", localAudioPath: nil))
        XCTAssertFalse(obj.keys.contains("localAudioPath"))
    }

    func testRecordingSourceRawValuesStable() {
        XCTAssertEqual(Recording.Source.mic.rawValue, "mic")
        XCTAssertEqual(Recording.Source.bluetooth.rawValue, "bluetooth")
        XCTAssertEqual(Recording.Source.file.rawValue, "file")
        XCTAssertEqual(Recording.Source.other.rawValue, "other")
        XCTAssertEqual(Recording.Source.allCases.count, 4)
    }

    func testRecordingStatusRawValuesStable() {
        XCTAssertEqual(Recording.Status.recording.rawValue, "recording")
        XCTAssertEqual(Recording.Status.processing.rawValue, "processing")
        XCTAssertEqual(Recording.Status.ready.rawValue, "ready")
        XCTAssertEqual(Recording.Status.failed.rawValue, "failed")
        XCTAssertEqual(Recording.Status.allCases.count, 4)
    }

    func testRecordingDecodesFromStableWireFormat() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","title":"Wire",
         "createdAt":0,"durationSec":12.5,"source":"file",
         "localAudioPath":"/x.m4a","status":"ready"}
        """
        let decoded = try JSONDecoder().decode(Recording.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.id, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        XCTAssertEqual(decoded.title, "Wire")
        XCTAssertEqual(decoded.source, .file)
        XCTAssertEqual(decoded.status, .ready)
        XCTAssertEqual(decoded.durationSec, 12.5)
    }

    func testRecordingDecodeUnknownSourceThrows() {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","title":"x","createdAt":0,
         "durationSec":0,"source":"telepathy","status":"ready"}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(Recording.self, from: Data(json.utf8)))
    }

    func testRecordingHashableEqualityAndInequality() {
        let base = Recording(title: "x")
        XCTAssertEqual(base, base)
        var changed = base
        changed.title = "y"
        XCTAssertNotEqual(base, changed)
        XCTAssertEqual(Set([base, base]).count, 1)
        XCTAssertEqual(Set([base, changed]).count, 2)
    }

    // MARK: - TranscriptSegment

    func testTranscriptSegmentRoundTrip() throws {
        let original = TranscriptSegment(startMs: 0, endMs: 1500, text: "Hello", speaker: "A")
        XCTAssertEqual(try roundTrip(original), original)
    }

    func testTranscriptSegmentNilSpeaker() throws {
        let original = TranscriptSegment(startMs: 10, endMs: 20, text: "x", speaker: nil)
        let decoded = try roundTrip(original)
        XCTAssertNil(decoded.speaker)
        XCTAssertEqual(decoded, original)
    }

    func testTranscriptSegmentBoundaryMillis() throws {
        for (start, end) in [(0, 0), (Int.min, Int.max), (-5, -1), (Int.max, Int.max)] {
            let original = TranscriptSegment(startMs: start, endMs: end, text: "t")
            let decoded = try roundTrip(original)
            XCTAssertEqual(decoded.startMs, start)
            XCTAssertEqual(decoded.endMs, end)
        }
    }

    func testTranscriptSegmentUnicodeAndEmptyText() throws {
        XCTAssertEqual(try roundTrip(TranscriptSegment(startMs: 0, endMs: 1, text: "")),
                       TranscriptSegment(startMs: 0, endMs: 1, text: ""))
        XCTAssertEqual(try roundTrip(TranscriptSegment(startMs: 0, endMs: 1, text: unicode)).text, unicode)
    }

    func testTranscriptSegmentJSONKeysStable() throws {
        let obj = try jsonObject(TranscriptSegment(startMs: 1, endMs: 2, text: "x", speaker: "A"))
        XCTAssertEqual(Set(obj.keys), ["startMs", "endMs", "text", "speaker"])
    }

    // MARK: - Transcript

    func testTranscriptRoundTrip() throws {
        let id = UUID()
        let original = Transcript(
            recordingId: id,
            language: "en",
            fullText: "One. Two.",
            segments: [
                TranscriptSegment(startMs: 0, endMs: 500, text: "One.", speaker: "A"),
                TranscriptSegment(startMs: 500, endMs: 900, text: "Two.")
            ]
        )
        XCTAssertEqual(try roundTrip(original), original)
    }

    func testTranscriptEmptySegments() throws {
        let original = Transcript(recordingId: UUID(), language: "en", fullText: "", segments: [])
        let decoded = try roundTrip(original)
        XCTAssertTrue(decoded.segments.isEmpty)
        XCTAssertEqual(decoded, original)
    }

    func testTranscriptVeryLongFullText() throws {
        let original = Transcript(recordingId: UUID(), language: "en", fullText: longText, segments: [])
        let decoded = try roundTrip(original)
        XCTAssertGreaterThan(decoded.fullText.count, 100_000)
        XCTAssertEqual(decoded, original)
    }

    func testTranscriptUnicodeAndRTLLanguage() throws {
        let original = Transcript(recordingId: UUID(), language: "ar", fullText: unicode, segments: [
            TranscriptSegment(startMs: 0, endMs: 1, text: "مرحبا", speaker: "متحدث")
        ])
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.language, "ar")
        XCTAssertEqual(decoded.fullText, unicode)
        XCTAssertEqual(decoded.segments.first?.speaker, "متحدث")
    }

    func testTranscriptManySegments() throws {
        let segments = (0..<1_000).map {
            TranscriptSegment(startMs: $0 * 10, endMs: $0 * 10 + 9, text: "seg-\($0)", speaker: "S\($0 % 3)")
        }
        let original = Transcript(recordingId: UUID(), language: "en", fullText: "x", segments: segments)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.segments.count, 1_000)
        XCTAssertEqual(decoded.segments[500].text, "seg-500")
    }

    func testTranscriptJSONKeysStable() throws {
        let obj = try jsonObject(Transcript(recordingId: UUID(), language: "en", fullText: "x", segments: []))
        XCTAssertEqual(Set(obj.keys), ["recordingId", "language", "fullText", "segments"])
    }

    // MARK: - ActionItem

    func testActionItemRoundTrip() throws {
        let original = ActionItem(id: UUID(), text: "Do thing", done: false)
        XCTAssertEqual(try roundTrip(original), original)
    }

    func testActionItemDoneFlagRoundTrip() throws {
        for done in [true, false] {
            let original = ActionItem(text: "x", done: done)
            XCTAssertEqual(try roundTrip(original).done, done)
        }
    }

    func testActionItemEmptyAndUnicodeText() throws {
        XCTAssertEqual(try roundTrip(ActionItem(text: "")).text, "")
        XCTAssertEqual(try roundTrip(ActionItem(text: unicode)).text, unicode)
    }

    func testActionItemPreservesId() throws {
        let id = UUID()
        let decoded = try roundTrip(ActionItem(id: id, text: "x", done: true))
        XCTAssertEqual(decoded.id, id)
        XCTAssertTrue(decoded.done)
    }

    func testActionItemJSONKeysStable() throws {
        let obj = try jsonObject(ActionItem(text: "x"))
        XCTAssertEqual(Set(obj.keys), ["id", "text", "done"])
    }

    // MARK: - Summary

    func testSummaryRoundTrip() throws {
        let original = Summary(
            recordingId: UUID(),
            style: "detailed",
            contentMarkdown: "## Hello\n- world",
            actionItems: [ActionItem(text: "Do the thing"), ActionItem(text: "Done thing", done: true)],
            model: "stub-summarizer-v1"
        )
        XCTAssertEqual(try roundTrip(original), original)
    }

    func testSummaryEmptyActionItems() throws {
        let original = Summary(recordingId: UUID(), style: "concise", contentMarkdown: "",
                               actionItems: [], model: "m")
        let decoded = try roundTrip(original)
        XCTAssertTrue(decoded.actionItems.isEmpty)
        XCTAssertEqual(decoded, original)
    }

    func testSummaryVeryLongMarkdownAndManyItems() throws {
        let items = (0..<500).map { ActionItem(text: "item-\($0)", done: $0 % 2 == 0) }
        let original = Summary(recordingId: UUID(), style: "concise", contentMarkdown: longText,
                               actionItems: items, model: "m")
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.actionItems.count, 500)
        XCTAssertGreaterThan(decoded.contentMarkdown.count, 100_000)
        XCTAssertEqual(decoded, original)
    }

    func testSummaryUnicodeContent() throws {
        let original = Summary(recordingId: UUID(), style: unicode, contentMarkdown: unicode,
                               actionItems: [ActionItem(text: unicode)], model: unicode)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.style, unicode)
        XCTAssertEqual(decoded.contentMarkdown, unicode)
    }

    func testSummaryPreservesGeneratedAt() throws {
        let date = Date(timeIntervalSince1970: 1_650_000_000)
        let original = Summary(recordingId: UUID(), style: "s", contentMarkdown: "c",
                               actionItems: [], model: "m", generatedAt: date)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded.generatedAt.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
    }

    func testSummaryJSONKeysStable() throws {
        let obj = try jsonObject(Summary(recordingId: UUID(), style: "s", contentMarkdown: "c",
                                         actionItems: [], model: "m"))
        XCTAssertEqual(Set(obj.keys),
                       ["recordingId", "style", "contentMarkdown", "actionItems", "model", "generatedAt"])
    }

    // MARK: - IntegrationExport

    func testIntegrationExportRoundTripAllStatuses() throws {
        for status in [IntegrationExport.Status.pending, .done, .failed] {
            let original = IntegrationExport(recordingId: UUID(), provider: "notion",
                                             externalId: "ext", url: "https://x", status: status)
            let decoded = try roundTrip(original)
            XCTAssertEqual(decoded, original)
            XCTAssertEqual(decoded.status, status)
        }
    }

    func testIntegrationExportNilOptionals() throws {
        let original = IntegrationExport(recordingId: UUID(), provider: "email",
                                         externalId: nil, url: nil, status: .done)
        let decoded = try roundTrip(original)
        XCTAssertNil(decoded.externalId)
        XCTAssertNil(decoded.url)
        XCTAssertEqual(decoded, original)
    }

    func testIntegrationExportStatusRawValuesStable() {
        XCTAssertEqual(IntegrationExport.Status.pending.rawValue, "pending")
        XCTAssertEqual(IntegrationExport.Status.done.rawValue, "done")
        XCTAssertEqual(IntegrationExport.Status.failed.rawValue, "failed")
    }

    func testIntegrationExportJSONKeysStable() throws {
        let obj = try jsonObject(IntegrationExport(recordingId: UUID(), provider: "notion",
                                                   externalId: "e", url: "u", status: .done))
        XCTAssertEqual(Set(obj.keys), ["recordingId", "provider", "externalId", "url", "status"])
    }

    func testIntegrationExportConvenienceConstructor() {
        let export = IntegrationExport(recordingId: UUID(), provider: "notion")
        XCTAssertEqual(export.status, .pending)
        XCTAssertEqual(export.provider, "notion")
        XCTAssertNil(export.externalId)
        XCTAssertNil(export.url)
    }

    // MARK: - Note (composite, not Codable but Identifiable/Hashable)

    func testNoteIdMatchesRecordingId() {
        let recording = Recording(title: "x")
        let note = Note(recording: recording)
        XCTAssertEqual(note.id, recording.id)
        XCTAssertNil(note.transcript)
        XCTAssertNil(note.summary)
    }

    func testNoteHashableEquality() {
        let recording = Recording(title: "x")
        let a = Note(recording: recording)
        let b = Note(recording: recording)
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 1)
    }
}
