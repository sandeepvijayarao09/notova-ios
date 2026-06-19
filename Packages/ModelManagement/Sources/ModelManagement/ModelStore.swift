import Foundation

// MARK: - Model capability

/// What an on-device model file/bundle enables. Detection maps a present file to
/// a capability so the resolvers know which optional engine to light up.
public enum ModelCapability: String, Sendable, Hashable, Codable, CaseIterable {
    /// An MLX-format Gemma model directory (config.json + weights) — enables
    /// `LocalGemmaSummarizer`.
    case localGemmaMLX
    /// A GGUF model file (llama.cpp family) — reserved extension point.
    case gguf
    /// Anything else we keep around but don't yet map to an engine.
    case unknown
}

// MARK: - Installed model

/// A model present in the store.
public struct InstalledModel: Sendable, Hashable, Identifiable {
    public var name: String
    public var url: URL
    public var isDirectory: Bool
    public var sizeBytes: Int64
    public var capability: ModelCapability

    /// Stable identity derived from the on-disk name.
    public var id: String { name }

    public init(name: String, url: URL, isDirectory: Bool, sizeBytes: Int64, capability: ModelCapability) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
        self.capability = capability
    }
}

// MARK: - ModelStore

/// Lists, imports, and deletes on-device model files under
/// `Application Support/Models`, and maps present files to a `ModelCapability`.
///
/// Pure file-system logic — no inference, no network — so it is fully testable
/// against a temporary directory.
public final class ModelStore: @unchecked Sendable {
    public let modelsDirectory: URL
    private let fileManager: FileManager

    /// Designated init with an explicit directory (used by tests with a temp dir).
    public init(directory: URL, fileManager: FileManager = .default) {
        self.modelsDirectory = directory
        self.fileManager = fileManager
    }

    /// Convenience init that resolves `Application Support/Models`, falling back
    /// to a temporary directory if Application Support is unavailable.
    public convenience init(fileManager: FileManager = .default) {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        self.init(directory: base.appendingPathComponent("Models", isDirectory: true), fileManager: fileManager)
    }

    // MARK: - Directory

    /// Ensure the models directory exists; safe to call repeatedly.
    @discardableResult
    public func ensureDirectory() throws -> URL {
        if !fileManager.fileExists(atPath: modelsDirectory.path) {
            try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        }
        return modelsDirectory
    }

    // MARK: - List

    /// All models currently present, sorted by name.
    public func installedModels() throws -> [InstalledModel] {
        guard fileManager.fileExists(atPath: modelsDirectory.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        )
        return entries
            .map { url -> InstalledModel in
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let size = isDir ? directorySize(of: url) : fileSize(of: url)
                return InstalledModel(
                    name: url.lastPathComponent,
                    url: url,
                    isDirectory: isDir,
                    sizeBytes: size,
                    capability: Self.capability(for: url, isDirectory: isDir)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Whether any installed model provides the given capability.
    public func hasCapability(_ capability: ModelCapability) -> Bool {
        ((try? installedModels()) ?? []).contains { $0.capability == capability }
    }

    /// The first installed model providing the given capability, if any.
    public func model(for capability: ModelCapability) -> InstalledModel? {
        ((try? installedModels()) ?? []).first { $0.capability == capability }
    }

    // MARK: - Import / delete

    /// Copy a model file (or directory bundle) into the store. Returns the
    /// destination URL. Overwrites any existing entry with the same name.
    @discardableResult
    public func importModel(from sourceURL: URL, named name: String? = nil) throws -> URL {
        try ensureDirectory()
        let destination = modelsDirectory.appendingPathComponent(name ?? sourceURL.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }

    /// Move (rather than copy) an item into the store — used by the downloader to
    /// promote a finished temp file. Overwrites any existing entry.
    @discardableResult
    public func adoptModel(at sourceURL: URL, named name: String) throws -> URL {
        try ensureDirectory()
        let destination = modelsDirectory.appendingPathComponent(name)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: sourceURL, to: destination)
        return destination
    }

    /// Delete a model by name. No-op if absent.
    public func deleteModel(named name: String) throws {
        let url = modelsDirectory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    // MARK: - Capability detection

    /// Map a file/dir to a capability. An MLX Gemma model is a *directory*
    /// containing `config.json` and a weights file (`*.safetensors`); a `.gguf`
    /// file maps to `.gguf`.
    static func capability(for url: URL, isDirectory: Bool) -> ModelCapability {
        if isDirectory {
            // An MLX model bundle is a directory holding `config.json` plus a
            // weights file (`*.safetensors` / `*.npz`). We treat any such bundle
            // as the local-Gemma capability (the only MLX engine wired today).
            let fm = FileManager.default
            let hasConfig = fm.fileExists(atPath: url.appendingPathComponent("config.json").path)
            let contents = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
            let hasWeights = contents.contains { $0.hasSuffix(".safetensors") || $0.hasSuffix(".npz") }
            return (hasConfig && hasWeights) ? .localGemmaMLX : .unknown
        }
        if url.pathExtension.lowercased() == "gguf" {
            return .gguf
        }
        return .unknown
    }

    // MARK: - Sizing

    private func fileSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func directorySize(of url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += fileSize(of: fileURL)
        }
        return total
    }
}
