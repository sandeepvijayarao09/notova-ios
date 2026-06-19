# notova-ios

**Notova** for iOS — on-device AI voice capture & notes (SwiftUI). Record from any
mic, Bluetooth input, or imported audio file; transcribe and summarize **fully
on-device**; export to your apps.

The backend exists only for accounts, OAuth integration brokering, metadata sync,
and billing. **AI compute never leaves the device.**

---

## Status

This is a working scaffold. Transcription and summarization are **stub
implementations behind protocols** so the real models drop in without touching
call sites:

- **Transcription** → `StubTranscriber` today; `WhisperTranscriber` later.
- **Summarization** → `StubSummarizer` today; `GemmaSummarizer` (Gemma 3n E4B) later.

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
make test                     # swift test in Packages/NotovaCore
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
injected, so swapping stubs for Whisper/Gemma is a one-line change in
`AppContainer` plus the new type in the relevant package.

### Module map

| Module          | Responsibility                                                                 | Depends on |
| --------------- | ------------------------------------------------------------------------------ | ---------- |
| `NotovaCore`    | Domain models, all protocols, stub impls, `PipelineService`. No UI/platform deps. Has tests. | —          |
| `AudioCapture`  | `AudioRecorder : AudioSource` — AVFoundation capture (mic / Bluetooth route via `AVAudioSession`) + file import. | NotovaCore |
| `Transcription` | `TranscriptionService.makeDefault()` → `StubTranscriber`. Whisper goes here.   | NotovaCore |
| `AISummary`     | `SummaryService.makeDefault()` → `StubSummarizer`. Gemma goes here.            | NotovaCore |
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

## Where Whisper / Gemma plug in

Both are isolated behind protocols and a factory:

- **Whisper (transcription):** add `WhisperTranscriber: Transcriber` in
  `Packages/Transcription/`, then return it from `TranscriptionService.makeDefault()`.
  A commented stub already marks the spot. Map model output to the
  `Transcript` / `TranscriptSegment` domain types.
- **Gemma 3n E4B (summarization):** add `GemmaSummarizer: Summarizer` in
  `Packages/AISummary/`, then return it from `SummaryService.makeDefault()`.
  Produce `Summary.contentMarkdown` + `actionItems`.

No call sites in the app change — `AppContainer` consumes the factories and
`PipelineService` consumes the protocols.

---

## Tests

`Packages/NotovaCore/Tests/NotovaCoreTests` covers:

- `PipelineService` end-to-end with stubs (ready note, action-item extraction,
  failure propagation)
- Codable round-trips for `Recording`, `Summary`, `Transcript`

Run with `swift test` (or `make test`). An app-level smoke test lives in
`AppTests/` and runs via the `NotovaTests` target in Xcode.

---

## License

Apache-2.0. See `LICENSE` and `NOTICE`.
