import Foundation
import NotovaCore

/// A `Transcriber` that picks the first AVAILABLE `TranscriptionEngine` from an
/// ordered chain at call time, and records which engine handled the request.
///
/// Default chain: Apple Speech (on-device). There is deliberately no "always
/// available" fallback: if no engine can run, `transcribe` throws
/// `NotovaError.transcriptionUnavailable` and the UI says so.
public actor ResolvingTranscriber: Transcriber {
    private let engines: [any TranscriptionEngine]
    private var lastResolution: EngineResolution

    public init(engines: [any TranscriptionEngine]) {
        precondition(!engines.isEmpty, "ResolvingTranscriber needs at least one engine")
        self.engines = engines
        self.lastResolution = EngineResolution(
            candidates: engines.map { .init(name: $0.engineName, available: false) }
        )
    }

    /// Shown when no engine in the chain can run.
    public static let unavailableReason =
        "allow Speech Recognition for Notova in Settings, and use a language your device supports on-device."

    /// The result of the most recent resolution. Read by Settings.
    public var resolution: EngineResolution { lastResolution }

    /// Probe availability across the chain WITHOUT transcribing, returning (and
    /// caching) which engine would currently handle a request. Used by Settings.
    @discardableResult
    public func previewResolution() async -> EngineResolution {
        var candidates: [EngineResolution.Candidate] = []
        var active: String?
        for engine in engines {
            let available = await engine.isAvailable()
            candidates.append(.init(name: engine.engineName, available: available))
            if available, active == nil { active = engine.engineName }
        }
        lastResolution = EngineResolution(activeEngineName: active, candidates: candidates)
        return lastResolution
    }

    public func transcribe(audioURL: URL, recordingId: UUID) async throws -> Transcript {
        var candidates: [EngineResolution.Candidate] = []
        var availableEngines: [any TranscriptionEngine] = []
        for engine in engines {
            let available = await engine.isAvailable()
            candidates.append(.init(name: engine.engineName, available: available))
            if available { availableEngines.append(engine) }
        }

        // Try each available engine in priority order. If one reports available
        // but fails at runtime (e.g. Apple Speech with no on-device assets, an
        // unsupported locale, or the simulator's speech service), fall back to
        // the next instead of failing.
        var lastError: Error?
        for engine in availableEngines {
            do {
                let transcript = try await engine.transcribe(audioURL: audioURL, recordingId: recordingId)
                lastResolution = EngineResolution(activeEngineName: engine.engineName, candidates: candidates)
                return transcript
            } catch {
                lastError = error
            }
        }

        lastResolution = EngineResolution(activeEngineName: nil, candidates: candidates)
        if let notovaError = lastError as? NotovaError { throw notovaError }
        if let lastError { throw NotovaError.transcriptionFailed(lastError.localizedDescription) }
        throw NotovaError.transcriptionUnavailable(Self.unavailableReason)
    }
}
