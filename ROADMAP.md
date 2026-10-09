# Notova Roadmap

Notova is an on-device AI voice-notes app: record or import audio, transcribe and
summarize it on the device, and optionally export the result through a small
backend that handles only accounts, OAuth brokering, metadata sync and billing.
AI never runs on the server.

This file is shared by the three repos:
[notova-ios](https://github.com/sandeepvijayarao09/notova-ios) (iPhone + Mac),
[notova-android](https://github.com/sandeepvijayarao09/notova-android) and
[notova-backend](https://github.com/sandeepvijayarao09/notova-backend).

## Where things stand (October 2026)

| Area | iOS / macOS | Android | Backend |
| --- | --- | --- | --- |
| Transcription | Apple Speech, on-device. No fake fallback: if it can't run, the app keeps the audio and says so. | Gemma 3n audio via LiteRT-LM, once the user imports a `.litertlm` model. `SpeechRecognizer` file input is not wired yet. No fake fallback. | n/a |
| Summaries | Local Gemma via MLX (opt-in build flag), then Apple Foundation Models (iOS 26+), then a labelled basic extract. | Local Gemma via LiteRT-LM, then Gemini Nano (AICore devices), then a labelled basic extract. | n/a |
| Export | Through the backend. Notion is implemented server-side; Google, Slack and Salesforce connect but export returns 501. | Same contract and provider list. | Notion page creation; others 501. |
| Deployment | Source only; no TestFlight build. | Test-signed APKs on the v1.0.0 release. | Docker image and compose file; not deployed anywhere public. Both apps default to a local dev server. |

## Next

1. **Android transcription without a model.** Feed recorded files to the platform
   `SpeechRecognizer` (API 33+ `EXTRA_AUDIO_SOURCE`), or bundle whisper.cpp tiny/base
   through JNI, so a fresh install can transcribe.
2. **In-app model download** on both platforms: one curated Gemma entry with size,
   checksum and progress instead of manual import.
3. **Deploy the backend** to a domain the project controls, then set
   `NOTOVA_BACKEND_URL` (iOS) / `-Pnotova.backendUrl` (Android) for release builds.
4. **One more real export** (Slack message or Google Tasks), or trim the provider list.
5. **Distribution:** TestFlight for iOS/macOS; a Play internal-testing track for Android.

## Later

- Account and cross-device metadata sync in the clients (endpoints exist).
- Billing (free/Pro) through StoreKit / Play Billing; the backend has a stub.
- Speaker diarization, mind-map view, background processing on iOS (`BGProcessingTask`).
