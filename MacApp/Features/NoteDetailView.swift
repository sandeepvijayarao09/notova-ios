import NotovaCore
import SwiftUI

/// Read-only detail for a finished note: summary (markdown), action items, and transcript.
struct NoteDetailView: View {
    let note: Note
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let summary = note.summary {
                    section("Summary") {
                        Text(markdown(summary.contentMarkdown))
                            .textSelection(.enabled)
                    }
                    if !summary.actionItems.isEmpty {
                        section("Action items") {
                            ForEach(summary.actionItems) { item in
                                Label(item.text, systemImage: item.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.done ? .secondary : .primary)
                            }
                        }
                    }
                }
                if let transcript = note.transcript {
                    section("Transcript") {
                        Text(transcript.fullText)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(note.recording.title)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    model.delete(note)
                    dismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
