import Foundation
import AVFoundation

/// Helper for requesting microphone permission.
public enum MicrophonePermission {
    public static func request() async -> Bool {
        #if canImport(UIKit)
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        return true
        #endif
    }
}
