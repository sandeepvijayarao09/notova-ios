import Foundation
import NotovaCore
import ModelManagement

/// Factory for the on-device summarizer. `makeDefault()` returns the always-on
/// stub (kept for existing call sites/tests); `makeResolving(store:)` returns a
/// `ResolvingSummarizer` that prefers Local Gemma (MLX) → Apple Foundation
/// Models → stub, choosing the first available engine at call time.
public enum SummaryService {
    /// The always-available baseline summarizer.
    public static func makeDefault() -> any Summarizer {
        StubSummarizer()
    }

    /// The full engine chain, highest priority first. The stub is last so
    /// summarization always succeeds.
    public static func defaultEngines(store: ModelStore) -> [any SummarizationEngine] {
        [
            LocalGemmaSummarizer(store: store),
            AppleFoundationModelsSummarizer(),
            StubSummarizer()
        ]
    }

    /// A resolver over the default engine chain.
    public static func makeResolving(store: ModelStore) -> ResolvingSummarizer {
        ResolvingSummarizer(engines: defaultEngines(store: store))
    }
}
