import Foundation
import NotovaCore

/// Notion export stub. Real impl will broker OAuth via the Notova backend and
/// create a page through the provider API. AI compute never touches the backend.
public struct NotionExporter: IntegrationExporter {
    public let provider = "notion"
    public init() {}

    public func export(
        recordingId: UUID,
        summary: Summary,
        transcript: Transcript
    ) async throws -> IntegrationExport {
        IntegrationExport(
            recordingId: recordingId,
            provider: provider,
            externalId: "notion-\(recordingId.uuidString.prefix(8))",
            url: "https://www.notion.so/\(recordingId.uuidString)",
            status: .done
        )
    }
}

/// Email export stub.
public struct EmailExporter: IntegrationExporter {
    public let provider = "email"
    public init() {}

    public func export(
        recordingId: UUID,
        summary: Summary,
        transcript: Transcript
    ) async throws -> IntegrationExport {
        IntegrationExport(
            recordingId: recordingId,
            provider: provider,
            externalId: nil,
            url: nil,
            status: .done
        )
    }
}

/// Registry of available exporters for the UI to enumerate.
public enum IntegrationRegistry {
    public static func available() -> [any IntegrationExporter] {
        [NotionExporter(), EmailExporter()]
    }
}
