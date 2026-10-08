import Foundation
import NotovaCore

/// Factory for the on-device transcriber: a `ResolvingTranscriber` over the
/// real engines, highest priority first. There is no stub in the chain, so a
/// device with no usable engine gets an explicit "unavailable" error rather
/// than placeholder text.
public enum TranscriptionService {
    /// The default transcriber (same as `makeResolving()`).
    public static func makeDefault() -> any Transcriber {
        makeResolving()
    }

    /// The full engine chain, highest priority first.
    public static func defaultEngines() -> [any TranscriptionEngine] {
        [AppleSpeechTranscriber()]
    }

    /// A resolver over the default engine chain.
    public static func makeResolving() -> ResolvingTranscriber {
        ResolvingTranscriber(engines: defaultEngines())
    }
}
