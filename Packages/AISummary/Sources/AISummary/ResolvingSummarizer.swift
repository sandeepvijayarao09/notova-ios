import Foundation
import NotovaCore

/// A `Summarizer` that picks the first AVAILABLE `SummarizationEngine` from an
/// ordered chain at call time, and records which engine handled the request.
///
/// Default chain (highest priority first): Local Gemma (MLX) → Apple Foundation
/// Models → built-in stub. The stub is always available, so summarization never
/// fails for lack of an engine.
public actor ResolvingSummarizer: Summarizer {
    private let engines: [any SummarizationEngine]
    private var lastResolution: EngineResolution

    /// - Parameter engines: ordered, highest-priority first. The last engine
    ///   should always be available (e.g. `StubSummarizer`).
    public init(engines: [any SummarizationEngine]) {
        precondition(!engines.isEmpty, "ResolvingSummarizer needs at least one engine")
        self.engines = engines
        self.lastResolution = EngineResolution(
            candidates: engines.map { .init(name: $0.engineName, available: false) }
        )
    }

    /// The result of the most recent resolution (or the chain shape before any
    /// call). Read by Settings to show the active engine + diagnostics.
    public var resolution: EngineResolution { lastResolution }

    /// Probe availability across the chain WITHOUT running inference, returning
    /// (and caching) which engine would currently handle a request. Used by
    /// Settings to display the active engine.
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

    public func summarize(_ transcript: Transcript, style: String) async throws -> Summary {
        var candidates: [EngineResolution.Candidate] = []
        var chosen: (any SummarizationEngine)?

        for engine in engines {
            let available = await engine.isAvailable()
            candidates.append(.init(name: engine.engineName, available: available))
            if available, chosen == nil {
                chosen = engine
            }
        }

        guard let engine = chosen else {
            // Should never happen: the stub is always available.
            lastResolution = EngineResolution(activeEngineName: nil, candidates: candidates)
            throw NotovaError.summarizationFailed("No summarization engine available")
        }

        lastResolution = EngineResolution(activeEngineName: engine.engineName, candidates: candidates)
        return try await engine.summarize(transcript, style: style)
    }
}
