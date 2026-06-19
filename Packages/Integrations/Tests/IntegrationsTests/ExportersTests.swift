import XCTest
import NotovaCore
@testable import Integrations

final class ExportersTests: XCTestCase {

    private func fixtures(id: UUID = UUID()) -> (Summary, Transcript) {
        let summary = Summary(recordingId: id, style: "concise", contentMarkdown: "## S",
                              actionItems: [ActionItem(text: "a")], model: "stub")
        let transcript = Transcript(recordingId: id, language: "en", fullText: "hi", segments: [])
        return (summary, transcript)
    }

    // MARK: - NotionExporter

    func testNotionExporterProvider() {
        XCTAssertEqual(NotionExporter().provider, "notion")
    }

    func testNotionExportReturnShapeAndStatus() async throws {
        let id = UUID()
        let (summary, transcript) = fixtures(id: id)
        let export = try await NotionExporter().export(recordingId: id, summary: summary, transcript: transcript)

        XCTAssertEqual(export.recordingId, id)
        XCTAssertEqual(export.provider, "notion")
        XCTAssertEqual(export.status, .done)
        XCTAssertEqual(export.externalId, "notion-\(id.uuidString.prefix(8))")
        XCTAssertEqual(export.url, "https://www.notion.so/\(id.uuidString)")
    }

    // MARK: - EmailExporter

    func testEmailExporterProvider() {
        XCTAssertEqual(EmailExporter().provider, "email")
    }

    func testEmailExportReturnShapeAndStatus() async throws {
        let id = UUID()
        let (summary, transcript) = fixtures(id: id)
        let export = try await EmailExporter().export(recordingId: id, summary: summary, transcript: transcript)

        XCTAssertEqual(export.recordingId, id)
        XCTAssertEqual(export.provider, "email")
        XCTAssertEqual(export.status, .done)
        XCTAssertNil(export.externalId)
        XCTAssertNil(export.url)
    }

    // MARK: - Registry

    func testRegistryListsBothExporters() {
        let providers = IntegrationRegistry.available().map(\.provider)
        XCTAssertEqual(providers, ["notion", "email"])
    }

    func testRegistryExportersAreUsable() async throws {
        let id = UUID()
        let (summary, transcript) = fixtures(id: id)
        for exporter in IntegrationRegistry.available() {
            let export = try await exporter.export(recordingId: id, summary: summary, transcript: transcript)
            XCTAssertEqual(export.status, .done)
            XCTAssertEqual(export.recordingId, id)
            XCTAssertEqual(export.provider, exporter.provider)
        }
    }
}
