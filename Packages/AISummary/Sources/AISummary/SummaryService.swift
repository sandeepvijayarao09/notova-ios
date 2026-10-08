import Foundation
import NotovaCore
import ModelManagement

/// Factory for the on-device summarizer. `makeDefault()` returns the basic
/// extractive summarizer; `makeResolving(store:)` returns a
/// `ResolvingSummarizer` that prefers Local Gemma (MLX) → Apple Foundation
/// Models → basic extractive summary, choosing the first available engine at
/// call time. The basic summary only quotes the transcript and is labelled as
/// "no AI model", so the fallback never invents content.
public enum SummaryService {
    /// The always-available basic extractive summarizer.
    public static func makeDefault() -> any Summarizer {
        StubSummarizer()
    }

    /// The full engine chain, highest priority first. The basic summarizer is
    /// last so a transcript always gets at least an extractive summary.
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
