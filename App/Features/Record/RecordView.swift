import SwiftUI
import UniformTypeIdentifiers
import DesignSystem

struct RecordView: View {
    @Environment(AppContainer.self) private var container
    @State private var viewModel: RecordViewModel?
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: NotovaSpacing.xl) {
                Spacer()

                Text("Notova")
                    .font(NotovaFont.title)

                if let viewModel {
                    RecordButton(isRecording: viewModel.isRecording) {
                        Task { await viewModel.toggleRecording() }
                    }
                    .accessibilityIdentifier("record.button")

                    if viewModel.state == .processing {
                        ProgressView()
                            .accessibilityIdentifier("record.processing")
                    }

                    Text(viewModel.statusMessage)
                        .font(NotovaFont.body)
                        .foregroundStyle(NotovaColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, NotovaSpacing.lg)
                        .accessibilityIdentifier("record.status")
                }

                Spacer()

                Button {
                    showImporter = true
                } label: {
                    Label("Import audio file", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .padding(.bottom, NotovaSpacing.xl)
                .accessibilityIdentifier("record.import")
            }
            .frame(maxWidth: .infinity)
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.audio, .mpeg4Audio, .wav, .mp3],
                allowsMultipleSelection: false
            ) { result in
                guard case let .success(urls) = result, let url = urls.first else { return }
                Task { await viewModel?.importFile(at: url) }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = RecordViewModel(
                    audioSource: container.audioSource,
                    pipeline: container.pipeline,
                    repository: container.repository,
                    requestPermission: container.requestPermission
                )
            }
        }
    }
}

#Preview {
    RecordView()
        .environment(AppContainer())
}
