import XCTest
@testable import NotovaCore

final class StubTranscriberTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/x.m4a")

    func testOutputShape() async throws {
        let id = UUID()
        let transcript = try await StubTranscriber().transcribe(audioURL: url, recordingId: id)
        XCTAssertEqual(transcript.recordingId, id)
        XCTAssertEqual(transcript.language, "en")
        XCTAssertFalse(transcript.fullText.isEmpty)
        XCTAssertEqual(transcript.segments.count, 4)
    }

    func testDeterministicAcrossCalls() async throws {
        let id = UUID()
        let a = try await StubTranscriber().transcribe(audioURL: url, recordingId: id)
        let b = try await StubTranscriber().transcribe(audioURL: url, recordingId: id)
        XCTAssertEqual(a, b)
    }

    func testRecordingIdIsThreadedThrough() async throws {
        let id = UUID()
        let transcript = try await StubTranscriber().transcribe(audioURL: url, recordingId: id)
        XCTAssertEqual(transcript.recordingId, id)
    }

    func testSegmentsAreContiguousAndOrdered() async throws {
        let transcript = try await StubTranscriber().transcribe(audioURL: url, recordingId: UUID())
        var prevEnd = 0
        for segment in transcript.segments {
            XCTAssertEqual(segment.startMs, prevEnd, "segments should be contiguous (start == previous end)")
            XCTAssertGreaterThan(segment.endMs, segment.startMs, "segment must have positive duration")
            XCTAssertEqual(segment.speaker, "Speaker 1")
            XCTAssertFalse(segment.text.isEmpty)
            prevEnd = segment.endMs
        }
    }

    func testFullTextIsConcatenationOfSegments() async throws {
        let transcript = try await StubTranscriber().transcribe(audioURL: url, recordingId: UUID())
        let joined = transcript.segments.map(\.text).joined(separator: " ")
        XCTAssertEqual(transcript.fullText, joined)
    }

    func testTranscriptContainsKnownActionSentences() async throws {
        let transcript = try await StubTranscriber().transcribe(audioURL: url, recordingId: UUID())
        XCTAssertTrue(transcript.fullText.lowercased().contains("follow up"))
        XCTAssertTrue(transcript.fullText.lowercased().contains("send"))
    }
}

final class StubSummarizerTests: XCTestCase {

    private func summarize(_ text: String, style: String = "concise") async throws -> Summary {
        let transcript = Transcript(recordingId: UUID(), language: "en", fullText: text, segments: [])
        return try await StubSummarizer().summarize(transcript, style: style)
    }

    // MARK: - Output shape & determinism

    func testModelNameStable() {
        XCTAssertEqual(StubSummarizer.modelName, "stub-summarizer-v1")
    }

    func testOutputShapeAndModelField() async throws {
        let summary = try await summarize("Please send the report. We had a great meeting.")
        XCTAssertEqual(summary.model, StubSummarizer.modelName)
        XCTAssertTrue(summary.contentMarkdown.contains("## Summary (concise)"))
        XCTAssertTrue(summary.contentMarkdown.contains("### Key points"))
    }

    func testStyleIsReflectedInOutput() async throws {
        let summary = try await summarize("Send it.", style: "detailed")
        XCTAssertEqual(summary.style, "detailed")
        XCTAssertTrue(summary.contentMarkdown.contains("## Summary (detailed)"))
    }

    func testDeterministicForSameInput() async throws {
        let text = "Please send the report. Schedule a call with the team."
        let a = try await summarize(text)
        let b = try await summarize(text)
        XCTAssertEqual(a.contentMarkdown, b.contentMarkdown)
        XCTAssertEqual(a.actionItems.map(\.text), b.actionItems.map(\.text))
    }

    func testRecordingIdPropagated() async throws {
        let id = UUID()
        let transcript = Transcript(recordingId: id, language: "en", fullText: "Send it.", segments: [])
        let summary = try await StubSummarizer().summarize(transcript, style: "x")
        XCTAssertEqual(summary.recordingId, id)
    }

    func testSummaryReferencesTranscriptContent() async throws {
        // The overview line should quote the first sentence of the transcript.
        let summary = try await summarize("The quarterly numbers look strong. Send the deck.")
        XCTAssertTrue(summary.contentMarkdown.contains("The quarterly numbers look strong"))
    }

    func testKeyPointsLimitedToThreeSentences() async throws {
        let summary = try await summarize("One. Two. Three. Four. Five.")
        let bulletCount = summary.contentMarkdown
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("- ") && !$0.hasPrefix("- [ ]") }
            .count
        XCTAssertEqual(bulletCount, 3, "key points should be capped at the first 3 sentences")
    }

    // MARK: - Empty / whitespace

    func testEmptyTranscriptYieldsNoActionItems() async throws {
        let summary = try await summarize("")
        XCTAssertTrue(summary.actionItems.isEmpty)
        XCTAssertFalse(summary.contentMarkdown.contains("Action items"))
    }

    func testWhitespaceOnlyYieldsNoActionItems() async throws {
        let summary = try await summarize("   \n  \t  ")
        XCTAssertTrue(summary.actionItems.isEmpty)
    }

    // MARK: - Action-item extraction: positives

    func testExtractsImperativeSendSentence() async throws {
        let summary = try await summarize("Send the updated budget by Friday.")
        XCTAssertEqual(summary.actionItems.count, 1)
        XCTAssertTrue(summary.actionItems[0].text.contains("Send the updated budget by Friday"))
        XCTAssertFalse(summary.actionItems[0].done)
    }

    func testExtractsFollowUp() async throws {
        let summary = try await summarize("We need to follow up with the design team next week.")
        XCTAssertEqual(summary.actionItems.count, 1)
    }

    func testExtractsAcrossManyActionVerbs() async throws {
        // One sentence per verb in StubSummarizer.actionVerbs.
        let verbSentences = [
            "Follow up with sales.",
            "Send the invoice.",
            "Schedule the review.",
            "Review the contract.",
            "Email the client.",
            "Call the vendor.",
            "Prepare the slides.",
            "Update the roadmap.",
            "Share the doc.",
            "Complete the form.",
            "Finish the draft.",
            "Create a ticket.",
            "Draft the announcement.",
            "Remind the team.",
            "Book the room.",
            "Confirm the date.",
            "Submit the report."
        ]
        let text = verbSentences.joined(separator: " ")
        let summary = try await summarize(text)
        XCTAssertEqual(summary.actionItems.count, verbSentences.count,
                       "each action-verb sentence should yield exactly one action item")
    }

    func testMultiSentenceMixedExtractsOnlyActionSentences() async throws {
        let text = "The weather was nice. Please send the agenda. I enjoyed lunch. Schedule a follow-up."
        let summary = try await summarize(text)
        XCTAssertEqual(summary.actionItems.count, 2)
        XCTAssertTrue(summary.actionItems.contains { $0.text.contains("send the agenda") })
        XCTAssertTrue(summary.actionItems.contains { $0.text.contains("Schedule a follow-up") })
    }

    func testBulletListStyleSentencesAreSplitOnPunctuation() async throws {
        // No sentence punctuation between items => treated as one sentence; with
        // periods they split. Verify the period-delimited form extracts each.
        let text = "Send the file. Review the PR. Book the venue."
        let summary = try await summarize(text)
        XCTAssertEqual(summary.actionItems.count, 3)
    }

    func testCaseInsensitiveVerbMatch() async throws {
        let summary = try await summarize("SEND the report. ReViEw it carefully.")
        XCTAssertEqual(summary.actionItems.count, 2)
    }

    func testExclamationAndQuestionDelimitersSplitSentences() async throws {
        let summary = try await summarize("Send it now! Did you review the doc? Call me.")
        // "Send it now" and "Call me" match; "Did you review the doc" contains "review".
        XCTAssertEqual(summary.actionItems.count, 3)
    }

    // MARK: - Action-item extraction: negatives (must NOT match)

    func testNonActionSentencesProduceNoItems() async throws {
        let summary = try await summarize("The sky is blue. It rained yesterday. Lunch was tasty.")
        XCTAssertTrue(summary.actionItems.isEmpty)
    }

    func testSubstringOfVerbDoesNotMatch() async throws {
        // "sender", "callous", "reviewer", "updates" contain action-verb
        // substrings but tokenization is word-based, so they must NOT match.
        let summary = try await summarize("The sender was callous. The reviewer left. Pending updates exist.")
        XCTAssertTrue(summary.actionItems.isEmpty,
                      "word-boundary matching must not fire on substrings like 'sender'/'reviewer'")
    }

    func testPunctuationAndDigitsDoNotCreateFalsePositives() async throws {
        let summary = try await summarize("12345. !!! ... ???")
        XCTAssertTrue(summary.actionItems.isEmpty)
    }

    func testUnicodeNonActionTextProducesNoItems() async throws {
        let summary = try await summarize("日本語のテキストです。emoji 😀 here. مرحبا بالعالم.")
        XCTAssertTrue(summary.actionItems.isEmpty)
    }

    // MARK: - Direct helper coverage

    func testSplitSentencesTrimsAndDropsEmpties() {
        let result = StubSummarizer.splitSentences("  One.   Two!  Three?  ")
        XCTAssertEqual(result, ["One", "Two", "Three"])
    }

    func testSplitSentencesOnEmptyString() {
        XCTAssertTrue(StubSummarizer.splitSentences("").isEmpty)
        XCTAssertTrue(StubSummarizer.splitSentences("   ").isEmpty)
    }

    func testExtractActionItemsDirect() {
        let items = StubSummarizer.extractActionItems(from: ["Send the file", "Nice weather", "Review it"])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.text), ["Send the file", "Review it"])
        XCTAssertTrue(items.allSatisfy { !$0.done })
    }

    func testActionVerbsSetContainsExpectedMembers() {
        XCTAssertTrue(StubSummarizer.actionVerbs.contains("follow"))
        XCTAssertTrue(StubSummarizer.actionVerbs.contains("submit"))
        XCTAssertFalse(StubSummarizer.actionVerbs.contains("the"))
        XCTAssertEqual(StubSummarizer.actionVerbs.count, 17)
    }
}

final class StubIntegrationExporterTests: XCTestCase {
    func testReturnsDoneStatusAndShape() async throws {
        let id = UUID()
        let exporter = StubIntegrationExporter(provider: "myprovider")
        let export = try await exporter.export(
            recordingId: id,
            summary: Summary(recordingId: id, style: "s", contentMarkdown: "c", actionItems: [], model: "m"),
            transcript: Transcript(recordingId: id, language: "en", fullText: "x", segments: [])
        )
        XCTAssertEqual(export.recordingId, id)
        XCTAssertEqual(export.provider, "myprovider")
        XCTAssertEqual(export.status, .done)
        XCTAssertNotNil(export.externalId)
        XCTAssertEqual(export.url, "https://example.com/myprovider/\(id.uuidString)")
    }

    func testDefaultProviderIsStub() {
        XCTAssertEqual(StubIntegrationExporter().provider, "stub")
    }

    func testExternalIdIsAValidUUID() async throws {
        let export = try await StubIntegrationExporter().export(
            recordingId: UUID(),
            summary: Summary(recordingId: UUID(), style: "s", contentMarkdown: "c", actionItems: [], model: "m"),
            transcript: Transcript(recordingId: UUID(), language: "en", fullText: "x", segments: [])
        )
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(export.externalId)))
    }
}
