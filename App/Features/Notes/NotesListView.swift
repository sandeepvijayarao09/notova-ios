import SwiftUI
import NotovaCore
import DesignSystem

struct NotesListView: View {
    @Environment(AppContainer.self) private var container
    @State private var viewModel: NotesViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    if viewModel.notes.isEmpty {
                        ContentUnavailableView(
                            "No notes yet",
                            systemImage: "waveform",
                            description: Text("Record or import audio to create your first note.")
                        )
                        .accessibilityIdentifier("notes.empty")
                    } else {
                        List {
                            ForEach(viewModel.notes) { note in
                                NavigationLink {
                                    NoteDetailView(note: note, viewModel: viewModel)
                                } label: {
                                    row(for: note)
                                }
                                .accessibilityIdentifier("notes.row.\(note.recording.id.uuidString)")
                            }
                            .onDelete { indexSet in
                                indexSet.map { viewModel.notes[$0] }.forEach(viewModel.delete)
                            }
                        }
                        .accessibilityIdentifier("notes.list")
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Notes")
            .toolbar { EditButton() }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = NotesViewModel(repository: container.repository)
            }
            viewModel?.load()
        }
    }

    private func row(for note: Note) -> some View {
        VStack(alignment: .leading, spacing: NotovaSpacing.xs) {
            Text(note.recording.title)
                .font(NotovaFont.heading)
            HStack(spacing: NotovaSpacing.sm) {
                StatusBadge(text: note.recording.source.rawValue)
                StatusBadge(
                    text: note.recording.status.rawValue,
                    color: note.recording.status == .ready ? NotovaColor.accent : NotovaColor.recording
                )
                Text(note.recording.createdAt, style: .date)
                    .font(NotovaFont.caption)
                    .foregroundStyle(NotovaColor.textSecondary)
            }
        }
    }
}

#Preview {
    NotesListView()
        .environment(AppContainer())
}
