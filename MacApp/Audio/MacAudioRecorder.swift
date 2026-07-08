import AVFoundation
import Foundation
import NotovaCore

/// Native macOS `AudioSource`: records the default input device with `AVAudioEngine` (writing a
/// `.caf` file), and imports existing audio files. Marked `@unchecked Sendable` because it guards
/// its mutable engine state with a lock.
///
/// The lock is taken only inside synchronous helpers (`beginRecording`/`finishRecording`/`append`),
/// never across an `await` — Swift 6 forbids `NSLock` in async contexts, and holding a lock across a
/// suspension point would be a bug anyway.
final class MacAudioRecorder: AudioSource, @unchecked Sendable {
    private let lock = NSLock()
    private let engine = AVAudioEngine()
    private var outputFile: AVAudioFile?
    private var outputURL: URL?
    private var startedAt: Date?

    func start() async throws {
        try beginRecording()
    }

    func stop() async throws -> AudioCaptureResult {
        try finishRecording()
    }

    func loadFile(at url: URL) async throws -> AudioCaptureResult {
        let asset = AVURLAsset(url: url)
        let seconds: Double
        if let duration = try? await asset.load(.duration) {
            let value = CMTimeGetSeconds(duration)
            seconds = value.isFinite ? value : 0
        } else {
            seconds = 0
        }
        return AudioCaptureResult(fileURL: url, durationSec: seconds, source: .file)
    }

    // MARK: - Synchronous, locked engine control

    private func beginRecording() throws {
        lock.lock()
        defer { lock.unlock() }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            throw NotovaError.audioCaptureFailed("No audio input device available.")
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notova_rec_\(UUID().uuidString).caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        outputFile = file
        outputURL = url

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
        startedAt = Date()
    }

    private func finishRecording() throws -> AudioCaptureResult {
        lock.lock()
        defer { lock.unlock() }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        guard let url = outputURL else {
            throw NotovaError.audioCaptureFailed("Stop called with no active recording.")
        }
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        outputFile = nil
        outputURL = nil
        startedAt = nil
        return AudioCaptureResult(fileURL: url, durationSec: duration, source: .mic)
    }

    /// Render-thread callback: append captured PCM to the output file under the lock.
    private func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        try? outputFile?.write(from: buffer)
    }
}
