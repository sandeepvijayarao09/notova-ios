import NotovaCore
import SwiftUI

/// Notes list. Selecting a note pushes its detail in the same pane.
struct NotesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.notes.isEmpty {
                    ContentUnavailableView(
                        "No notes yet",
                        systemImage: "note.text",
                        description: Text("Record or import audio to create your first note.")
                    )
                } else {
                    List(model.notes) { note in
                        NavigationLink(value: note) { NoteRow(note: note) }
                    }
                }
            }
            .navigationTitle("Notes")
            .navigationDestination(for: Note.self) { note in
                NoteDetailView(note: note)
            }
        }
    }
}

/// One row in the notes list: title, relative date, source + duration, and processing status.
private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.recording.title).fontWeight(.medium)
                Spacer()
                StatusBadge(status: note.recording.status)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let date = note.recording.createdAt.formatted(date: .abbreviated, time: .shortened)
        let duration = Duration.seconds(note.recording.durationSec)
            .formatted(.time(pattern: .minuteSecond))
        return "\(date) · \(note.recording.source.rawValue) · \(duration)"
    }
}

private struct StatusBadge: View {
    let status: Recording.Status

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .ready: .green
        case .processing, .recording: .orange
        case .failed: .red
        }
    }
}
