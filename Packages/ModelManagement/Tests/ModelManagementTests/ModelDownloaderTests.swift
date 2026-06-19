import XCTest
@testable import ModelManagement

final class ModelDownloaderTests: XCTestCase {
    private var tempDir: URL!
    private var store: ModelStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelDownloaderTests-\(UUID().uuidString)")
        store = ModelStore(directory: tempDir.appendingPathComponent("Models"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func collect(_ stream: AsyncThrowingStream<ModelDownloadEvent, Error>) async throws -> [ModelDownloadEvent] {
        var events: [ModelDownloadEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    func testDownloadCompletesAndStoresFile() async throws {
        let payload = Data(repeating: 0x41, count: 200 * 1024) // 200 KiB to force multiple flushes
        let transport = StubDownloadTransport(body: payload, contentLength: Int64(payload.count))
        let downloader = ModelDownloader(store: store, transport: transport)

        let events = try await collect(
            downloader.download(from: URL(string: "https://example.com/model.gguf")!, filename: "model.gguf")
        )

        guard case let .finished(url) = events.last else {
            return XCTFail("expected a finished event, got \(String(describing: events.last))")
        }
        XCTAssertEqual(url.lastPathComponent, "model.gguf")
        XCTAssertEqual(try Data(contentsOf: url), payload)
        XCTAssertEqual(try store.installedModels().map(\.name), ["model.gguf"])
    }

    func testProgressIsMonotonicAndReachesCompletion() async throws {
        let payload = Data(repeating: 0x42, count: 300 * 1024)
        let transport = StubDownloadTransport(body: payload, contentLength: Int64(payload.count))
        let downloader = ModelDownloader(store: store, transport: transport)

        let events = try await collect(
            downloader.download(from: URL(string: "https://example.com/m.gguf")!, filename: "m.gguf")
        )

        let fractions: [Double] = events.compactMap {
            if case let .progress(fraction, _, _) = $0 { return fraction }
            return nil
        }
        XCTAssertFalse(fractions.isEmpty, "should emit progress")
        XCTAssertEqual(fractions, fractions.sorted(), "progress must be monotonic")
        XCTAssertEqual(try XCTUnwrap(fractions.last), 1.0, accuracy: 0.0001, "final progress should be 1.0")

        let lastBytes: Int64 = events.compactMap {
            if case let .progress(_, written, _) = $0 { return written }
            return nil
        }.last ?? 0
        XCTAssertEqual(lastBytes, Int64(payload.count))
    }

    func testUnknownContentLengthYieldsNilFractionUntilEnd() async throws {
        let payload = Data(repeating: 0x43, count: 100 * 1024)
        let transport = StubDownloadTransport(body: payload, contentLength: -1)
        let downloader = ModelDownloader(store: store, transport: transport)

        let events = try await collect(
            downloader.download(from: URL(string: "https://example.com/u.gguf")!, filename: "u.gguf")
        )
        // The mid-stream progress events have nil fraction; the final event is 1.0.
        let fractions = events.compactMap { event -> Double?? in
            if case let .progress(fraction, _, _) = event { return .some(fraction) }
            return nil
        }
        XCTAssertEqual(fractions.last, .some(1.0))
        guard case .finished = events.last else { return XCTFail("expected finished") }
    }

    func testBadStatusThrows() async {
        let transport = StubDownloadTransport(body: Data("nope".utf8), contentLength: 4, statusCode: 404)
        let downloader = ModelDownloader(store: store, transport: transport)
        do {
            _ = try await collect(
                downloader.download(from: URL(string: "https://example.com/x")!, filename: "x.gguf")
            )
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? ModelDownloadError, .badStatus(404))
        }
        let installed = (try? store.installedModels()) ?? []
        XCTAssertTrue(installed.isEmpty)
    }

    func testEmptyBodyThrows() async {
        let transport = StubDownloadTransport(body: Data(), contentLength: 0)
        let downloader = ModelDownloader(store: store, transport: transport)
        do {
            _ = try await collect(
                downloader.download(from: URL(string: "https://example.com/x")!, filename: "x.gguf")
            )
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? ModelDownloadError, .emptyResponse)
        }
    }
}
