import XCTest
@testable import ModelManagement

final class ModelStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: ModelStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = ModelStore(directory: tempDir.appendingPathComponent("Models"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Directory

    func testEnsureDirectoryCreatesIt() throws {
        let url = try store.ensureDirectory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testInstalledModelsEmptyWhenNoDirectory() throws {
        XCTAssertTrue(try store.installedModels().isEmpty)
    }

    // MARK: - Import / list / delete

    func testImportFileAppearsInList() throws {
        let source = tempDir.appendingPathComponent("note.gguf")
        try Data("weights".utf8).write(to: source)

        let dest = try store.importModel(from: source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))

        let models = try store.installedModels()
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.name, "note.gguf")
        XCTAssertFalse(models.first!.isDirectory)
        XCTAssertGreaterThan(models.first!.sizeBytes, 0)
    }

    func testImportWithCustomName() throws {
        let source = tempDir.appendingPathComponent("x.gguf")
        try Data("w".utf8).write(to: source)
        try store.importModel(from: source, named: "renamed.gguf")
        XCTAssertEqual(try store.installedModels().first?.name, "renamed.gguf")
    }

    func testImportOverwritesExisting() throws {
        let source = tempDir.appendingPathComponent("a.gguf")
        try Data("one".utf8).write(to: source)
        try store.importModel(from: source, named: "model.gguf")

        let source2 = tempDir.appendingPathComponent("b.gguf")
        try Data("two-longer".utf8).write(to: source2)
        try store.importModel(from: source2, named: "model.gguf")

        let models = try store.installedModels()
        XCTAssertEqual(models.count, 1)
        let data = try Data(contentsOf: models[0].url)
        XCTAssertEqual(String(bytes: data, encoding: .utf8), "two-longer")
    }

    func testDeleteRemovesModel() throws {
        let source = tempDir.appendingPathComponent("d.gguf")
        try Data("w".utf8).write(to: source)
        try store.importModel(from: source, named: "del.gguf")
        XCTAssertEqual(try store.installedModels().count, 1)

        try store.deleteModel(named: "del.gguf")
        XCTAssertTrue(try store.installedModels().isEmpty)
    }

    func testDeleteAbsentIsNoOp() throws {
        XCTAssertNoThrow(try store.deleteModel(named: "missing.gguf"))
    }

    func testModelsSortedByName() throws {
        for name in ["zeta.gguf", "alpha.gguf", "mid.gguf"] {
            let src = tempDir.appendingPathComponent("src-\(name)")
            try Data("w".utf8).write(to: src)
            try store.importModel(from: src, named: name)
        }
        XCTAssertEqual(try store.installedModels().map(\.name), ["alpha.gguf", "mid.gguf", "zeta.gguf"])
    }

    // MARK: - Capability detection

    func testGGUFFileMapsToGGUFCapability() throws {
        let source = tempDir.appendingPathComponent("m.gguf")
        try Data("w".utf8).write(to: source)
        try store.importModel(from: source, named: "m.gguf")
        let model = try XCTUnwrap(try store.installedModels().first)
        XCTAssertEqual(model.capability, .gguf)
        XCTAssertFalse(store.hasCapability(.localGemmaMLX))
        XCTAssertTrue(store.hasCapability(.gguf))
    }

    func testGemmaMLXDirectoryMapsToLocalGemma() throws {
        // An MLX Gemma model is a directory with config.json + a weights file.
        try store.ensureDirectory()
        let modelDir = store.modelsDirectory.appendingPathComponent("gemma-2b-it-mlx", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: modelDir.appendingPathComponent("config.json"))
        try Data("weights".utf8).write(to: modelDir.appendingPathComponent("model.safetensors"))

        let models = try store.installedModels()
        XCTAssertEqual(models.count, 1)
        XCTAssertTrue(models[0].isDirectory)
        XCTAssertEqual(models[0].capability, .localGemmaMLX)
        XCTAssertTrue(store.hasCapability(.localGemmaMLX))
        XCTAssertNotNil(store.model(for: .localGemmaMLX))
        XCTAssertGreaterThan(models[0].sizeBytes, 0, "directory size should sum its files")
    }

    func testDirectoryWithoutWeightsIsUnknown() throws {
        try store.ensureDirectory()
        let modelDir = store.modelsDirectory.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        XCTAssertEqual(try store.installedModels().first?.capability, .unknown)
    }

    func testAdoptMovesFile() throws {
        let source = tempDir.appendingPathComponent("adopt-src")
        try Data("w".utf8).write(to: source)
        try store.adoptModel(at: source, named: "adopted.gguf")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path), "adopt should move, not copy")
        XCTAssertEqual(try store.installedModels().first?.name, "adopted.gguf")
    }
}
