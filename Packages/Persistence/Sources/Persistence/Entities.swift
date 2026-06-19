import Foundation
import SwiftData
import NotovaCore

// MARK: - SwiftData entities

@Model
public final class RecordingEntity {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var createdAt: Date
    public var durationSec: Double
    public var sourceRaw: String
    public var localAudioPath: String?
    public var statusRaw: String

    // Derived note content stored alongside the recording.
    public var transcriptJSON: Data?
    @Relationship(deleteRule: .cascade, inverse: \SummaryEntity.recording)
    public var summary: SummaryEntity?

    public init(
        id: UUID,
        title: String,
        createdAt: Date,
        durationSec: Double,
        sourceRaw: String,
        localAudioPath: String?,
        statusRaw: String,
        transcriptJSON: Data? = nil,
        summary: SummaryEntity? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.durationSec = durationSec
        self.sourceRaw = sourceRaw
        self.localAudioPath = localAudioPath
        self.statusRaw = statusRaw
        self.transcriptJSON = transcriptJSON
        self.summary = summary
    }
}

@Model
public final class SummaryEntity {
    @Attribute(.unique) public var recordingId: UUID
    public var style: String
    public var contentMarkdown: String
    public var actionItemsJSON: Data
    public var model: String
    public var generatedAt: Date
    public var recording: RecordingEntity?

    public init(
        recordingId: UUID,
        style: String,
        contentMarkdown: String,
        actionItemsJSON: Data,
        model: String,
        generatedAt: Date
    ) {
        self.recordingId = recordingId
        self.style = style
        self.contentMarkdown = contentMarkdown
        self.actionItemsJSON = actionItemsJSON
        self.model = model
        self.generatedAt = generatedAt
    }
}

// MARK: - Mapping to/from domain types

extension RecordingEntity {
    public convenience init(domain: Recording) {
        self.init(
            id: domain.id,
            title: domain.title,
            createdAt: domain.createdAt,
            durationSec: domain.durationSec,
            sourceRaw: domain.source.rawValue,
            localAudioPath: domain.localAudioPath,
            statusRaw: domain.status.rawValue
        )
    }

    public var asDomain: Recording {
        Recording(
            id: id,
            title: title,
            createdAt: createdAt,
            durationSec: durationSec,
            source: Recording.Source(rawValue: sourceRaw) ?? .other,
            localAudioPath: localAudioPath,
            status: Recording.Status(rawValue: statusRaw) ?? .ready
        )
    }
}

extension SummaryEntity {
    public convenience init(domain: Summary) throws {
        let data = try JSONEncoder().encode(domain.actionItems)
        self.init(
            recordingId: domain.recordingId,
            style: domain.style,
            contentMarkdown: domain.contentMarkdown,
            actionItemsJSON: data,
            model: domain.model,
            generatedAt: domain.generatedAt
        )
    }

    public func asDomain() throws -> Summary {
        let items = try JSONDecoder().decode([ActionItem].self, from: actionItemsJSON)
        return Summary(
            recordingId: recordingId,
            style: style,
            contentMarkdown: contentMarkdown,
            actionItems: items,
            model: model,
            generatedAt: generatedAt
        )
    }
}
