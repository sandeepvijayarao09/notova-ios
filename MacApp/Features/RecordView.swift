import NotovaCore
import SwiftUI
import UniformTypeIdentifiers

/// Capture / import screen. Record from the default input device or import an audio file;
/// both run the same on-device pipeline and land in Notes.
struct RecordView: View {
    @Environment(AppModel.self) private var model
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: model.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(model.isRecording ? .red : .accentColor)
                .symbolEffect(.pulse, isActive: model.isRecording)

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if model.recordState == .processing {
                ProgressView()
            }

            HStack(spacing: 12) {
                Button {
                    Task { await model.toggleRecording() }
                } label: {
                    Label(model.isRecording ? "Stop" : "Record", systemImage: model.isRecording ? "stop.fill" : "record.circle")
                        .frame(minWidth: 96)
                }
                .keyboardShortcut("r", modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .disabled(model.recordState == .processing)

                Button {
                    isImporting = true
                } label: {
                    Label("Import Audio File…", systemImage: "square.and.arrow.down")
                }
                .disabled(model.isRecording || model.recordState == .processing)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Record")
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                Task { await model.importFile(at: url) }
            }
        }
    }

    private var title: String {
        switch model.recordState {
        case .idle: "Ready"
        case .recording: "Recording"
        case .processing: "Processing"
        case let .done(name): "Saved “\(name)”"
        case .failed: "Something went wrong"
        }
    }
}
