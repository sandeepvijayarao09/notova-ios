import Foundation
import NotovaCore

/// Minimal on-disk note store for the macOS app: persists notes as JSON in Application Support
/// (or stays in-memory when `inMemory` is true, for tests). Thread-safe via an `NSLock` so it can
/// be a plain dependency of the `@MainActor` `AppModel` and of background callers alike.
///
/// This intentionally mirrors only what the Mac app needs; the richer iOS `Persistence` package
/// (SwiftData) is iOS-leaning, so the Mac app keeps its own small, portable store.
final class NoteStore: @unchecked Sendable {
    /// Codable mirror of a `Note` (whose `recording`/`transcript`/`summary` are all Codable).
    private struct Persisted: Codable {
        var recording: Recording
        var transcript: Transcript?
        var summary: Summary?
    }

    private let fileURL: URL?
    private let lock = NSLock()
    private var items: [Note]

    init(inMemory: Bool = false) {
        let url = inMemory ? nil : Self.defaultFileURL()
        fileURL = url
        items = url.flatMap(Self.read) ?? []
    }

    /// All notes, newest first.
    func load() -> [Note] {
        lock.lock()
        defer { lock.unlock() }
        return items.sorted { $0.recording.createdAt > $1.recording.createdAt }
    }

    /// Inserts or replaces a note (matched by id), then persists.
    func save(_ note: Note) {
        lock.lock()
        defer { lock.unlock() }
        items.removeAll { $0.id == note.id }
        items.append(note)
        persist()
    }

    func delete(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        items.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Disk

    private func persist() {
        guard let fileURL else { return }
        let dtos = items.map { Persisted(recording: $0.recording, transcript: $0.transcript, summary: $0.summary) }
        guard let data = try? JSONEncoder().encode(dtos) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func read(_ url: URL) -> [Note]? {
        guard let data = try? Data(contentsOf: url),
              let dtos = try? JSONDecoder().decode([Persisted].self, from: data)
        else { return nil }
        return dtos.map { Note(recording: $0.recording, transcript: $0.transcript, summary: $0.summary) }
    }

    private static func defaultFileURL() -> URL? {
        let fileManager = FileManager.default
        guard let support = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let directory = support.appendingPathComponent("Notova", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("notes.json")
    }
}
