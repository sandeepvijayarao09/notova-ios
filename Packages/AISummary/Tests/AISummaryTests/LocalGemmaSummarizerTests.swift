import XCTest
import NotovaCore
import ModelManagement
@testable import AISummary

final class LocalGemmaSummarizerTests: XCTestCase {
    private var tempDir: URL!
    private var store: ModelStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalGemmaTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = ModelStore(directory: tempDir.appendingPathComponent("Models"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func installGemmaModel() throws {
        try store.ensureDirectory()
        let dir = store.modelsDirectory.appendingPathComponent("gemma-2b-it-mlx", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: dir.appendingPathComponent("config.json"))
        try Data("w".utf8).write(to: dir.appendingPathComponent("model.safetensors"))
    }

    func testEngineNameStable() {
        XCTAssertEqual(LocalGemmaSummarizer(store: store).engineName, "Local Gemma (MLX)")
    }

    func testUnavailableWithNoModel() async {
        let engine = LocalGemmaSummarizer(store: store)
        let available = await engine.isAvailable()
        XCTAssertFalse(available, "must be unavailable with no Gemma model installed")
    }

    func testAvailabilityRequiresBothModelAndRuntime() async throws {
        try installGemmaModel()
        let engine = LocalGemmaSummarizer(store: store)
        let available = await engine.isAvailable()
        // The model IS present, so availability reflects whether MLX is compiled in.
        // In the default (no-MLX) build that's false; with NOTOVA_ENABLE_MLX it's true.
        XCTAssertEqual(available, LocalGemmaSummarizer.mlxRuntimeCompiledIn)
        XCTAssertTrue(store.hasCapability(.localGemmaMLX), "the model should be detected regardless of runtime")
    }

    func testSummarizeThrowsWithoutModel() async {
        let engine = LocalGemmaSummarizer(store: store)
        do {
            _ = try await engine.summarize(
                Transcript(recordingId: UUID(), language: "en", fullText: "x", segments: []), style: "s"
            )
            XCTFail("expected failure")
        } catch {
            XCTAssertTrue(error is NotovaError)
        }
    }

    func testPromptDelegatesToFoundationModelsBuilder() {
        let transcript = Transcript(recordingId: UUID(), language: "en", fullText: "Hello there.", segments: [])
        let prompt = LocalGemmaSummarizer.buildPrompt(transcript: transcript, style: "concise")
        XCTAssertEqual(prompt, AppleFoundationModelsSummarizer.buildPrompt(transcript: transcript, style: "concise"))
    }
}
