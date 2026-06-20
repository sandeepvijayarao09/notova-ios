import SwiftUI
import DesignSystem
import NotovaCore
import ModelManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(SessionStore.self) private var session
    @State private var viewModel: SettingsViewModel?
    @State private var showImporter = false
    @State private var downloadURL = ""
    @State private var downloadFilename = ""

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                integrationsSection
                onDeviceAISection
                modelManagementSection
                aboutSection
            }
            .accessibilityIdentifier("settings.form")
            .navigationTitle("Settings")
            .task {
                if viewModel == nil {
                    viewModel = SettingsViewModel(
                        modelStore: container.modelStore,
                        summarizerResolver: container.summarizerResolver,
                        transcriberResolver: container.transcriberResolver
                    )
                }
                await viewModel?.refresh()
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.data, .item, .folder],
                allowsMultipleSelection: false
            ) { result in
                if case let .success(urls) = result, let url = urls.first {
                    viewModel?.importModel(from: url)
                }
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section("Account") {
            LabeledContent("Signed in", value: accountEmail)
                .accessibilityIdentifier("settings.account.email")
            Button("Sign Out", role: .destructive) {
                Task { await session.signOut() }
            }
            .accessibilityIdentifier("settings.signOut")
            Text("Accounts, billing, and metadata sync are handled by the Notova backend. AI runs fully on-device.")
                .font(NotovaFont.caption)
                .foregroundStyle(NotovaColor.textSecondary)
        }
    }

    private var accountEmail: String {
        if let email = session.userEmail, !email.isEmpty { return email }
        return "Signed in"
    }

    private var integrationsSection: some View {
        Section("Integrations") {
            Text("Manage connected providers in the Integrations tab.")
                .font(NotovaFont.caption)
                .foregroundStyle(NotovaColor.textSecondary)
        }
    }

    @ViewBuilder
    private var onDeviceAISection: some View {
        Section("On-device AI") {
            LabeledContent("Transcription", value: viewModel?.activeTranscriberName ?? "Resolving…")
                .accessibilityIdentifier("settings.engine.transcription")
            LabeledContent("Summarization", value: viewModel?.activeSummarizerName ?? "Resolving…")
                .accessibilityIdentifier("settings.engine.summarization")

            if let resolution = viewModel?.summarizerResolution, !resolution.candidates.isEmpty {
                DisclosureGroup("Summarizer engines") {
                    ForEach(resolution.candidates) { candidate in
                        engineRow(candidate)
                    }
                }
                .accessibilityIdentifier("settings.engines.summarizer")
            }
            if let resolution = viewModel?.transcriberResolution, !resolution.candidates.isEmpty {
                DisclosureGroup("Transcriber engines") {
                    ForEach(resolution.candidates) { candidate in
                        engineRow(candidate)
                    }
                }
                .accessibilityIdentifier("settings.engines.transcriber")
            }
            Text("Notova picks the first available on-device engine. If none is ready it uses the built-in sample engine.")
                .font(NotovaFont.caption)
                .foregroundStyle(NotovaColor.textSecondary)
        }
    }

    private func engineRow(_ candidate: EngineResolution.Candidate) -> some View {
        HStack {
            Image(systemName: candidate.available ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(candidate.available ? Color.green : NotovaColor.textSecondary)
            Text(candidate.name)
            Spacer()
            Text(candidate.available ? "Available" : "Unavailable here")
                .font(NotovaFont.caption)
                .foregroundStyle(NotovaColor.textSecondary)
        }
    }

    @ViewBuilder
    private var modelManagementSection: some View {
        Section("On-device models") {
            if let models = viewModel?.models, !models.isEmpty {
                ForEach(models) { model in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.name)
                            Text("\(model.capability.rawValue) · \(viewModel?.sizeString(model) ?? "")")
                                .font(NotovaFont.caption)
                                .foregroundStyle(NotovaColor.textSecondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            viewModel?.deleteModel(model)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityIdentifier("settings.model.delete.\(model.name)")
                    }
                }
            } else {
                Text("No models installed.")
                    .font(NotovaFont.caption)
                    .foregroundStyle(NotovaColor.textSecondary)
            }

            Button("Import model file") { showImporter = true }
                .accessibilityIdentifier("settings.model.import")

            VStack(alignment: .leading, spacing: 8) {
                TextField("Model URL", text: $downloadURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("settings.model.url")
                TextField("Save as filename", text: $downloadFilename)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("settings.model.filename")
                if let progress = viewModel?.downloadProgress {
                    ProgressView(value: progress)
                        .accessibilityIdentifier("settings.model.progress")
                    Button("Cancel download") { viewModel?.cancelDownload() }
                } else {
                    Button("Download model") {
                        viewModel?.startDownload(from: downloadURL, filename: downloadFilename)
                    }
                    .accessibilityIdentifier("settings.model.download")
                }
            }

            if let status = viewModel?.statusMessage {
                Text(status)
                    .font(NotovaFont.caption)
                    .foregroundStyle(NotovaColor.textSecondary)
                    .accessibilityIdentifier("settings.model.status")
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "Notova")
            LabeledContent("Bundle", value: "com.notova.app")
        }
    }
}

#Preview {
    let container = AppContainer()
    return SettingsView()
        .environment(container)
        .environment(container.session)
}
