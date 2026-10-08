import Foundation

// MARK: - StubTranscriber

/// Test double. Returns a fixed, obviously synthetic transcript so pipeline and
/// summarizer tests have deterministic input. It is NOT part of any production
/// engine chain: when no real engine can run, the app reports
/// `NotovaError.transcriptionUnavailable` instead of showing made-up text.
public struct StubTranscriber: Transcriber {
    public init() {}

    public func transcribe(audioURL: URL, recordingId: UUID) async throws -> Transcript {
        let sentences = [
            "Welcome to Notova, this is a stub transcript.",
            "We need to follow up with the design team next week.",
            "Please send the updated budget by Friday.",
            "The on-device model will replace this placeholder soon."
        ]
        var segments: [TranscriptSegment] = []
        var cursorMs = 0
        for sentence in sentences {
            let durationMs = max(1500, sentence.count * 60)
            segments.append(
                TranscriptSegment(
                    startMs: cursorMs,
                    endMs: cursorMs + durationMs,
                    text: sentence,
                    speaker: "Speaker 1"
                )
            )
            cursorMs += durationMs
        }
        return Transcript(
            recordingId: recordingId,
            language: "en",
            fullText: sentences.joined(separator: " "),
            segments: segments
        )
    }
}

// MARK: - StubSummarizer

/// Basic extractive summarizer, used when no on-device AI model is available.
/// It never invents content: key points are the first sentences of the real
/// transcript, and action items are transcript sentences containing an action
/// verb. The summary says plainly that no AI model produced it.
public struct StubSummarizer: Summarizer {
    public static let modelName = "basic-extractive-v1"

    /// Verbs that mark a sentence as a likely action item.
    public static let actionVerbs: Set<String> = [
        "follow", "send", "schedule", "review", "email", "call",
        "prepare", "update", "share", "complete", "finish", "create",
        "draft", "remind", "book", "confirm", "submit"
    ]

    public init() {}

    public func summarize(_ transcript: Transcript, style: String) async throws -> Summary {
        let sentences = Self.splitSentences(transcript.fullText)
        let actionItems = Self.extractActionItems(from: sentences)

        var markdown = "## Summary (\(style))\n\n"
        markdown += "_Basic summary: no on-device AI model was available, so these are sentences taken from the transcript._\n\n"
        if let first = sentences.first {
            markdown += "**Overview:** \(first)\n\n"
        }
        markdown += "### Key points\n"
        for sentence in sentences.prefix(3) {
            markdown += "- \(sentence)\n"
        }
        if !actionItems.isEmpty {
            markdown += "\n### Action items\n"
            for item in actionItems {
                markdown += "- [ ] \(item.text)\n"
            }
        }

        return Summary(
            recordingId: transcript.recordingId,
            style: style,
            contentMarkdown: markdown,
            actionItems: actionItems,
            model: Self.modelName
        )
    }

    public static func splitSentences(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func extractActionItems(from sentences: [String]) -> [ActionItem] {
        sentences.compactMap { sentence in
            let words = sentence.lowercased().split(whereSeparator: { !$0.isLetter })
            let hasVerb = words.contains { actionVerbs.contains(String($0)) }
            guard hasVerb else { return nil }
            return ActionItem(text: sentence)
        }
    }
}

// MARK: - Stub engine conformances

/// The basic summarizer is always available, so it is the last link in the
/// summarizer chain. The test transcriber conforms so resolver tests can use
/// it, but it is never registered in the app.
extension StubTranscriber: TranscriptionEngine {
    public var engineName: String { "Test fixture transcriber" }
    public func isAvailable() async -> Bool { true }
}

extension StubSummarizer: SummarizationEngine {
    public var engineName: String { "Basic summary (no AI model)" }
    public func isAvailable() async -> Bool { true }
}
