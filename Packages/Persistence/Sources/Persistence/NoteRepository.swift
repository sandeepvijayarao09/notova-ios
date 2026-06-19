import Foundation
import SwiftData
import NotovaCore

/// Persists `Note`s (recording + transcript + summary) using SwiftData.
/// Bound to the main actor because `ModelContext` is not Sendable.
@MainActor
public final class NoteRepository {
    public let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(inMemory: Bool = false) throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        self.container = try ModelContainer(
            for: RecordingEntity.self, SummaryEntity.self,
            configurations: config
        )
    }

    public init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Writes

    /// Insert or update a full note.
    public func save(_ note: Note) throws {
        let id = note.recording.id
        let existing = try fetchEntity(id: id)
        let entity = existing ?? RecordingEntity(domain: note.recording)

        entity.title = note.recording.title
        entity.createdAt = note.recording.createdAt
        entity.durationSec = note.recording.durationSec
        entity.sourceRaw = note.recording.source.rawValue
        entity.localAudioPath = note.recording.localAudioPath
        entity.statusRaw = note.recording.status.rawValue

        if let transcript = note.transcript {
            entity.transcriptJSON = try JSONEncoder().encode(transcript)
        }
        if let summary = note.summary {
            entity.summary = try SummaryEntity(domain: summary)
        }

        if existing == nil {
            context.insert(entity)
        }
        try context.save()
    }

    public func updateActionItems(recordingId: UUID, items: [ActionItem]) throws {
        guard let entity = try fetchEntity(id: recordingId), let summary = entity.summary else { return }
        summary.actionItemsJSON = try JSONEncoder().encode(items)
        try context.save()
    }

    public func delete(recordingId: UUID) throws {
        guard let entity = try fetchEntity(id: recordingId) else { return }
        context.delete(entity)
        try context.save()
    }

    // MARK: - Reads

    public func allNotes() throws -> [Note] {
        let descriptor = FetchDescriptor<RecordingEntity>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { try $0.asNote() }
    }

    public func note(id: UUID) throws -> Note? {
        try fetchEntity(id: id)?.asNote()
    }

    // MARK: - Private

    private func fetchEntity(id: UUID) throws -> RecordingEntity? {
        var descriptor = FetchDescriptor<RecordingEntity>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

extension RecordingEntity {
    func asNote() throws -> Note {
        let transcript = try transcriptJSON.map { try JSONDecoder().decode(Transcript.self, from: $0) }
        let summaryDomain = try summary?.asDomain()
        return Note(recording: asDomain, transcript: transcript, summary: summaryDomain)
    }
}
