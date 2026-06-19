import Foundation

// MARK: - Download progress

/// Progress events emitted while a model downloads.
public enum ModelDownloadEvent: Sendable, Equatable {
    /// Fractional progress in `0...1` plus raw byte counts. `fraction` is `nil`
    /// when the server didn't send a content length.
    case progress(fraction: Double?, bytesWritten: Int64, totalBytes: Int64)
    /// The download finished and the file was promoted into the `ModelStore`.
    case finished(url: URL)
}

public enum ModelDownloadError: Error, Sendable, Equatable {
    case badStatus(Int)
    case emptyResponse
    case cancelled
}

// MARK: - URLSession seam (testable)

/// Minimal seam over the bytes-streaming part of `URLSession` so the downloader
/// can be tested with a stubbed `URLProtocol` without real network I/O.
public protocol DownloadTransport: Sendable {
    /// Stream the bytes of `url` along with the response (for status + length).
    func bytes(from url: URL) async throws -> (URLSession.AsyncBytes, URLResponse)
}

/// Production transport backed by a real `URLSession`.
public struct URLSessionDownloadTransport: DownloadTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func bytes(from url: URL) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try await session.bytes(from: url)
    }
}

// MARK: - ModelDownloader

/// Downloads a model file from a URL into the `ModelStore`, reporting progress
/// via an `AsyncStream`. Streams bytes to a temp file (so large models never sit
/// in memory) and promotes the finished file into the store.
///
/// Not a giant hardcoded download: the caller supplies the URL + expected
/// filename. Cancellation is honored cooperatively (Swift task cancellation).
public final class ModelDownloader: Sendable {
    private let transport: DownloadTransport
    private let store: ModelStore

    public init(store: ModelStore, transport: DownloadTransport = URLSessionDownloadTransport()) {
        self.store = store
        self.transport = transport
    }

    /// Download `url` into the store as `filename`, yielding progress events.
    /// The stream finishes after a `.finished` event (success) or by throwing.
    public func download(from url: URL, filename: String) -> AsyncThrowingStream<ModelDownloadEvent, Error> {
        let transport = self.transport
        let store = self.store
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = try await Self.run(
                        transport: transport,
                        store: store,
                        url: url,
                        filename: filename
                    ) { event in
                        continuation.yield(event)
                    }
                    continuation.yield(.finished(url: url))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ModelDownloadError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Core streaming routine, factored out so it can be exercised directly.
    static func run(
        transport: DownloadTransport,
        store: ModelStore,
        url: URL,
        filename: String,
        onEvent: @Sendable (ModelDownloadEvent) -> Void
    ) async throws -> URL {
        let (bytes, response) = try await transport.bytes(from: url)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ModelDownloadError.badStatus(http.statusCode)
        }

        let expected = response.expectedContentLength // -1 when unknown
        let total = expected > 0 ? expected : 0

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notova-dl-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)
        defer { try? handle.close() }

        var written: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        let flushThreshold = 64 * 1024

        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            written += 1
            if buffer.count >= flushThreshold {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                let fraction = total > 0 ? Double(written) / Double(total) : nil
                onEvent(.progress(fraction: fraction, bytesWritten: written, totalBytes: total))
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        try handle.close()

        let fraction = total > 0 ? Double(written) / Double(total) : 1.0
        onEvent(.progress(fraction: fraction, bytesWritten: written, totalBytes: max(total, written)))

        guard written > 0 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw ModelDownloadError.emptyResponse
        }

        return try store.adoptModel(at: tempURL, named: filename)
    }
}
