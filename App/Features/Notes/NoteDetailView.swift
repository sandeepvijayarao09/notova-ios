import SwiftUI
import NotovaCore
import DesignSystem

struct NoteDetailView: View {
    let note: Note
    let viewModel: NotesViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NotovaSpacing.lg) {
                if let summary = note.summary {
                    CardSection("Summary") {
                        Text(markdown(summary.contentMarkdown))
                            .font(NotovaFont.body)
                    }

                    if !summary.actionItems.isEmpty {
                        CardSection("Action items") {
                            ForEach(summary.actionItems) { item in
                                Button {
                                    viewModel.toggleActionItem(in: note, item: item)
                                } label: {
                                    HStack(alignment: .top, spacing: NotovaSpacing.sm) {
                                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(item.done ? NotovaColor.accent : NotovaColor.textSecondary)
                                        Text(item.text)
                                            .strikethrough(item.done)
                                            .foregroundStyle(NotovaColor.textPrimary)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let transcript = note.transcript {
                    CardSection("Transcript") {
                        VStack(alignment: .leading, spacing: NotovaSpacing.sm) {
                            ForEach(Array(transcript.segments.enumerated()), id: \.offset) { _, segment in
                                VStack(alignment: .leading, spacing: 2) {
                                    if let speaker = segment.speaker {
                                        Text(speaker)
                                            .font(NotovaFont.caption)
                                            .foregroundStyle(NotovaColor.textSecondary)
                                    }
                                    Text(segment.text)
                                        .font(NotovaFont.body)
                                }
                            }
                        }
                    }
                }

                if note.summary == nil && note.transcript == nil {
                    Text("This note has no content yet.")
                        .foregroundStyle(NotovaColor.textSecondary)
                }
            }
            .padding(NotovaSpacing.md)
        }
        .accessibilityIdentifier("noteDetail.scroll")
        .navigationTitle(note.recording.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
