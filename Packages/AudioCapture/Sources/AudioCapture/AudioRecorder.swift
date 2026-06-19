import Foundation
import AVFoundation
import NotovaCore

/// Captures audio from the active input route (built-in mic, Bluetooth HFP, or
/// other connected input device) using `AVAudioRecorder`, and supports importing
/// an existing audio file. Conforms to `AudioSource`.
///
/// Route selection is delegated to `AVAudioSession`: by enabling
/// `.allowBluetooth` / `.allowBluetoothA2DP` the system records from a paired
/// Bluetooth mic when one is the preferred input; otherwise the built-in mic is
/// used. The chosen route is reflected in the reported `Recording.Source`.
public final class AudioRecorder: NSObject, AudioSource, @unchecked Sendable {
    private let lock = NSLock()
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?
    private let outputDirectory: URL

    public init(outputDirectory: URL? = nil) {
        self.outputDirectory = outputDirectory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        super.init()
    }

    // MARK: - AudioSource

    public func start() async throws {
        let url = outputDirectory
            .appendingPathComponent("notova-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        #if canImport(UIKit)
        try configureSessionForRecording()
        #endif

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                throw NotovaError.audioCaptureFailed("AVAudioRecorder failed to start")
            }
            lock.withLock {
                self.recorder = recorder
                self.currentURL = url
            }
        } catch let error as NotovaError {
            throw error
        } catch {
            throw NotovaError.audioCaptureFailed(error.localizedDescription)
        }
    }

    public func stop() async throws -> AudioCaptureResult {
        let (recorder, url) = lock.withLock { (self.recorder, self.currentURL) }
        guard let recorder, let url else {
            throw NotovaError.audioCaptureFailed("No active recording")
        }

        let duration = recorder.currentTime
        recorder.stop()
        lock.withLock {
            self.recorder = nil
            self.currentURL = nil
        }

        let source = detectSource()

        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        let resolvedDuration = duration > 0 ? duration : (try? Self.duration(of: url)) ?? 0
        return AudioCaptureResult(fileURL: url, durationSec: resolvedDuration, source: source)
    }

    public func loadFile(at url: URL) async throws -> AudioCaptureResult {
        let supported: Set<String> = ["m4a", "mp3", "wav", "aac", "caf", "aiff", "aif", "mp4"]
        guard supported.contains(url.pathExtension.lowercased()) else {
            throw NotovaError.unsupportedFile("Unsupported audio extension: .\(url.pathExtension)")
        }
        let duration = (try? Self.duration(of: url)) ?? 0
        return AudioCaptureResult(fileURL: url, durationSec: duration, source: .file)
    }

    // MARK: - Helpers

    private static func duration(of url: URL) throws -> Double {
        let player = try AVAudioPlayer(contentsOf: url)
        return player.duration
    }

    private func detectSource() -> Recording.Source {
        #if canImport(UIKit)
        let inputs = AVAudioSession.sharedInstance().currentRoute.inputs
        if let port = inputs.first {
            switch port.portType {
            case .bluetoothHFP, .bluetoothLE, .bluetoothA2DP:
                return .bluetooth
            case .builtInMic:
                return .mic
            default:
                return .other
            }
        }
        #endif
        return .mic
    }

    #if canImport(UIKit)
    private func configureSessionForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setActive(true, options: [])
        } catch {
            throw NotovaError.audioCaptureFailed("Audio session setup failed: \(error.localizedDescription)")
        }
    }
    #endif
}
