import XCTest
@testable import NotovaCore

final class PipelineServiceTests: XCTestCase {

    // MARK: - Success path with stubs

    func testProcessProducesReadyNoteWithStubs() async throws {
        let pipeline = PipelineService()
        let recording = Recording(title: "Test", source: .mic)
        let dummyURL = URL(fileURLWithPath: "/tmp/notova-test.m4a")

        let note = try await pipeline.process(recording: recording, audioURL: dummyURL, style: "concise")

        XCTAssertEqual(note.recording.status, .ready)
        XCTAssertEqual(note.recording.id, recording.id)
        XCTAssertEqual(note.recording.title, "Test")

        let transcript = try XCTUnwrap(note.transcript)
        XCTAssertEqual(transcript.recordingId, recording.id)
        XCTAssertFalse(transcript.fullText.isEmpty)
        XCTAssertFalse(transcript.segments.isEmpty)

        let summary = try XCTUnwrap(note.summary)
        XCTAssertEqual(summary.recordingId, recording.id)
        XCTAssertEqual(summary.style, "concise")
        XCTAssertEqual(summary.model, StubSummarizer.modelName)
        XCTAssertTrue(summary.contentMarkdown.contains("Summary"))
    }

    func testProcessDefaultStyleIsConcise() async throws {
        let pipeline = PipelineService()
        let note = try await pipeline.process(
            recording: Recording(title: "x"),
            audioURL: URL(fileURLWithPath: "/tmp/x.m4a")
        )
        XCTAssertEqual(note.summary?.style, "concise")
    }

    func testActionItemExtractionFindsActionVerbs() async throws {
        let pipeline = PipelineService()
        let note = try await pipeline.process(
            recording: Recording(title: "Actions", source: .file),
            audioURL: URL(fileURLWithPath: "/tmp/x.m4a")
        )
        let summary = try XCTUnwrap(note.summary)
        XCTAssertFalse(summary.actionItems.isEmpty)
        XCTAssertTrue(summary.actionItems.allSatisfy { !$0.done })
    }

    // MARK: - Fakes that record inputs / return canned output

    func testProcessPassesAudioURLAndRecordingIdToTranscriber() async throws {
        let recorder = RecordingTranscriber()
        let pipeline = PipelineService(transcriber: recorder, summarizer: StubSummarizer())
        let recording = Recording(title: "Probe", source: .mic)
        let url = URL(fileURLWithPath: "/tmp/probe.m4a")

        _ = try await pipeline.process(recording: recording, audioURL: url)

        let calls = await recorder.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.url, url)
        XCTAssertEqual(calls.first?.recordingId, recording.id)
    }

    func testProcessPassesTranscriptAndStyleToSummarizer() async throws {
        let cannedTranscript = Transcript(recordingId: UUID(), language: "fr", fullText: "Bonjour.", segments: [])
        let transcriber = CannedTranscriber(transcript: cannedTranscript)
        let summarizer = RecordingSummarizer()
        let pipeline = PipelineService(transcriber: transcriber, summarizer: summarizer)

        _ = try await pipeline.process(
            recording: Recording(title: "x"),
            audioURL: URL(fileURLWithPath: "/tmp/x.m4a"),
            style: "bullet"
        )

        let calls = await summarizer.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.style, "bullet")
        XCTAssertEqual(calls.first?.transcript.fullText, "Bonjour.")
        XCTAssertEqual(calls.first?.transcript.language, "fr")
    }

    func testProcessReturnsCannedSummary() async throws {
        let recId = UUID()
        let canned = Summary(recordingId: recId, style: "canned", contentMarkdown: "CANNED",
                             actionItems: [ActionItem(text: "a")], model: "fake-model")
        let pipeline = PipelineService(
            transcriber: CannedTranscriber(transcript: Transcript(recordingId: recId, language: "en",
                                                                  fullText: "x", segments: [])),
            summarizer: CannedSummarizer(summary: canned)
        )
        let note = try await pipeline.process(recording: Recording(id: recId, title: "x"),
                                              audioURL: URL(fileURLWithPath: "/tmp/x"))
        XCTAssertEqual(note.summary?.contentMarkdown, "CANNED")
        XCTAssertEqual(note.summary?.model, "fake-model")
    }

    // MARK: - Failure propagation

    func testProcessPropagatesTranscriptionFailure() async {
        let pipeline = PipelineService(transcriber: FailingTranscriber(), summarizer: StubSummarizer())
        do {
            _ = try await pipeline.process(recording: Recording(title: "Fail"),
                                           audioURL: URL(fileURLWithPath: "/tmp/x.m4a"))
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error as? NotovaError, .transcriptionFailed("boom"))
        }
    }

    func testTranscriberFailureDoesNotCallSummarizer() async {
        let summarizer = RecordingSummarizer()
        let pipeline = PipelineService(transcriber: FailingTranscriber(), summarizer: summarizer)
        _ = try? await pipeline.process(recording: Recording(title: "x"),
                                        audioURL: URL(fileURLWithPath: "/tmp/x"))
        let calls = await summarizer.calls
        XCTAssertTrue(calls.isEmpty, "summarizer must not run when transcription fails")
    }

    func testProcessPropagatesSummarizationFailure() async {
        let pipeline = PipelineService(transcriber: StubTranscriber(), summarizer: FailingSummarizer())
        do {
            _ = try await pipeline.process(recording: Recording(title: "x"),
                                           audioURL: URL(fileURLWithPath: "/tmp/x"))
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(error as? NotovaError, .summarizationFailed("nope"))
        }
    }

    /// The contract documents `status == .failed` on failure. Since `process`
    /// rethrows rather than returning the failed recording, we observe the
    /// status mutation via a transcriber that captures it through the recording
    /// id and a status-observing summarizer is unnecessary; instead we assert
    /// the thrown error path leaves no partial Note returned.
    func testFailedProcessReturnsNoNote() async {
        let pipeline = PipelineService(transcriber: FailingTranscriber(), summarizer: StubSummarizer())
        var produced: Note?
        do {
            produced = try await pipeline.process(recording: Recording(title: "x"),
                                                  audioURL: URL(fileURLWithPath: "/tmp/x"))
        } catch {
            // expected
        }
        XCTAssertNil(produced)
    }

    // MARK: - Empty / whitespace transcripts

    func testEmptyTranscriptProducesSummaryWithNoActionItems() async throws {
        let empty = Transcript(recordingId: UUID(), language: "en", fullText: "", segments: [])
        let pipeline = PipelineService(transcriber: CannedTranscriber(transcript: empty),
                                       summarizer: StubSummarizer())
        let note = try await pipeline.process(recording: Recording(title: "x"),
                                              audioURL: URL(fileURLWithPath: "/tmp/x"))
        let summary = try XCTUnwrap(note.summary)
        XCTAssertTrue(summary.actionItems.isEmpty)
        XCTAssertEqual(note.recording.status, .ready)
    }

    func testWhitespaceOnlyTranscriptProducesNoActionItems() async throws {
        let ws = Transcript(recordingId: UUID(), language: "en",
                            fullText: "   \n\t  \n   ", segments: [])
        let pipeline = PipelineService(transcriber: CannedTranscriber(transcript: ws),
                                       summarizer: StubSummarizer())
        let note = try await pipeline.process(recording: Recording(title: "x"),
                                              audioURL: URL(fileURLWithPath: "/tmp/x"))
        XCTAssertTrue(try XCTUnwrap(note.summary).actionItems.isEmpty)
    }

    // MARK: - Concurrency / isolation

    func testConcurrentPipelinesViaAsyncLetPreserveIdentity() async throws {
        let pipeline = PipelineService()
        let r1 = Recording(title: "one", source: .mic)
        let r2 = Recording(title: "two", source: .file)
        let url = URL(fileURLWithPath: "/tmp/x.m4a")

        async let n1 = pipeline.process(recording: r1, audioURL: url, style: "concise")
        async let n2 = pipeline.process(recording: r2, audioURL: url, style: "detailed")
        let (note1, note2) = try await (n1, n2)

        XCTAssertEqual(note1.recording.id, r1.id)
        XCTAssertEqual(note2.recording.id, r2.id)
        XCTAssertEqual(note1.summary?.style, "concise")
        XCTAssertEqual(note2.summary?.style, "detailed")
        XCTAssertEqual(note1.transcript?.recordingId, r1.id)
        XCTAssertEqual(note2.transcript?.recordingId, r2.id)
    }

    func testManyConcurrentPipelinesViaTaskGroupIsolated() async throws {
        let pipeline = PipelineService()
        let recordings = (0..<50).map { Recording(title: "rec-\($0)", source: .mic) }
        let url = URL(fileURLWithPath: "/tmp/x.m4a")

        let notes = try await withThrowingTaskGroup(of: Note.self) { group -> [Note] in
            for recording in recordings {
                group.addTask { try await pipeline.process(recording: recording, audioURL: url) }
            }
            var collected: [Note] = []
            for try await note in group { collected.append(note) }
            return collected
        }

        XCTAssertEqual(notes.count, 50)
        // Each note's transcript/summary must reference its own recording id —
        // no cross-talk between concurrent runs.
        for note in notes {
            XCTAssertEqual(note.transcript?.recordingId, note.recording.id)
            XCTAssertEqual(note.summary?.recordingId, note.recording.id)
            XCTAssertEqual(note.recording.status, .ready)
        }
        XCTAssertEqual(Set(notes.map(\.recording.id)), Set(recordings.map(\.id)))
    }
}

// MARK: - Test doubles

private struct FailingTranscriber: Transcriber {
    func transcribe(audioURL: URL, recordingId: UUID) async throws -> Transcript {
        throw NotovaError.transcriptionFailed("boom")
    }
}

private struct FailingSummarizer: Summarizer {
    func summarize(_ transcript: Transcript, style: String) async throws -> Summary {
        throw NotovaError.summarizationFailed("nope")
    }
}

private struct CannedTranscriber: Transcriber {
    let transcript: Transcript
    func transcribe(audioURL: URL, recordingId: UUID) async throws -> Transcript { transcript }
}

private struct CannedSummarizer: Summarizer {
    let summary: Summary
    func summarize(_ transcript: Transcript, style: String) async throws -> Summary { summary }
}

/// Records every transcribe() invocation for later assertions.
private actor RecordingTranscriber: Transcriber {
    struct Call: Sendable { let url: URL; let recordingId: UUID }
    private(set) var calls: [Call] = []

    func transcribe(audioURL: URL, recordingId: UUID) async throws -> Transcript {
        calls.append(Call(url: audioURL, recordingId: recordingId))
        return Transcript(recordingId: recordingId, language: "en", fullText: "recorded", segments: [])
    }
}

/// Records every summarize() invocation for later assertions.
private actor RecordingSummarizer: Summarizer {
    struct Call: Sendable { let transcript: Transcript; let style: String }
    private(set) var calls: [Call] = []

    func summarize(_ transcript: Transcript, style: String) async throws -> Summary {
        calls.append(Call(transcript: transcript, style: style))
        return Summary(recordingId: transcript.recordingId, style: style, contentMarkdown: "",
                       actionItems: [], model: "recording-summarizer")
    }
}
