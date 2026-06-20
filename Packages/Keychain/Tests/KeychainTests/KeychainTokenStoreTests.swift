import XCTest
@testable import Keychain

final class KeychainTokenStoreTests: XCTestCase {

    /// Each test uses a unique service name so it never collides with the real
    /// app item or with other tests, and tears its item down afterwards.
    private func makeStore(function: String = #function) -> KeychainTokenStore {
        KeychainTokenStore(service: "com.notova.app.tests.\(function).\(UUID().uuidString)",
                           account: "tokens")
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = makeStore()
        defer { try? store.clear() }

        let tokens = AuthTokens(accessToken: "acc-123", refreshToken: "ref-456")
        try store.save(tokens)

        let loaded = try store.load()
        XCTAssertEqual(loaded, tokens)
    }

    func testLoadReturnsNilWhenEmpty() throws {
        let store = makeStore()
        defer { try? store.clear() }
        XCTAssertNil(try store.load())
    }

    func testSaveOverwritesExistingValue() throws {
        let store = makeStore()
        defer { try? store.clear() }

        try store.save(AuthTokens(accessToken: "old-a", refreshToken: "old-r"))
        try store.save(AuthTokens(accessToken: "new-a", refreshToken: "new-r"))

        let loaded = try store.load()
        XCTAssertEqual(loaded?.accessToken, "new-a")
        XCTAssertEqual(loaded?.refreshToken, "new-r")
    }

    func testClearRemovesTokens() throws {
        let store = makeStore()
        try store.save(AuthTokens(accessToken: "a", refreshToken: "r"))
        XCTAssertNotNil(try store.load())

        try store.clear()
        XCTAssertNil(try store.load())
    }

    func testClearOnEmptyStoreIsNoOp() throws {
        let store = makeStore()
        XCTAssertNoThrow(try store.clear())
    }

    func testStoresAreIsolatedByServiceName() throws {
        let storeA = KeychainTokenStore(service: "com.notova.app.tests.isolation.A.\(UUID().uuidString)")
        let storeB = KeychainTokenStore(service: "com.notova.app.tests.isolation.B.\(UUID().uuidString)")
        defer { try? storeA.clear(); try? storeB.clear() }

        try storeA.save(AuthTokens(accessToken: "a-only", refreshToken: "a-ref"))
        XCTAssertEqual(try storeA.load()?.accessToken, "a-only")
        XCTAssertNil(try storeB.load(), "a different service name must not see A's tokens")
    }

    func testInMemoryStoreRoundTrips() throws {
        let store = InMemoryTokenStore()
        XCTAssertNil(try store.load())
        let tokens = AuthTokens(accessToken: "x", refreshToken: "y")
        try store.save(tokens)
        XCTAssertEqual(try store.load(), tokens)
        try store.clear()
        XCTAssertNil(try store.load())
    }
}
