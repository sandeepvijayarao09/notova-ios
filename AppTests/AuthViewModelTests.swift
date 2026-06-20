import XCTest
import NotovaCore
import Integrations
import Keychain
@testable import Notova

@MainActor
final class SessionStoreTests: XCTestCase {

    private func makeSession(
        backend: FakeBackend = FakeBackend(),
        store: InMemoryTokenStore = InMemoryTokenStore()
    ) -> SessionStore {
        SessionStore(backend: backend, tokenStore: store)
    }

    // MARK: - Restore on launch

    func testRestoreWithNoTokenGoesSignedOut() async {
        let session = makeSession()
        await session.restore()
        XCTAssertEqual(session.phase, .signedOut)
    }

    func testRestoreWithValidTokenSignsInAndAppliesToken() async {
        let backend = FakeBackend()
        let store = InMemoryTokenStore(tokens: AuthTokens(accessToken: "stored-acc", refreshToken: "stored-ref"))
        let session = makeSession(backend: backend, store: store)

        await session.restore()

        XCTAssertEqual(session.phase, .signedIn(email: "user@notova.app"))
        // The stored access token must have been pushed onto the client.
        let applied = await backend.lastToken
        XCTAssertEqual(applied, "stored-acc")
    }

    func testRestoreWith401RefreshesOnceThenSignsIn() async {
        let backend = FakeBackend()
        // First /me (during restore) 401s; refresh succeeds; second /me works.
        await backend.setFailAuthorizedTimes(1)
        let store = InMemoryTokenStore(tokens: AuthTokens(accessToken: "old", refreshToken: "ref"))
        let session = makeSession(backend: backend, store: store)

        await session.restore()

        let refreshCalls = await backend.refreshCalls
        let lastToken = await backend.lastToken
        if case .signedIn = session.phase {} else {
            XCTFail("expected signedIn after a successful refresh, got \(session.phase)")
        }
        XCTAssertEqual(refreshCalls, ["ref"])
        // Latest token applied should be the refreshed one.
        XCTAssertEqual(lastToken, "access-2")
    }

    func testRestoreWith401AndFailedRefreshSignsOut() async {
        let backend = FakeBackend()
        await backend.setMe(.failure(NotovaBackendClient.BackendError.unauthorized))
        await backend.setRefresh(.failure(NotovaBackendClient.BackendError.unauthorized))
        let store = InMemoryTokenStore(tokens: AuthTokens(accessToken: "old", refreshToken: "ref"))
        let session = makeSession(backend: backend, store: store)

        await session.restore()

        XCTAssertEqual(session.phase, .signedOut)
        XCTAssertNil(try store.load(), "failed refresh must clear stored tokens")
    }

    // MARK: - Sign out

    func testSignOutClearsTokensAndClient() async {
        let backend = FakeBackend()
        let store = InMemoryTokenStore()
        let session = makeSession(backend: backend, store: store)
        try? store.save(AuthTokens(accessToken: "a", refreshToken: "r"))

        await session.signOut()

        let lastToken = await backend.lastToken
        XCTAssertEqual(session.phase, .signedOut)
        XCTAssertNil(session.userEmail)
        XCTAssertNil(try store.load())
        XCTAssertNil(lastToken)
    }

    // MARK: - withAuthRetry

    func testWithAuthRetrySucceedsImmediately() async throws {
        let backend = FakeBackend()
        let session = makeSession(backend: backend,
                                  store: InMemoryTokenStore(tokens: .init(accessToken: "a", refreshToken: "r")))
        await session.restore()
        let value = try await session.withAuthRetry { 42 }
        XCTAssertEqual(value, 42)
    }

    func testWithAuthRetryRefreshesOnceOn401() async throws {
        let backend = FakeBackend()
        let session = makeSession(backend: backend,
                                  store: InMemoryTokenStore(tokens: .init(accessToken: "a", refreshToken: "r")))
        await session.restore()

        let attempts = Counter()
        let value: Int = try await session.withAuthRetry {
            let count = await attempts.increment()
            if count == 1 { throw NotovaBackendClient.BackendError.unauthorized }
            return 7
        }
        let attemptCount = await attempts.value
        let refreshCount = await backend.refreshCalls.count
        XCTAssertEqual(value, 7)
        XCTAssertEqual(attemptCount, 2, "should retry exactly once after refresh")
        XCTAssertEqual(refreshCount, 1)
    }
}

@MainActor
final class AuthViewModelTests: XCTestCase {

    private func makeContext(
        backend: FakeBackend = FakeBackend()
    ) -> (AuthViewModel, AuthTestContext) {
        let store = InMemoryTokenStore()
        let session = SessionStore(backend: backend, tokenStore: store)
        let context = AuthTestContext(session: session, store: store, backend: backend)
        return (AuthViewModel(session: session), context)
    }

    func testCanSubmitRequiresBothFields() {
        let (vm, _) = makeContext()
        XCTAssertFalse(vm.canSubmit)
        vm.email = "a@b.com"
        XCTAssertFalse(vm.canSubmit)
        vm.password = "pw"
        XCTAssertTrue(vm.canSubmit)
    }

    func testSignInSuccessStoresTokenAndAdvances() async {
        let (vm, context) = makeContext()
        vm.email = "  user@notova.app "
        vm.password = "secret"

        await vm.signIn()

        let lastToken = await context.backend.lastToken
        let firstLoginEmail = await context.backend.loginCalls.first?.email
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(context.session.phase, .signedIn(email: "user@notova.app"))
        XCTAssertEqual(try context.store.load(), AuthTokens(accessToken: "access-1", refreshToken: "refresh-1"))
        XCTAssertEqual(lastToken, "access-1")
        // Email is trimmed before being sent.
        XCTAssertEqual(firstLoginEmail, "user@notova.app")
        XCTAssertEqual(vm.password, "", "password is cleared after a successful sign-in")
    }

    func testRegisterSuccessStoresTokenAndAdvances() async {
        let (vm, context) = makeContext()
        vm.email = "new@notova.app"
        vm.password = "pw"

        await vm.createAccount()

        let registerCount = await context.backend.registerCalls.count
        XCTAssertEqual(context.session.phase, .signedIn(email: "user@notova.app"))
        XCTAssertNotNil(try context.store.load())
        XCTAssertEqual(registerCount, 1)
    }

    func testSignInFailureSurfacesErrorAndStaysSignedOut() async {
        let backend = FakeBackend()
        await backend.setLogin(.failure(NotovaBackendClient.BackendError.unauthorized))
        let (vm, context) = makeContext(backend: backend)
        vm.email = "user@notova.app"
        vm.password = "wrong"

        await vm.signIn()

        XCTAssertEqual(vm.errorMessage, "Incorrect email or password.")
        XCTAssertEqual(context.session.phase, .loading, "a failed login must not advance the session")
        XCTAssertNil(try context.store.load())
    }

    func testRegisterConflictSurfacesFriendlyError() async {
        let backend = FakeBackend()
        await backend.setRegister(.failure(NotovaBackendClient.BackendError.http(409)))
        let (vm, _) = makeContext(backend: backend)
        vm.email = "dupe@notova.app"
        vm.password = "pw"

        await vm.createAccount()

        XCTAssertEqual(vm.errorMessage, "An account with that email already exists.")
    }

    func testBusyFlagFalseAfterCompletion() async {
        let (vm, _) = makeContext()
        vm.email = "a@b.com"
        vm.password = "pw"
        await vm.signIn()
        XCTAssertFalse(vm.isBusy)
    }
}
