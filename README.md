# notova-ios

**Notova** for iOS — on-device AI voice capture & notes (SwiftUI). Record from any
mic, Bluetooth input, or imported audio file; transcribe and summarize **fully
on-device**; export to your apps.

The backend exists only for accounts, OAuth integration brokering, metadata sync,
and billing. **AI compute never leaves the device.**

---

## Status

**1.0.0 — working on-device pipeline** (iPhone + native macOS). Record → transcribe →
summarize → save runs entirely on the device, with no account required.

| Stage | Engine chain (highest priority first) |
| --- | --- |
| **Transcription** | **Apple Speech** (`SFSpeechRecognizer`, `requiresOnDeviceRecognition`, iOS 17+) → built-in fallback |
| **Summarization** | **Local Gemma via MLX** (when a Gemma model is installed and the build sets `NOTOVA_ENABLE_MLX=1`) → **Apple Foundation Models** (iOS 26+ with Apple Intelligence) → built-in fallback |

A runtime resolver (`ResolvingTranscriber` / `ResolvingSummarizer`, both Swift
`actor`s) probes each engine's availability at call time, falls through if an
engine fails mid-inference, and records which engine handled the request so
Settings can show the active engine. The built-in fallback never throws, so the
pipeline always completes offline. Summaries are Markdown with key points and
parsed action items.

---

## Requirements

- Xcode 26.x, Swift 6 (Swift Concurrency, strict)
- iOS deployment target 17.0
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) on `PATH` (the `.xcodeproj` is
  **generated**, not committed)

## Generate, build, test

```bash
make generate                 # xcodegen generate  (creates Notova.xcodeproj)
make build                    # xcodebuild for the iOS Simulator
make build-mac                # xcodebuild the native macOS app (NotovaMac)
make test                     # swift test in Packages/NotovaCore
make test-mac                 # xcodebuild test for the macOS app (NotovaMacTests)
make lint                     # swiftlint (if installed)
make format                   # swiftformat (if installed)
```

Equivalent raw commands:

```bash
xcodegen generate

xcodebuild -project Notova.xcodeproj -scheme Notova \
  -destination 'generic/platform=iOS Simulator' build

cd Packages/NotovaCore && swift test
```

> The generated `Notova.xcodeproj`, the generated `App/Info.plist`, and Xcode user
> data are **gitignored**. The source of truth is `project.yml`. Regenerate with
> `xcodegen generate` after editing it. Microphone and speech-recognition usage
> descriptions live in `project.yml` under `targets.Notova.info.properties`.

### macOS app

Notova also ships a **native macOS app** (`NotovaMac` target, sources in `MacApp/`).
It is SwiftUI for the Mac (a `NavigationSplitView` with Record / Notes / Settings)
and **reuses the same `NotovaCore` package** — models, `PipelineService`, and the
on-device `Transcriber`/`Summarizer` seams — as iOS. Only the platform plumbing is
Mac-specific: `MacAudioRecorder` (AVAudioEngine capture + file import) and a small
JSON `NoteStore`. Build it with `make build-mac` and test it with `make test-mac`.

---

## Architecture

MVVM with `@Observable` view models. UI is SwiftUI. Domain logic and the
on-device pipeline live in **local Swift packages** under `Packages/`, so the app
layer depends only on protocols and is trivially testable.

```
App (SwiftUI, MVVM)
  └─ AppContainer  (composition root: wires concrete impls to protocols)
        ├─ PipelineService = Transcriber + Summarizer        (NotovaCore)
        ├─ AudioRecorder : AudioSource                       (AudioCapture)
        ├─ NoteRepository (SwiftData)                        (Persistence)
        ├─ NotovaBackendClient + exporters                   (Integrations)
        └─ DesignSystem tokens & components
```

### Pipeline

`PipelineService` (an `actor` in NotovaCore) composes a `Transcriber` and a
`Summarizer` to turn an audio file URL into a finished `Note`
(`Recording` + `Transcript` + `Summary`). The concrete transcriber/summarizer are
injected: `AppContainer` (iOS) and `AppModel` (macOS) wire in the resolving
transcriber and summarizer from `TranscriptionService.makeResolving()` and
`SummaryService.makeResolving(store:)`.

### Module map

| Module          | Responsibility                                                                 | Depends on |
| --------------- | ------------------------------------------------------------------------------ | ---------- |
| `NotovaCore`    | Domain models, all protocols, stub impls, `PipelineService`. No UI/platform deps. Has tests. | —          |
| `AudioCapture`  | `AudioRecorder : AudioSource` — AVFoundation capture (mic / Bluetooth route via `AVAudioSession`) + file import. | NotovaCore |
| `Transcription` | `AppleSpeechTranscriber` (on-device) + `ResolvingTranscriber`; `TranscriptionService.makeResolving()`. Has tests. | NotovaCore |
| `AISummary`     | `LocalGemmaSummarizer` (MLX), `AppleFoundationModelsSummarizer` + `ResolvingSummarizer`; `SummaryService.makeResolving(store:)`. Has tests. | NotovaCore, ModelManagement |
| `Persistence`   | SwiftData `@Model` entities for Recording + Summary; `NoteRepository`.         | NotovaCore |
| `Integrations`  | `IntegrationExporter` stub impls + `NotovaBackendClient` (`/v1` REST).          | NotovaCore |
| `DesignSystem`  | Color / typography / spacing tokens + reusable SwiftUI components.             | —          |

### App layer

```
App/
  NotovaApp.swift            @main; builds AppContainer, injects via .environment
  AppContainer.swift         composition root
  RootView.swift             TabView: Record / Notes / Settings
  Features/
    Record/                  record from mic, import via .fileImporter, run pipeline, save
    Notes/                   list saved notes; detail = summary markdown + action items + transcript
    Settings/                account + integrations placeholders
```

---

## Domain model (in `NotovaCore`)

`Recording`, `TranscriptSegment`, `Transcript`, `ActionItem`, `Summary`,
`IntegrationExport`, plus a composite `Note`. See
`Packages/NotovaCore/Sources/NotovaCore/Models.swift`.

Protocols: `AudioSource`, `Transcriber`, `Summarizer`, `IntegrationExporter`.
See `Protocols.swift`. Stubs in `Stubs.swift`.

---

## On-device AI engines

Each engine conforms to `TranscriptionEngine` or `SummarizationEngine`
(`isAvailable()` + the work method) and is listed in priority order in
`TranscriptionService.defaultEngines()` / `SummaryService.defaultEngines(store:)`.

- **Apple Speech** — on-device `SFSpeechRecognizer`; segments map to
  `Transcript` / `TranscriptSegment` with timing. Unavailable without speech
  authorization or on-device support for the locale.
- **Local Gemma (MLX)** — runs a Gemma model from the app's models directory
  (`ModelStore`, capability `.localGemmaMLX`). MLX is Metal-only and fetched from
  the network, so it is opt-in: set `NOTOVA_ENABLE_MLX=1` before generating the
  project. Without it the package still builds and the resolver skips the engine.
- **Apple Foundation Models** — Apple Intelligence's on-device model on iOS 26+.

Adding another engine (e.g. Whisper) is one new type plus one line in the
engine list; no call sites change.

---

## Tests

`Packages/NotovaCore/Tests/NotovaCoreTests` covers:

- `PipelineService` end-to-end (ready note, action-item extraction,
  failure propagation)
- `Packages/Transcription` and `Packages/AISummary` test each engine's
  availability gating, output mapping and the resolvers' fallback order
- Codable round-trips for `Recording`, `Summary`, `Transcript`

Run with `swift test` (or `make test`). An app-level smoke test lives in
`AppTests/` and runs via the `NotovaTests` target in Xcode.

---

## License

Apache-2.0. See `LICENSE` and `NOTICE`.
