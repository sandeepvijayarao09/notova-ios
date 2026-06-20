import Foundation
import SwiftUI
import NotovaCore
import Integrations

/// Drives the "Export to…" action on a note: lists the connected providers,
/// then forwards the note's recording + summary + transcript to the chosen one
/// via `NotovaBackendClient.export`, mapping the result/error to UI state.
@Observable
@MainActor
final class ExportViewModel {

    enum Result: Equatable {
        case success(provider: String, externalId: String, url: String?, status: NotovaBackendClient.ExportStatus)
        case failure(message: String)
    }

    let note: Note

    /// Providers that are currently connected (the only valid export targets).
    var connectedProviders: [String] = []
    var isLoadingProviders = false
    var isExporting = false
    var result: Result?
    var loadError: String?

    private let backend: ExportBackend
    private let session: SessionStore

    init(note: Note, backend: ExportBackend, session: SessionStore) {
        self.note = note
        self.backend = backend
        self.session = session
    }

    /// True only when the note carries both a summary and a transcript — export
    /// forwards both, so we don't offer it for incomplete notes.
    var canExport: Bool {
        note.summary != nil && note.transcript != nil
    }

    func loadConnectedProviders() async {
        isLoadingProviders = true
        loadError = nil
        defer { isLoadingProviders = false }
        do {
            let integrations = try await session.withAuthRetry { [backend] in
                try await backend.listIntegrations()
            }
            connectedProviders = integrations
                .filter(\.connected)
                .map(\.provider)
                .sorted()
        } catch {
            loadError = SessionStore.message(for: error)
        }
    }

    /// Builds + sends the export call for the given provider.
    func export(to provider: String) async {
        guard let summary = note.summary, let transcript = note.transcript else {
            result = .failure(message: "This note has no summary or transcript to export yet.")
            return
        }
        isExporting = true
        result = nil
        defer { isExporting = false }
        do {
            let response = try await session.withAuthRetry { [backend, note] in
                try await backend.export(
                    provider: provider,
                    recording: note.recording,
                    summary: summary,
                    transcript: transcript
                )
            }
            result = .success(
                provider: provider,
                externalId: response.externalId,
                url: response.url,
                status: response.status
            )
        } catch {
            result = .failure(message: IntegrationsViewModel.connectMessage(for: error, provider: provider))
        }
    }
}
