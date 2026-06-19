import Foundation
import NotovaCore

#if canImport(Speech)
import Speech
#endif

// MARK: - Testable seam

/// A single recognized phrase with timing, decoupled from `SFSpeechRecognition`
/// so the mapping to `Transcript` can be unit-tested without the real engine.
public struct RecognizedSegment: Sendable, Equatable {
    public var text: String
    public var startSec: Double
    public var durationSec: Double

    public init(text: String, startSec: Double, durationSec: Double) {
        self.text = text
        self.startSec = startSec
        self.durationSec = durationSec
    }
}

/// The raw recognition result for an audio file.
public struct RecognitionResult: Sendable, Equatable {
    public var fullText: String
    public var localeIdentifier: String
    public var segments: [RecognizedSegment]

    public init(fullText: String, localeIdentifier: String, segments: [RecognizedSegment]) {
        self.fullText = fullText
        self.localeIdentifier = localeIdentifier
        self.segments = segments
    }
}

/// Seam over Apple's `Speech` framework. Wrapping it lets the `AppleSpeechTranscriber`
/// be tested for availability-gating and `Transcript` mapping without invoking
/// the real on-device recognizer (which needs a device + a real audio file).
public protocol SpeechRecognitionBackend: Sendable {
    /// Whether on-device recognition can run right now (authorized + supported).
    func isAvailable() async -> Bool
    /// Recognize an audio file entirely on-device.
    func recognize(audioURL: URL) async throws -> RecognitionResult
}

// MARK: - AppleSpeechTranscriber

/// On-device transcriber backed by Apple's `Speech` framework (`SFSpeechRecognizer`
/// with `requiresOnDeviceRecognition = true`). Works on iOS 17+. Availability
/// depends on speech-recognition authorization and on-device support for the
/// locale; where unavailable the resolver falls through to the stub.
public struct AppleSpeechTranscriber: TranscriptionEngine {
    public let engineName = "Apple Speech (on-device)"
    private let backend: any SpeechRecognitionBackend

    public init(backend: (any SpeechRecognitionBackend)? = nil) {
        self.backend = backend ?? SystemSpeechBackend()
    }

    public func isAvailable() async -> Bool {
        await backend.isAvailable()
    }

    public func transcribe(audioURL: URL, recordingId: UUID) async throws -> Transcript {
        let result = try await backend.recognize(audioURL: audioURL)
        return Self.makeTranscript(from: result, recordingId: recordingId)
    }

    // MARK: - Mapping (pure, testable)

    static func makeTranscript(from result: RecognitionResult, recordingId: UUID) -> Transcript {
        let segments = result.segments.map { segment in
            TranscriptSegment(
                startMs: Int((segment.startSec * 1000).rounded()),
                endMs: Int(((segment.startSec + segment.durationSec) * 1000).rounded()),
                text: segment.text,
                speaker: nil
            )
        }
        let language = String(result.localeIdentifier.prefix(2)).lowercased()
        return Transcript(
            recordingId: recordingId,
            language: language.isEmpty ? "en" : language,
            fullText: result.fullText,
            segments: segments
        )
    }
}

// MARK: - Whisper integration point
//
// Local Whisper (whisper.cpp / Core ML) is out of scope for now. To add it, make
// a `WhisperTranscriber: TranscriptionEngine` here, report availability when a
// Whisper model is present in the ModelStore, and insert it ahead of
// `AppleSpeechTranscriber` in `TranscriptionService.defaultEngines`.

// MARK: - System-backed Speech backend

/// Real backend over `SFSpeechRecognizer`. Guarded with `canImport(Speech)` so
/// the package compiles even where the framework is absent.
struct SystemSpeechBackend: SpeechRecognitionBackend {
    let localeIdentifier: String

    init(localeIdentifier: String = Locale.current.identifier) {
        self.localeIdentifier = localeIdentifier
    }

    func isAvailable() async -> Bool {
        #if canImport(Speech)
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            return false
        }
        let status = await Self.requestAuthorization()
        return status == .authorized
        #else
        return false
        #endif
    }

    func recognize(audioURL: URL) async throws -> RecognitionResult {
        #if canImport(Speech)
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.supportsOnDeviceRecognition else {
            throw NotovaError.transcriptionFailed("On-device speech recognition unavailable")
        }
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            let resumed = Resumed()
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if resumed.set() {
                        continuation.resume(throwing: NotovaError.transcriptionFailed(error.localizedDescription))
                    }
                    return
                }
                guard let result, result.isFinal else { return }
                let best = result.bestTranscription
                let segments = best.segments.map { seg in
                    RecognizedSegment(text: seg.substring, startSec: seg.timestamp, durationSec: seg.duration)
                }
                if resumed.set() {
                    continuation.resume(returning: RecognitionResult(
                        fullText: best.formattedString,
                        localeIdentifier: recognizer.locale.identifier,
                        segments: segments
                    ))
                }
            }
        }
        #else
        throw NotovaError.transcriptionFailed("Speech framework unavailable")
        #endif
    }

    #if canImport(Speech)
    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    #endif
}

/// Guards a checked continuation against double-resume from the recognition
/// callback (which may fire more than once).
private final class Resumed: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func set() -> Bool {
        lock.withLock {
            if done { return false }
            done = true
            return true
        }
    }
}
