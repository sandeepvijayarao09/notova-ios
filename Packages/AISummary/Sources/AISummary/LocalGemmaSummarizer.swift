import Foundation
import NotovaCore
import ModelManagement

#if NOTOVA_ENABLE_MLX && canImport(MLXLLM)
import MLX
import MLXLLM
import MLXLMCommon
#endif

// MARK: - LocalGemmaSummarizer

/// On-device summarizer that runs a Gemma model via MLX, loaded from the app's
/// models directory.
///
/// MLX inference is Metal-only (real Apple-silicon devices). To guarantee the
/// package always compiles and the app always builds — including in the
/// simulator and CI where MLX/Metal isn't available — the heavy MLX code path is
/// gated behind the `NOTOVA_ENABLE_MLX` compile flag *and* `canImport(MLXLLM)`.
///
/// Availability is twofold:
///  1. an MLX Gemma model must be present in the `ModelStore` (capability
///     `.localGemmaMLX`), and
///  2. the MLX runtime must be compiled in.
///
/// When either is missing, `isAvailable()` returns `false` and the resolver
/// falls through to the next engine. The model presence check is real and runs
/// everywhere, so this engine is correctly *selected* once a model is installed
/// on a capable device.
public struct LocalGemmaSummarizer: SummarizationEngine {
    public let engineName = "Local Gemma (MLX)"
    private let store: ModelStore

    public init(store: ModelStore) {
        self.store = store
    }

    /// True only when an MLX Gemma model is installed AND the MLX runtime is
    /// compiled in. The model check works on every platform.
    public func isAvailable() async -> Bool {
        guard store.hasCapability(.localGemmaMLX) else { return false }
        return Self.mlxRuntimeCompiledIn
    }

    public func summarize(_ transcript: Transcript, style: String) async throws -> Summary {
        guard let model = store.model(for: .localGemmaMLX) else {
            throw NotovaError.summarizationFailed("No local Gemma model installed")
        }
        let raw = try await Self.runInference(
            modelDirectory: model.url,
            prompt: Self.buildPrompt(transcript: transcript, style: style)
        )
        // Reuse the Foundation-Models parsing so output mapping is consistent.
        return AppleFoundationModelsSummarizer.makeSummary(from: raw, transcript: transcript, style: style)
            .with(model: "local-gemma-mlx")
    }

    static func buildPrompt(transcript: Transcript, style: String) -> String {
        AppleFoundationModelsSummarizer.buildPrompt(transcript: transcript, style: style)
    }

    // MARK: - MLX integration point

    /// Whether the MLX runtime is compiled into this build.
    static var mlxRuntimeCompiledIn: Bool {
        #if NOTOVA_ENABLE_MLX && canImport(MLXLLM)
        return true
        #else
        return false
        #endif
    }

    /// Run Gemma inference via MLX. Compiled only when MLX is available; otherwise
    /// throws so the resolver never reaches here without a runtime.
    static func runInference(modelDirectory: URL, prompt: String) async throws -> String {
        #if NOTOVA_ENABLE_MLX && canImport(MLXLLM)
        // INTEGRATION POINT (device/Metal only): load the model container from the
        // on-disk MLX Gemma directory and generate. Kept minimal and behind the
        // flag so the default build never links MLX.
        let configuration = ModelConfiguration(directory: modelDirectory)
        let container = try await LLMModelFactory.shared.loadContainer(configuration: configuration)
        let result = try await container.perform { context in
            let input = try await context.processor.prepare(input: .init(prompt: prompt))
            return try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(temperature: 0.6),
                context: context
            ) { _ in .more }
        }
        return result.output
        #else
        throw NotovaError.summarizationFailed("MLX runtime not compiled in")
        #endif
    }
}

private extension Summary {
    func with(model: String) -> Summary {
        Summary(
            recordingId: recordingId,
            style: style,
            contentMarkdown: contentMarkdown,
            actionItems: actionItems,
            model: model,
            generatedAt: generatedAt
        )
    }
}
