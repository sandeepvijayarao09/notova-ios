import Foundation
import SwiftUI
import NotovaCore
import AudioCapture
import Persistence

@Observable
@MainActor
final class RecordViewModel {
    enum State: Equatable {
        case idle
        case recording
        case processing
        case done(String)
        case failed(String)
    }

    var state: State = .idle
    var statusMessage: String = "Tap to record, or import an audio file."

    private let audioSource: any AudioSource
    private let pipeline: PipelineService
    private let repository: NoteRepository
    private let requestPermission: @Sendable () async -> Bool

    init(
        audioSource: any AudioSource,
        pipeline: PipelineService,
        repository: NoteRepository,
        requestPermission: @escaping @Sendable () async -> Bool = { await MicrophonePermission.request() }
    ) {
        self.audioSource = audioSource
        self.pipeline = pipeline
        self.repository = repository
        self.requestPermission = requestPermission
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    func toggleRecording() async {
        if isRecording {
            await stopAndProcess()
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        let granted = await requestPermission()
        guard granted else {
            state = .failed("Microphone permission denied.")
            statusMessage = "Enable microphone access in Settings."
            return
        }
        do {
            try await audioSource.start()
            state = .recording
            statusMessage = "Recording… tap to stop."
        } catch {
            state = .failed(error.localizedDescription)
            statusMessage = "Could not start recording."
        }
    }

    func stopAndProcess() async {
        do {
            let result = try await audioSource.stop()
            await process(result: result, defaultTitle: "Voice note")
        } catch {
            state = .failed(error.localizedDescription)
            statusMessage = "Recording failed."
        }
    }

    func importFile(at url: URL) async {
        do {
            // Security-scoped access for files picked outside the sandbox.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let result = try await audioSource.loadFile(at: url)
            await process(result: result, defaultTitle: url.deletingPathExtension().lastPathComponent)
        } catch {
            state = .failed(error.localizedDescription)
            statusMessage = "Could not import file."
        }
    }

    private func process(result: AudioCaptureResult, defaultTitle: String) async {
        state = .processing
        statusMessage = "Transcribing and summarizing on-device…"

        let recording = Recording(
            title: defaultTitle,
            durationSec: result.durationSec,
            source: result.source,
            localAudioPath: result.fileURL.path,
            status: .processing
        )

        do {
            let note = try await pipeline.process(recording: recording, audioURL: result.fileURL)
            try repository.save(note)
            state = .done(note.recording.title)
            statusMessage = "Saved \"\(note.recording.title)\"."
        } catch {
            state = .failed(error.localizedDescription)
            statusMessage = "Processing failed."
        }
    }
}
