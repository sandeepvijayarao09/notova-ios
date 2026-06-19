import Foundation
import NotovaCore

/// Factory for the on-device transcriber. `makeDefault()` returns the always-on
/// stub (kept for existing call sites/tests); `makeResolving()` returns a
/// `ResolvingTranscriber` that prefers Apple Speech (on-device) → stub, choosing
/// the first available engine at call time.
public enum TranscriptionService {
    /// The always-available baseline transcriber.
    public static func makeDefault() -> any Transcriber {
        StubTranscriber()
    }

    /// The full engine chain, highest priority first. The stub is last so
    /// transcription always succeeds.
    public static func defaultEngines() -> [any TranscriptionEngine] {
        [
            AppleSpeechTranscriber(),
            StubTranscriber()
        ]
    }

    /// A resolver over the default engine chain.
    public static func makeResolving() -> ResolvingTranscriber {
        ResolvingTranscriber(engines: defaultEngines())
    }
}
