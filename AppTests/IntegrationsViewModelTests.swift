import XCTest
import NotovaCore
import Integrations
import Keychain
@testable import Notova

@MainActor
final class IntegrationsViewModelTests: XCTestCase {

    private func makeContext(
        backend: FakeBackend = FakeBackend(),
        authorize: @escaping @MainActor (URL) async throws -> URL = { _ in
            URL(string: "notova://oauth/notion?status=connected")!
        }
    ) async -> (IntegrationsViewModel, FakeBackend) {
        let store = InMemoryTokenStore(tokens: AuthTokens(accessToken: "a", refreshToken: "r"))
        let session = SessionStore(backend: backend, tokenStore: store)
        await session.restore()
        let vm = IntegrationsViewModel(backend: backend, session: session, authorize: authorize)
        return (vm, backend)
    }

    // MARK: - Listing

    func testRefreshLoadsAndSortsRows() async {
        let backend = FakeBackend()
        await backend.setList(.success(BackendDTO.integrations([
            ("notion", false),
            ("google", true)
        ])))
        let (vm, _) = await makeContext(backend: backend)

        await vm.refresh()

        XCTAssertEqual(vm.rows.map(\.provider), ["google", "notion"])
        XCTAssertTrue(vm.rows[0].connected)
        XCTAssertFalse(vm.rows[1].connected)
        XCTAssertNil(vm.errorMessage)
    }

    func testRefreshSurfacesError() async {
        let backend = FakeBackend()
        await backend.setList(.failure(NotovaBackendClient.BackendError.http(500)))
        let (vm, _) = await makeContext(backend: backend)

        await vm.refresh()

        XCTAssertTrue(vm.rows.isEmpty)
        XCTAssertEqual(vm.errorMessage, "Something went wrong (HTTP 500). Please try again.")
    }

    // MARK: - Connect

    func testConnectOpensAuthorizeUrlAndRefreshesOnConnectedCallback() async {
        let backend = FakeBackend()
        await backend.setConnect(.success(BackendDTO.connect(authorizeUrl: "https://provider.example/auth", state: "st")))
        // After the callback, the list reports notion connected.
        await backend.setList(.success(BackendDTO.integrations([("notion", true)])))

        var openedURL: URL?
        let (vm, _) = await makeContext(backend: backend, authorize: { url in
            openedURL = url
            return URL(string: "notova://oauth/notion?status=connected")!
        })

        await vm.connect(provider: "notion")

        let connectCalls = await backend.connectCalls
        XCTAssertEqual(openedURL?.absoluteString, "https://provider.example/auth")
        XCTAssertEqual(connectCalls, ["notion"])
        XCTAssertEqual(vm.statusMessage, "Connected Notion.")
        XCTAssertEqual(vm.rows.first?.provider, "notion")
        XCTAssertTrue(vm.rows.first?.connected ?? false)
    }

    func testConnectCancelledIsNotAnError() async {
        let backend = FakeBackend()
        let (vm, _) = await makeContext(backend: backend, authorize: { _ in
            throw ASWebAuthError.canceled
        })

        await vm.connect(provider: "notion")

        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.statusMessage, "Connection cancelled.")
    }

    func testConnectProviderNotConfiguredShowsDevSafeMessage() async {
        let backend = FakeBackend()
        await backend.setConnect(.failure(NotovaBackendClient.BackendError.http(501)))
        let (vm, _) = await makeContext(backend: backend)

        await vm.connect(provider: "salesforce")

        XCTAssertEqual(vm.errorMessage,
                       "Salesforce isn't configured on the server yet. Add its OAuth credentials to enable it.")
    }

    func testConnectInvalidAuthorizeUrlSurfacesError() async {
        let backend = FakeBackend()
        await backend.setConnect(.success(BackendDTO.connect(authorizeUrl: "", state: "st")))
        let (vm, _) = await makeContext(backend: backend)

        await vm.connect(provider: "notion")

        XCTAssertEqual(vm.errorMessage, "The provider returned an invalid authorization URL.")
    }

    // MARK: - Disconnect

    func testDisconnectCallsBackendAndRefreshes() async {
        let backend = FakeBackend()
        await backend.setList(.success(BackendDTO.integrations([("notion", false)])))
        let (vm, _) = await makeContext(backend: backend)

        await vm.disconnect(provider: "notion")

        let disconnectCalls = await backend.disconnectCalls
        XCTAssertEqual(disconnectCalls, ["notion"])
        XCTAssertEqual(vm.statusMessage, "Disconnected Notion.")
        XCTAssertFalse(vm.rows.first?.connected ?? true)
    }

    // MARK: - Callback parsing

    func testParseCallbackHostForm() {
        let url = URL(string: "notova://oauth/notion?status=connected")!
        let result = IntegrationsViewModel.parseCallback(url)
        XCTAssertEqual(result, .init(provider: "notion", status: "connected"))
        XCTAssertTrue(result?.isConnected ?? false)
    }

    func testParseCallbackDefaultsStatusToConnectedWhenMissing() {
        let url = URL(string: "notova://oauth/slack")!
        XCTAssertEqual(IntegrationsViewModel.parseCallback(url),
                       .init(provider: "slack", status: "connected"))
    }

    func testParseCallbackErrorStatus() {
        let url = URL(string: "notova://oauth/google?status=error")!
        let result = IntegrationsViewModel.parseCallback(url)
        XCTAssertEqual(result?.status, "error")
        XCTAssertFalse(result?.isConnected ?? true)
    }

    func testParseCallbackRejectsWrongScheme() {
        XCTAssertNil(IntegrationsViewModel.parseCallback(URL(string: "https://example.com/oauth/notion")!))
    }

    func testHandleCallbackConnectedRefreshesList() async {
        let backend = FakeBackend()
        await backend.setList(.success(BackendDTO.integrations([("notion", true)])))
        let (vm, _) = await makeContext(backend: backend)

        await vm.handleCallback(url: URL(string: "notova://oauth/notion?status=connected")!)

        let listCallCount = await backend.listCallCount
        XCTAssertEqual(vm.statusMessage, "Connected Notion.")
        XCTAssertTrue(vm.rows.first?.connected ?? false)
        XCTAssertGreaterThanOrEqual(listCallCount, 1)
    }

    func testHandleCallbackNonConnectedSurfacesError() async {
        let (vm, _) = await makeContext()
        await vm.handleCallback(url: URL(string: "notova://oauth/notion?status=denied")!)
        XCTAssertEqual(vm.errorMessage, "Notion did not finish connecting (denied).")
    }

    func testHandleCallbackUnrecognizedURLSurfacesError() async {
        let (vm, _) = await makeContext()
        await vm.handleCallback(url: URL(string: "https://example.com/whatever")!)
        XCTAssertEqual(vm.errorMessage, "Received an unexpected callback from the provider.")
    }

    // MARK: - 401 retry through the session

    func testRefreshRetriesOnceOn401() async {
        let backend = FakeBackend()
        await backend.setList(.success(BackendDTO.integrations([("notion", true)])))
        await backend.setFailAuthorizedTimes(1) // first list 401s, retry succeeds
        let (vm, _) = await makeContext(backend: backend)

        await vm.refresh()

        let refreshCount = await backend.refreshCalls.count
        XCTAssertEqual(vm.rows.first?.provider, "notion")
        XCTAssertEqual(refreshCount, 1)
        XCTAssertNil(vm.errorMessage)
    }
}
