import XCTest
import SwiftData
import NotovaCore
@testable import Persistence

@MainActor
final class NoteRepositoryTests: XCTestCase {

    private var repo: NoteRepository!

    override func setUpWithError() throws {
        repo = try NoteRepository(inMemory: true)
    }

    override func tearDown() {
        repo = nil
    }

    // MARK: - Fixtures

    private func makeNote(
        id: UUID = UUID(),
        title: String = "Note",
        createdAt: Date = Date(),
        status: Recording.Status = .ready,
        withTranscript: Bool = true,
        actionItems: [ActionItem] = [ActionItem(text: "Do it")]
    ) -> Note {
        let recording = Recording(id: id, title: title, createdAt: createdAt,
                                  durationSec: 12, source: .mic, localAudioPath: "/x.m4a", status: status)
        let transcript = withTranscript
            ? Transcript(recordingId: id, language: "en", fullText: "Hello world.",
                         segments: [TranscriptSegment(startMs: 0, endMs: 100, text: "Hello world.", speaker: "A")])
            : nil
        let summary = Summary(recordingId: id, style: "concise", contentMarkdown: "## Sum",
                              actionItems: actionItems, model: "stub")
        return Note(recording: recording, transcript: transcript, summary: summary)
    }

    // MARK: - Empty store

    func testEmptyStoreFetchReturnsEmpty() throws {
        XCTAssertTrue(try repo.allNotes().isEmpty)
        XCTAssertNil(try repo.note(id: UUID()))
    }

    func testInMemoryFlagProducesDistinctStores() throws {
        let other = try NoteRepository(inMemory: true)
        try repo.save(makeNote())
        // A separate in-memory container should not see the first repo's data.
        XCTAssertEqual(try other.allNotes().count, 0)
    }

    // MARK: - Save → fetch round-trips

    func testSaveThenFetchById() throws {
        let note = makeNote(title: "Roundtrip")
        try repo.save(note)

        let fetched = try XCTUnwrap(try repo.note(id: note.recording.id))
        XCTAssertEqual(fetched.recording.id, note.recording.id)
        XCTAssertEqual(fetched.recording.title, "Roundtrip")
        XCTAssertEqual(fetched.recording.source, .mic)
        XCTAssertEqual(fetched.recording.status, .ready)
        XCTAssertEqual(fetched.recording.localAudioPath, "/x.m4a")
    }

    func testSavePersistsTranscript() throws {
        let note = makeNote()
        try repo.save(note)
        let fetched = try XCTUnwrap(try repo.note(id: note.recording.id))
        let transcript = try XCTUnwrap(fetched.transcript)
        XCTAssertEqual(transcript.fullText, "Hello world.")
        XCTAssertEqual(transcript.segments.count, 1)
        XCTAssertEqual(transcript.segments.first?.speaker, "A")
    }

    func testSavePersistsSummaryAndActionItems() throws {
        let note = makeNote(actionItems: [ActionItem(text: "A"), ActionItem(text: "B", done: true)])
        try repo.save(note)
        let fetched = try XCTUnwrap(try repo.note(id: note.recording.id))
        let summary = try XCTUnwrap(fetched.summary)
        XCTAssertEqual(summary.style, "concise")
        XCTAssertEqual(summary.actionItems.count, 2)
        XCTAssertEqual(summary.actionItems.map(\.text), ["A", "B"])
        XCTAssertEqual(summary.actionItems.map(\.done), [false, true])
    }

    func testSaveNoteWithoutTranscript() throws {
        let note = makeNote(withTranscript: false)
        try repo.save(note)
        let fetched = try XCTUnwrap(try repo.note(id: note.recording.id))
        XCTAssertNil(fetched.transcript)
        XCTAssertNotNil(fetched.summary)
    }

    func testAllNotesReturnsAllSaved() throws {
        for index in 0..<5 { try repo.save(makeNote(title: "n\(index)")) }
        XCTAssertEqual(try repo.allNotes().count, 5)
    }

    // MARK: - Ordering (newest first)

    func testAllNotesOrderedNewestFirst() throws {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let oldest = makeNote(title: "oldest", createdAt: base)
        let middle = makeNote(title: "middle", createdAt: base.addingTimeInterval(100))
        let newest = makeNote(title: "newest", createdAt: base.addingTimeInterval(200))

        // Insert out of order to prove the sort, not insertion order.
        try repo.save(middle)
        try repo.save(newest)
        try repo.save(oldest)

        let titles = try repo.allNotes().map(\.recording.title)
        XCTAssertEqual(titles, ["newest", "middle", "oldest"])
    }

    // MARK: - Update (upsert by id)

    func testSaveTwiceUpsertsRatherThanDuplicates() throws {
        let id = UUID()
        try repo.save(makeNote(id: id, title: "v1"))
        try repo.save(makeNote(id: id, title: "v2", status: .failed))

        XCTAssertEqual(try repo.allNotes().count, 1)
        let fetched = try XCTUnwrap(try repo.note(id: id))
        XCTAssertEqual(fetched.recording.title, "v2")
        XCTAssertEqual(fetched.recording.status, .failed)
    }

    func testUpdateActionItems() throws {
        let id = UUID()
        try repo.save(makeNote(id: id, actionItems: [ActionItem(text: "todo", done: false)]))

        let updated = [ActionItem(text: "todo", done: true), ActionItem(text: "extra")]
        try repo.updateActionItems(recordingId: id, items: updated)

        let summary = try XCTUnwrap(try repo.note(id: id)?.summary)
        XCTAssertEqual(summary.actionItems.count, 2)
        XCTAssertTrue(summary.actionItems[0].done)
        XCTAssertEqual(summary.actionItems[1].text, "extra")
    }

    func testUpdateActionItemsOnMissingNoteIsNoOp() throws {
        XCTAssertNoThrow(try repo.updateActionItems(recordingId: UUID(), items: [ActionItem(text: "x")]))
        XCTAssertTrue(try repo.allNotes().isEmpty)
    }

    // MARK: - Delete + cascade

    func testDeleteRemovesNote() throws {
        let id = UUID()
        try repo.save(makeNote(id: id))
        try repo.delete(recordingId: id)
        XCTAssertNil(try repo.note(id: id))
        XCTAssertTrue(try repo.allNotes().isEmpty)
    }

    func testDeleteMissingIsNoOp() throws {
        try repo.save(makeNote())
        XCTAssertNoThrow(try repo.delete(recordingId: UUID()))
        XCTAssertEqual(try repo.allNotes().count, 1)
    }

    func testDeleteCascadesSummaryEntity() throws {
        let id = UUID()
        try repo.save(makeNote(id: id))
        try repo.delete(recordingId: id)

        // The cascade rule should remove the orphaned SummaryEntity too.
        let summaryDescriptor = FetchDescriptor<SummaryEntity>()
        let remaining = try repo.container.mainContext.fetch(summaryDescriptor)
        XCTAssertTrue(remaining.isEmpty, "SummaryEntity should be cascade-deleted with its Recording")
    }

    func testDeleteOneLeavesOthers() throws {
        let keep = UUID()
        let drop = UUID()
        try repo.save(makeNote(id: keep, title: "keep"))
        try repo.save(makeNote(id: drop, title: "drop"))
        try repo.delete(recordingId: drop)
        let notes = try repo.allNotes()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.recording.title, "keep")
    }

    // MARK: - Container injection initializer

    func testInitWithInjectedContainer() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RecordingEntity.self, SummaryEntity.self, configurations: config)
        let injected = NoteRepository(container: container)
        try injected.save(makeNote(title: "injected"))
        XCTAssertEqual(try injected.allNotes().first?.recording.title, "injected")
    }

    // MARK: - Entity ↔ domain mapping

    func testEntityDomainRoundTripForAllSources() throws {
        for source in Recording.Source.allCases {
            let recording = Recording(title: "s", source: source)
            let entity = RecordingEntity(domain: recording)
            XCTAssertEqual(entity.asDomain.source, source)
        }
    }

    func testEntityUnknownSourceFallsBackToOther() {
        let entity = RecordingEntity(id: UUID(), title: "x", createdAt: Date(), durationSec: 0,
                                     sourceRaw: "garbage", localAudioPath: nil, statusRaw: "ready")
        XCTAssertEqual(entity.asDomain.source, .other)
    }

    func testEntityUnknownStatusFallsBackToReady() {
        let entity = RecordingEntity(id: UUID(), title: "x", createdAt: Date(), durationSec: 0,
                                     sourceRaw: "mic", localAudioPath: nil, statusRaw: "garbage")
        XCTAssertEqual(entity.asDomain.status, .ready)
    }

    func testSummaryEntityDomainRoundTrip() throws {
        let id = UUID()
        let summary = Summary(recordingId: id, style: "detailed", contentMarkdown: "C",
                              actionItems: [ActionItem(text: "x", done: true)], model: "m")
        let entity = try SummaryEntity(domain: summary)
        let back = try entity.asDomain()
        XCTAssertEqual(back.recordingId, id)
        XCTAssertEqual(back.style, "detailed")
        XCTAssertEqual(back.actionItems.count, 1)
        XCTAssertTrue(back.actionItems[0].done)
    }

    // MARK: - Unicode persistence

    func testUnicodeTitleAndContentSurvivePersistence() throws {
        let id = UUID()
        let unicode = "日本語 😀 مرحبا"
        let recording = Recording(id: id, title: unicode, status: .ready)
        let transcript = Transcript(recordingId: id, language: "ja", fullText: unicode, segments: [])
        let summary = Summary(recordingId: id, style: "s", contentMarkdown: unicode,
                              actionItems: [], model: "m")
        try repo.save(Note(recording: recording, transcript: transcript, summary: summary))

        let fetched = try XCTUnwrap(try repo.note(id: id))
        XCTAssertEqual(fetched.recording.title, unicode)
        XCTAssertEqual(fetched.transcript?.fullText, unicode)
        XCTAssertEqual(fetched.summary?.contentMarkdown, unicode)
    }
}
