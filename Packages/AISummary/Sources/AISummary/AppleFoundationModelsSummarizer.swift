import Foundation
import NotovaCore

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Testable seam

/// The raw text a backend produces for a transcript, before it is mapped to a
/// `Summary`. Wrapping the system call behind this protocol lets us unit-test
/// the prompt-building + parsing without invoking the real on-device model.
public protocol FoundationTextGenerator: Sendable {
    /// Whether the underlying model is available right now.
    func isAvailable() async -> Bool
    /// Produce raw summary text (markdown + an "Action items" section) for `prompt`.
    func generate(prompt: String) async throws -> String
}

// MARK: - AppleFoundationModelsSummarizer

/// Summarizer backed by Apple's on-device Foundation Models (Apple Intelligence).
///
/// Available only on iOS 26+ devices where `SystemLanguageModel.default.availability`
/// is `.available` (real hardware with Apple Intelligence enabled). Everywhere
/// else — simulators, older OSes, builds without the framework — `isAvailable()`
/// returns `false` and the resolver falls through. The deployment target stays 17.
public struct AppleFoundationModelsSummarizer: SummarizationEngine {
    public let engineName = "Apple Foundation Models"
    private let generator: any FoundationTextGenerator

    /// Inject a custom generator (tests use a fake). Defaults to the real
    /// system-backed generator.
    public init(generator: (any FoundationTextGenerator)? = nil) {
        self.generator = generator ?? SystemFoundationTextGenerator()
    }

    public func isAvailable() async -> Bool {
        await generator.isAvailable()
    }

    public func summarize(_ transcript: NotovaCore.Transcript, style: String) async throws -> Summary {
        let prompt = Self.buildPrompt(transcript: transcript, style: style)
        let raw = try await generator.generate(prompt: prompt)
        return Self.makeSummary(from: raw, transcript: transcript, style: style)
    }

    // MARK: - Prompt + parsing (pure, testable)

    static func buildPrompt(transcript: NotovaCore.Transcript, style: String) -> String {
        """
        You are an on-device meeting assistant. Summarize the transcript below in a \(style) style.
        Respond in Markdown with a short overview and a "## Key points" bulleted list.
        Then add an "## Action items" section with one "- " bullet per concrete task, or omit it if there are none.

        Transcript:
        \(transcript.fullText)
        """
    }

    /// Map raw model output to a `Summary`. Action items are parsed from bullets
    /// under an "Action items" heading; if none are present we fall back to the
    /// heuristic extractor so the field is still useful.
    static func makeSummary(from raw: String, transcript: NotovaCore.Transcript, style: String) -> Summary {
        let items = parseActionItems(from: raw)
        let finalItems = items.isEmpty
            ? StubSummarizer.extractActionItems(from: StubSummarizer.splitSentences(transcript.fullText))
            : items
        return Summary(
            recordingId: transcript.recordingId,
            style: style,
            contentMarkdown: raw,
            actionItems: finalItems,
            model: "apple-foundation-models"
        )
    }

    /// Extract action-item bullets that appear after an "Action items" heading.
    static func parseActionItems(from markdown: String) -> [ActionItem] {
        let lines = markdown.components(separatedBy: .newlines)
        var inActionSection = false
        var items: [ActionItem] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            if lower.hasPrefix("#"), lower.contains("action item") {
                inActionSection = true
                continue
            }
            // A new heading ends the action-items section.
            if inActionSection, trimmed.hasPrefix("#") {
                inActionSection = false
                continue
            }
            guard inActionSection else { continue }
            if let text = bulletText(trimmed), !text.isEmpty {
                items.append(ActionItem(text: text))
            }
        }
        return items
    }

    private static func bulletText(_ line: String) -> String? {
        for marker in ["- [ ] ", "- [x] ", "- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}

// MARK: - System-backed generator

/// Real generator over `SystemLanguageModel` / `LanguageModelSession`. Guarded so
/// the package compiles and reports unavailable where Foundation Models can't run.
struct SystemFoundationTextGenerator: FoundationTextGenerator {
    func isAvailable() async -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    func generate(prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else {
                throw NotovaError.summarizationFailed("Apple Foundation Models unavailable")
            }
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            return response.content
        }
        #endif
        throw NotovaError.summarizationFailed("Apple Foundation Models unavailable")
    }
}
