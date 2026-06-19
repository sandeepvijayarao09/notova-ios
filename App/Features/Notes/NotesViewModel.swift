import Foundation
import SwiftUI
import NotovaCore
import Persistence

@Observable
@MainActor
final class NotesViewModel {
    var notes: [Note] = []
    var loadError: String?

    private let repository: NoteRepository

    init(repository: NoteRepository) {
        self.repository = repository
    }

    func load() {
        do {
            notes = try repository.allNotes()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func delete(_ note: Note) {
        do {
            try repository.delete(recordingId: note.recording.id)
            load()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func toggleActionItem(in note: Note, item: ActionItem) {
        guard var summary = note.summary else { return }
        guard let idx = summary.actionItems.firstIndex(where: { $0.id == item.id }) else { return }
        summary.actionItems[idx].done.toggle()
        do {
            try repository.updateActionItems(recordingId: note.recording.id, items: summary.actionItems)
            load()
        } catch {
            loadError = error.localizedDescription
        }
    }
}
