import SwiftUI
import NotovaCore
import Integrations
import DesignSystem

/// Sheet presented from `NoteDetailView` to export a note to a connected
/// integration provider. Loads connected providers, lets the user pick one,
/// then shows success (externalId / url) or a clear error.
struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: ExportViewModel

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.canExport {
                    Section {
                        Text("This note needs a summary and transcript before it can be exported.")
                            .font(NotovaFont.caption)
                            .foregroundStyle(NotovaColor.textSecondary)
                    }
                } else {
                    providersSection
                }
                resultSection
            }
            .navigationTitle("Export to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("export.done")
                }
            }
            .task { await viewModel.loadConnectedProviders() }
        }
        .accessibilityIdentifier("export.sheet")
    }

    @ViewBuilder
    private var providersSection: some View {
        Section("Connected providers") {
            if viewModel.isLoadingProviders {
                ProgressView()
            } else if let error = viewModel.loadError {
                Text(error)
                    .font(NotovaFont.caption)
                    .foregroundStyle(NotovaColor.recording)
                    .accessibilityIdentifier("export.loadError")
            } else if viewModel.connectedProviders.isEmpty {
                Text("No connected providers. Connect one in the Integrations tab first.")
                    .font(NotovaFont.caption)
                    .foregroundStyle(NotovaColor.textSecondary)
                    .accessibilityIdentifier("export.empty")
            } else {
                ForEach(viewModel.connectedProviders, id: \.self) { provider in
                    Button {
                        Task { await viewModel.export(to: provider) }
                    } label: {
                        HStack {
                            Text(provider.capitalized)
                            Spacer()
                            if viewModel.isExporting {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(NotovaColor.textSecondary)
                            }
                        }
                    }
                    .disabled(viewModel.isExporting)
                    .accessibilityIdentifier("export.provider.\(provider)")
                }
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let result = viewModel.result {
            Section("Result") {
                switch result {
                case let .success(provider, externalId, url, status):
                    VStack(alignment: .leading, spacing: NotovaSpacing.xs) {
                        Label("Exported to \(provider.capitalized)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(NotovaColor.accent)
                        Text("Status: \(status.rawValue)")
                            .font(NotovaFont.caption)
                            .foregroundStyle(NotovaColor.textSecondary)
                        Text("ID: \(externalId)")
                            .font(NotovaFont.caption)
                            .foregroundStyle(NotovaColor.textSecondary)
                        if let url, let link = URL(string: url) {
                            Link("Open in \(provider.capitalized)", destination: link)
                                .font(NotovaFont.caption)
                        }
                    }
                    .accessibilityIdentifier("export.success")
                case let .failure(message):
                    Text(message)
                        .font(NotovaFont.caption)
                        .foregroundStyle(NotovaColor.recording)
                        .accessibilityIdentifier("export.failure")
                }
            }
        }
    }
}
