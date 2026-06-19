import Foundation

// MARK: - Recording

/// A single captured audio item and its processing lifecycle.
public struct Recording: Identifiable, Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable, CaseIterable {
        case mic
        case bluetooth
        case file
        case other
    }

    public enum Status: String, Codable, Sendable, CaseIterable {
        case recording
        case processing
        case ready
        case failed
    }

    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var durationSec: Double
    public var source: Source
    public var localAudioPath: String?
    public var status: Status

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        durationSec: Double = 0,
        source: Source = .mic,
        localAudioPath: String? = nil,
        status: Status = .recording
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.durationSec = durationSec
        self.source = source
        self.localAudioPath = localAudioPath
        self.status = status
    }
}

// MARK: - Transcript

public struct TranscriptSegment: Codable, Hashable, Sendable {
    public var startMs: Int
    public var endMs: Int
    public var text: String
    public var speaker: String?

    public init(startMs: Int, endMs: Int, text: String, speaker: String? = nil) {
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.speaker = speaker
    }
}

public struct Transcript: Codable, Hashable, Sendable {
    public var recordingId: UUID
    public var language: String
    public var fullText: String
    public var segments: [TranscriptSegment]

    public init(recordingId: UUID, language: String, fullText: String, segments: [TranscriptSegment]) {
        self.recordingId = recordingId
        self.language = language
        self.fullText = fullText
        self.segments = segments
    }
}

// MARK: - Summary

public struct ActionItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var done: Bool

    public init(id: UUID = UUID(), text: String, done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }
}

public struct Summary: Codable, Hashable, Sendable {
    public var recordingId: UUID
    public var style: String
    public var contentMarkdown: String
    public var actionItems: [ActionItem]
    public var model: String
    public var generatedAt: Date

    public init(
        recordingId: UUID,
        style: String,
        contentMarkdown: String,
        actionItems: [ActionItem],
        model: String,
        generatedAt: Date = Date()
    ) {
        self.recordingId = recordingId
        self.style = style
        self.contentMarkdown = contentMarkdown
        self.actionItems = actionItems
        self.model = model
        self.generatedAt = generatedAt
    }
}

// MARK: - Integration export

public struct IntegrationExport: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending
        case done
        case failed
    }

    public var recordingId: UUID
    public var provider: String
    public var externalId: String?
    public var url: String?
    public var status: Status

    public init(
        recordingId: UUID,
        provider: String,
        externalId: String? = nil,
        url: String? = nil,
        status: Status = .pending
    ) {
        self.recordingId = recordingId
        self.provider = provider
        self.externalId = externalId
        self.url = url
        self.status = status
    }
}

// MARK: - Composite note

/// A finished note: the recording plus its derived transcript and summary.
public struct Note: Identifiable, Hashable, Sendable {
    public var recording: Recording
    public var transcript: Transcript?
    public var summary: Summary?

    public var id: UUID { recording.id }

    public init(recording: Recording, transcript: Transcript? = nil, summary: Summary? = nil) {
        self.recording = recording
        self.transcript = transcript
        self.summary = summary
    }
}
