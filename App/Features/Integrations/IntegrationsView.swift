import SwiftUI
import DesignSystem

/// The Integrations tab: lists providers with connect / disconnect actions and
/// surfaces connection state + errors (including the dev-safe "not configured").
struct IntegrationsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(SessionStore.self) private var session
    @State private var viewModel: IntegrationsViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if !session.hasAccount {
                    guestPrompt
                } else if let viewModel {
                    content(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Integrations")
            .task {
                if viewModel == nil {
                    viewModel = IntegrationsViewModel(
                        backend: container.backend,
                        session: session,
                        authorize: { try await WebAuthSession.authorize(url: $0) }
                    )
                }
                // A guest has no account token; calling the backend here would 401 and sign them
                // out. Integrations require an account — guestPrompt is shown instead.
                if session.hasAccount {
                    await viewModel?.refresh()
                }
            }
        }
        .onOpenURL { url in
            Task { await viewModel?.handleCallback(url: url) }
        }
    }

    private var guestPrompt: some View {
        VStack(spacing: NotovaSpacing.md) {
            Image(systemName: "link")
                .font(.system(size: 44))
                .foregroundStyle(NotovaColor.textSecondary)
            Text("Sign in to connect integrations")
                .font(NotovaFont.title)
                .multilineTextAlignment(.center)
            Text(
                "Exporting notes to apps like Notion and Todoist needs a Notova account. "
                    + "Your recordings, transcripts and summaries always stay on-device."
            )
                .font(NotovaFont.caption)
                .foregroundStyle(NotovaColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(NotovaSpacing.lg)
        .frame(maxWidth: 420)
        .accessibilityIdentifier("integrations.guestPrompt")
    }

    @ViewBuilder
    private func content(_ viewModel: IntegrationsViewModel) -> some View {
        List {
            Section {
                if viewModel.rows.isEmpty && !viewModel.isLoading {
                    Text("No integrations available.")
                        .font(NotovaFont.caption)
                        .foregroundStyle(NotovaColor.textSecondary)
                } else {
                    ForEach(viewModel.rows) { row in
                        providerRow(row, viewModel: viewModel)
                    }
                }
            } footer: {
                Text("Connecting opens a secure provider sign-in. Notova forwards a note's summary + transcript only when you export it.")
            }

            if let status = viewModel.statusMessage {
                Section {
                    Text(status)
                        .font(NotovaFont.caption)
                        .foregroundStyle(NotovaColor.textSecondary)
                        .accessibilityIdentifier("integrations.status")
                }
            }
            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(NotovaFont.caption)
                        .foregroundStyle(NotovaColor.recording)
                        .accessibilityIdentifier("integrations.error")
                }
            }
        }
        .accessibilityIdentifier("integrations.list")
        .overlay {
            if viewModel.isLoading && viewModel.rows.isEmpty {
                ProgressView()
            }
        }
        .refreshable { await viewModel.refresh() }
    }

    private func providerRow(_ row: IntegrationsViewModel.Row, viewModel: IntegrationsViewModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: NotovaSpacing.xs) {
                Text(row.displayName)
                    .font(NotovaFont.body)
                StatusBadge(
                    text: row.connected ? "Connected" : "Not connected",
                    color: row.connected ? NotovaColor.accent : NotovaColor.textSecondary
                )
            }
            Spacer()
            if viewModel.inFlightProvider == row.provider {
                ProgressView()
            } else if row.connected {
                Button("Disconnect", role: .destructive) {
                    Task { await viewModel.disconnect(provider: row.provider) }
                }
                .accessibilityIdentifier("integrations.disconnect.\(row.provider)")
            } else {
                Button("Connect") {
                    Task { await viewModel.connect(provider: row.provider) }
                }
                .accessibilityIdentifier("integrations.connect.\(row.provider)")
            }
        }
        .accessibilityIdentifier("integrations.row.\(row.provider)")
    }
}
