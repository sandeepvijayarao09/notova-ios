import Foundation

/// Composes a `Transcriber` and a `Summarizer` to turn an audio file into a
/// finished `Note` entirely on-device. Swap the injected stubs for Whisper /
/// Gemma implementations without touching call sites.
public actor PipelineService {
    private let transcriber: Transcriber
    private let summarizer: Summarizer

    public init(transcriber: Transcriber = StubTranscriber(),
                summarizer: Summarizer = StubSummarizer()) {
        self.transcriber = transcriber
        self.summarizer = summarizer
    }

    /// Run transcription + summarization for an already-captured recording.
    /// - Returns: a `Note` with `recording.status == .ready` and populated
    ///   transcript + summary. On failure the returned recording is `.failed`
    ///   and the error is rethrown only for transcription/summarization issues.
    public func process(
        recording: Recording,
        audioURL: URL,
        style: String = "concise"
    ) async throws -> Note {
        var updated = recording
        updated.status = .processing

        do {
            let transcript = try await transcriber.transcribe(
                audioURL: audioURL,
                recordingId: recording.id
            )
            let summary = try await summarizer.summarize(transcript, style: style)
            updated.status = .ready
            return Note(recording: updated, transcript: transcript, summary: summary)
        } catch {
            updated.status = .failed
            throw error
        }
    }
}
