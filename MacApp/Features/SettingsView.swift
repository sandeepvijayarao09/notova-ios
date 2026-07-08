import SwiftUI

/// Settings / about. Surfaces the privacy posture and which on-device engines are actually active.
/// The names come from the live resolver chain on `AppModel` (Apple Speech / Foundation Models /
/// Gemma, degrading to the built-in sample engine), so this screen reflects what really runs —
/// Whisper / Gemma 3n drop in behind the same `NotovaCore` protocols without touching this view.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("On-device AI") {
                LabeledContent("Transcription", value: model.activeTranscriberName)
                LabeledContent("Summarization", value: model.activeSummarizerName)
                Text("Notova picks the first available on-device engine. If none is ready it uses "
                    + "the built-in sample engine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Label(
                    "Audio, transcripts, and summaries are processed entirely on this Mac. "
                        + "The backend only handles accounts, sync, and export.",
                    systemImage: "lock.shield"
                )
                .foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("App", value: "Notova")
                LabeledContent("Version", value: appVersion)
                LabeledContent("Bundle", value: "com.notova.mac")
                Link("Privacy Policy", destination: Self.privacyPolicyURL)
                Link("Support", destination: Self.supportURL)
                Text("Open source under the Apache 2.0 License.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task { await model.refreshEngineNames() }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    static let privacyPolicyURL = URL(
        string: "https://github.com/sandeepvijayarao09/notova-ios/blob/main/docs/privacy-policy.md"
    )!
    static let supportURL = URL(
        string: "https://github.com/sandeepvijayarao09/notova-ios/blob/main/SUPPORT.md"
    )!
}
