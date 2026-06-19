import Foundation

/// Records the request as seen by the transport (headers + body are captured
/// before the protocol consumes the stream).
struct CapturedRequest: @unchecked Sendable {
    let url: URL?
    let method: String?
    let headers: [String: String]
    let body: Data?

    var bodyJSON: [String: Any]? {
        guard let body, let obj = try? JSONSerialization.jsonObject(with: body) else { return nil }
        return obj as? [String: Any]
    }

    var bodyString: String? { body.flatMap { String(data: $0, encoding: .utf8) } }
}

/// What the stub should return for a matched request.
struct StubResponse: @unchecked Sendable {
    let statusCode: Int
    let body: Data
    let headers: [String: String]

    init(statusCode: Int = 200, body: Data = Data(), headers: [String: String] = ["Content-Type": "application/json"]) {
        self.statusCode = statusCode
        self.body = body
        self.headers = headers
    }

    static func json(_ string: String, status: Int = 200) -> StubResponse {
        StubResponse(statusCode: status, body: Data(string.utf8))
    }
}

/// Thread-safe holder for the request handler + captured requests, shared with
/// the URLProtocol subclass (which is instantiated by URLSession on arbitrary
/// queues).
final class StubState: @unchecked Sendable {
    static let shared = StubState()
    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) -> StubResponse)?
    private var captured: [CapturedRequest] = []

    func reset() {
        lock.withLock {
            handler = nil
            captured = []
        }
    }

    func setHandler(_ handler: @escaping @Sendable (URLRequest) -> StubResponse) {
        lock.withLock { self.handler = handler }
    }

    func capture(_ request: URLRequest) {
        // Reconstitute the body: URLProtocol strips httpBody into a stream for
        // streamed uploads, so check both.
        let body = request.httpBody ?? request.bodyStreamData()
        let captured = CapturedRequest(
            url: request.url,
            method: request.httpMethod,
            headers: request.allHTTPHeaderFields ?? [:],
            body: body
        )
        lock.withLock { self.captured.append(captured) }
    }

    func response(for request: URLRequest) -> StubResponse {
        lock.withLock { handler?(request) } ?? StubResponse(statusCode: 599, body: Data())
    }

    var requests: [CapturedRequest] {
        lock.withLock { captured }
    }

    var lastRequest: CapturedRequest? {
        lock.withLock { captured.last }
    }
}

private extension URLRequest {
    func bodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}

/// A URLProtocol that intercepts every request, records it, and returns a
/// canned response — no real network ever happens.
final class StubURLProtocol: URLProtocol {
    // These are required `class func` overrides from URLProtocol; they cannot be `static`.
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        StubState.shared.capture(request)
        let stub = StubState.shared.response(for: request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://invalid")!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// A URLSession wired to use this protocol exclusively.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}
