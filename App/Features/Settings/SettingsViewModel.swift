import Foundation
import SwiftUI
import NotovaCore
import ModelManagement
import Transcription
import AISummary

/// Drives the Settings "On-device AI" + model-management section: surfaces the
/// active summarizer/transcriber engines (and the full candidate chain) and
/// handles importing, downloading, and deleting model files.
@Observable
@MainActor
final class SettingsViewModel {
    private let modelStore: ModelStore
    private let summarizerResolver: ResolvingSummarizer?
    private let transcriberResolver: ResolvingTranscriber?

    /// Installed models, refreshed after every mutation.
    var models: [InstalledModel] = []
    /// Resolution snapshots for display. Populated by a cheap dry-run probe.
    var summarizerResolution = EngineResolution()
    var transcriberResolution = EngineResolution()

    /// Download progress in `0...1` while a download is active; `nil` otherwise.
    var downloadProgress: Double?
    /// User-visible status line for the model section.
    var statusMessage: String?
    var isImporting = false

    private var downloadTask: Task<Void, Never>?

    init(
        modelStore: ModelStore,
        summarizerResolver: ResolvingSummarizer?,
        transcriberResolver: ResolvingTranscriber?
    ) {
        self.modelStore = modelStore
        self.summarizerResolver = summarizerResolver
        self.transcriberResolver = transcriberResolver
    }

    // MARK: - Loading

    func refresh() async {
        models = (try? modelStore.installedModels()) ?? []
        if let summarizerResolver {
            summarizerResolution = await summarizerResolver.previewResolution()
        }
        if let transcriberResolver {
            transcriberResolution = await transcriberResolver.previewResolution()
        }
    }

    var activeSummarizerName: String {
        summarizerResolution.candidates.first(where: \.available)?.name ?? "None"
    }

    var activeTranscriberName: String {
        transcriberResolution.candidates.first(where: \.available)?.name ?? "None"
    }

    // MARK: - Import

    func importModel(from url: URL) {
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try modelStore.importModel(from: url)
            statusMessage = "Imported \(url.lastPathComponent)."
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
        Task { await refresh() }
    }

    // MARK: - Download

    func startDownload(from urlString: String, filename: String) {
        guard let url = URL(string: urlString), !filename.isEmpty else {
            statusMessage = "Enter a valid URL and filename."
            return
        }
        downloadTask?.cancel()
        downloadProgress = 0
        statusMessage = "Downloading \(filename)…"
        let downloader = ModelDownloader(store: modelStore)
        downloadTask = Task {
            do {
                for try await event in downloader.download(from: url, filename: filename) {
                    switch event {
                    case let .progress(fraction, _, _):
                        downloadProgress = fraction ?? downloadProgress
                    case .finished:
                        statusMessage = "Downloaded \(filename)."
                    }
                }
            } catch is CancellationError {
                statusMessage = "Download cancelled."
            } catch {
                statusMessage = "Download failed: \(error.localizedDescription)"
            }
            downloadProgress = nil
            await refresh()
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadProgress = nil
    }

    // MARK: - Delete

    func deleteModel(_ model: InstalledModel) {
        try? modelStore.deleteModel(named: model.name)
        statusMessage = "Deleted \(model.name)."
        Task { await refresh() }
    }

    // MARK: - Formatting

    func sizeString(_ model: InstalledModel) -> String {
        ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file)
    }
}
