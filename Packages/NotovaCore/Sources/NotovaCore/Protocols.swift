import Foundation

// MARK: - Audio source

/// Describes the result of an audio capture or import operation.
public struct AudioCaptureResult: Sendable {
    public var fileURL: URL
    public var durationSec: Double
    public var source: Recording.Source

    public init(fileURL: URL, durationSec: Double, source: Recording.Source) {
        self.fileURL = fileURL
        self.durationSec = durationSec
        self.source = source
    }
}

/// Abstracts capturing audio (mic / Bluetooth / other input device) or importing
/// from a file. Implementations live in the AudioCapture package.
public protocol AudioSource: Sendable {
    /// Begin a live capture session.
    func start() async throws

    /// Stop a live capture session, returning the recorded file + metadata.
    func stop() async throws -> AudioCaptureResult

    /// Import an existing audio file as a capture result (no recording involved).
    func loadFile(at url: URL) async throws -> AudioCaptureResult
}

// MARK: - Transcription

/// Converts an audio file into a transcript. The shipping implementation is
/// Apple Speech (on-device); see the Transcription package.
public protocol Transcriber: Sendable {
    func transcribe(audioURL: URL, recordingId: UUID) async throws -> Transcript
}

// MARK: - Summarization

/// Produces a markdown summary + action items from a transcript. See the
/// AISummary package for the on-device engines.
public protocol Summarizer: Sendable {
    func summarize(_ transcript: Transcript, style: String) async throws -> Summary
}

// MARK: - Integration export

public protocol IntegrationExporter: Sendable {
    var provider: String { get }
    func export(recordingId: UUID, summary: Summary, transcript: Transcript) async throws -> IntegrationExport
}

// MARK: - Errors

public enum NotovaError: Error, Sendable, Equatable {
    case audioCaptureFailed(String)
    /// No transcription engine can run on this device right now (speech
    /// permission denied, locale not supported on-device, …). The app must
    /// say so instead of inventing a transcript.
    case transcriptionUnavailable(String)
    case transcriptionFailed(String)
    case summarizationFailed(String)
    case exportFailed(String)
    case unsupportedFile(String)
}

extension NotovaError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .audioCaptureFailed(let reason): return "Recording failed: \(reason)"
        case .transcriptionUnavailable(let reason): return "Transcription unavailable: \(reason)"
        case .transcriptionFailed(let reason): return "Transcription failed: \(reason)"
        case .summarizationFailed(let reason): return "Summary failed: \(reason)"
        case .exportFailed(let reason): return "Export failed: \(reason)"
        case .unsupportedFile(let reason): return "Unsupported file: \(reason)"
        }
    }
}
