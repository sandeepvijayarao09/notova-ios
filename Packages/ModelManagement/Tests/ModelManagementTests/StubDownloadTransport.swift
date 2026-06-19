import Foundation
@testable import ModelManagement

/// A `DownloadTransport` that serves canned bytes through a real `URLSession`
/// wired to an intercepting `URLProtocol` — so the production byte-streaming
/// path runs without touching the network.
struct StubDownloadTransport: DownloadTransport {
    let body: Data
    let contentLength: Int64
    let statusCode: Int

    init(body: Data, contentLength: Int64, statusCode: Int = 200) {
        self.body = body
        self.contentLength = contentLength
        self.statusCode = statusCode
    }

    func bytes(from url: URL) async throws -> (URLSession.AsyncBytes, URLResponse) {
        StubDownloadState.shared.configure(body: body, contentLength: contentLength, statusCode: statusCode)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubDownloadProtocol.self]
        let session = URLSession(configuration: config)
        return try await session.bytes(from: url)
    }
}

/// Thread-safe holder for the canned response shared with the URLProtocol
/// subclass (instantiated by URLSession on arbitrary queues).
final class StubDownloadState: @unchecked Sendable {
    static let shared = StubDownloadState()
    private let lock = NSLock()
    private var body = Data()
    private var contentLength: Int64 = 0
    private var statusCode = 200

    func configure(body: Data, contentLength: Int64, statusCode: Int) {
        lock.withLock {
            self.body = body
            self.contentLength = contentLength
            self.statusCode = statusCode
        }
    }

    struct Snapshot: Sendable {
        let body: Data
        let contentLength: Int64
        let statusCode: Int
    }

    var current: Snapshot {
        lock.withLock { Snapshot(body: body, contentLength: contentLength, statusCode: statusCode) }
    }
}

final class StubDownloadProtocol: URLProtocol {
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        let state = StubDownloadState.shared.current
        var headers: [String: String] = ["Content-Type": "application/octet-stream"]
        if state.contentLength >= 0 {
            headers["Content-Length"] = String(state.contentLength)
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://invalid")!,
            statusCode: state.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !state.body.isEmpty {
            client?.urlProtocol(self, didLoad: state.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
