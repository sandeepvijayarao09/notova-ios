import Foundation

// MARK: - Engine availability

/// A concrete summarization backend that can report whether it is usable in the
/// current environment (model present, OS/hardware capable, …) before it is
/// asked to do work. Lets a resolver pick the best available engine at call time.
public protocol SummarizationEngine: Summarizer {
    /// Human-readable name shown in Settings (e.g. "Apple Foundation Models").
    var engineName: String { get }

    /// Whether this engine can run right now. Cheap to call; must not perform
    /// inference. Heavy/optional engines (MLX, Apple Intelligence) return
    /// `false` where unavailable so the resolver falls through to the next one.
    func isAvailable() async -> Bool
}

/// A concrete transcription backend with the same availability contract as
/// ``SummarizationEngine``.
public protocol TranscriptionEngine: Transcriber {
    var engineName: String { get }
    func isAvailable() async -> Bool
}

// MARK: - Resolution result

/// Records which engine handled the most recent request, and why a given engine
/// was or wasn't chosen. Surfaced in Settings so users can see what ran.
public struct EngineResolution: Sendable, Hashable {
    /// The engine that handled the request (or `nil` before the first call).
    public var activeEngineName: String?
    /// Ordered diagnostics: each engine in the chain and whether it was available.
    public var candidates: [Candidate]

    public struct Candidate: Sendable, Hashable, Identifiable {
        public var name: String
        public var available: Bool
        public var id: String { name }

        public init(name: String, available: Bool) {
            self.name = name
            self.available = available
        }
    }

    public init(activeEngineName: String? = nil, candidates: [Candidate] = []) {
        self.activeEngineName = activeEngineName
        self.candidates = candidates
    }
}
