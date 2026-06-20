import XCTest
import NotovaCore
import Integrations
import Keychain
@testable import Notova

@MainActor
final class ExportViewModelTests: XCTestCase {

    private func makeContext(
        backend: FakeBackend = FakeBackend(),
        note: Note = AuthFixtures.note()
    ) async -> (ExportViewModel, FakeBackend) {
        let store = InMemoryTokenStore(tokens: AuthTokens(accessToken: "a", refreshToken: "r"))
        let session = SessionStore(backend: backend, tokenStore: store)
        await session.restore()
        return (ExportViewModel(note: note, backend: backend, session: session), backend)
    }

    func testCanExportRequiresSummaryAndTranscript() async {
        let (full, _) = await makeContext(note: AuthFixtures.note(withContent: true))
        XCTAssertTrue(full.canExport)
        let (empty, _) = await makeContext(note: AuthFixtures.note(withContent: false))
        XCTAssertFalse(empty.canExport)
    }

    func testLoadConnectedProvidersFiltersAndSorts() async {
        let backend = FakeBackend()
        await backend.setList(.success(BackendDTO.integrations([
            ("slack", true),
            ("notion", true),
            ("google", false)
        ])))
        let (vm, _) = await makeContext(backend: backend)

        await vm.loadConnectedProviders()

        XCTAssertEqual(vm.connectedProviders, ["notion", "slack"],
                       "only connected providers, sorted")
        XCTAssertNil(vm.loadError)
    }

    func testLoadConnectedProvidersSurfacesError() async {
        let backend = FakeBackend()
        await backend.setList(.failure(NotovaBackendClient.BackendError.http(500)))
        let (vm, _) = await makeContext(backend: backend)

        await vm.loadConnectedProviders()

        XCTAssertTrue(vm.connectedProviders.isEmpty)
        XCTAssertEqual(vm.loadError, "Something went wrong (HTTP 500). Please try again.")
    }

    func testExportBuildsCorrectCallAndMapsSuccess() async {
        let note = AuthFixtures.note()
        let backend = FakeBackend()
        await backend.setExport(.success(BackendDTO.export(externalId: "ext-99",
                                                           url: "https://notion.so/page",
                                                           status: "exported")))
        let (vm, _) = await makeContext(backend: backend, note: note)

        await vm.export(to: "notion")

        // The export call targeted the right provider + recording.
        let call = await backend.exportCalls.first
        XCTAssertEqual(call?.provider, "notion")
        XCTAssertEqual(call?.recordingId, note.recording.id)

        guard case let .success(provider, externalId, url, status) = vm.result else {
            return XCTFail("expected success, got \(String(describing: vm.result))")
        }
        XCTAssertEqual(provider, "notion")
        XCTAssertEqual(externalId, "ext-99")
        XCTAssertEqual(url, "https://notion.so/page")
        XCTAssertEqual(status, .exported)
    }

    func testExportMapsQueuedStatusWithNilURL() async {
        let backend = FakeBackend()
        await backend.setExport(.success(BackendDTO.export(externalId: "q-1", url: nil, status: "queued")))
        let (vm, _) = await makeContext(backend: backend)

        await vm.export(to: "slack")

        guard case let .success(_, _, url, status) = vm.result else {
            return XCTFail("expected success")
        }
        XCTAssertNil(url)
        XCTAssertEqual(status, .queued)
    }

    func testExportMapsErrorToFailure() async {
        let backend = FakeBackend()
        await backend.setExport(.failure(NotovaBackendClient.BackendError.http(503)))
        let (vm, _) = await makeContext(backend: backend)

        await vm.export(to: "notion")

        guard case let .failure(message) = vm.result else {
            return XCTFail("expected failure, got \(String(describing: vm.result))")
        }
        XCTAssertEqual(message, "Something went wrong (HTTP 503). Please try again.")
    }

    func testExportProviderNotConfiguredFailureMessage() async {
        let backend = FakeBackend()
        await backend.setExport(.failure(NotovaBackendClient.BackendError.http(501)))
        let (vm, _) = await makeContext(backend: backend)

        await vm.export(to: "salesforce")

        guard case let .failure(message) = vm.result else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(message,
                       "Salesforce isn't configured on the server yet. Add its OAuth credentials to enable it.")
    }

    func testExportWithoutContentFailsFast() async {
        let backend = FakeBackend()
        let (vm, _) = await makeContext(backend: backend, note: AuthFixtures.note(withContent: false))

        await vm.export(to: "notion")

        guard case let .failure(message) = vm.result else {
            return XCTFail("expected failure")
        }
        let exportCalls = await backend.exportCalls
        XCTAssertEqual(message, "This note has no summary or transcript to export yet.")
        XCTAssertTrue(exportCalls.isEmpty, "must not hit the backend without content")
    }

    func testExportRetriesOnceOn401() async {
        let backend = FakeBackend()
        await backend.setFailAuthorizedTimes(1)
        let (vm, _) = await makeContext(backend: backend)

        await vm.export(to: "notion")

        let refreshCount = await backend.refreshCalls.count
        guard case .success = vm.result else {
            return XCTFail("expected success after refresh, got \(String(describing: vm.result))")
        }
        XCTAssertEqual(refreshCount, 1)
    }
}
