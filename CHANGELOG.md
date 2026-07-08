# Changelog

All notable changes to Notova for iOS & macOS are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-07-08

Initial public release of the iPhone and native macOS apps.

### Added
- **Audio capture** from the built-in microphone, a Bluetooth microphone/route,
  or an imported audio file (`.fileImporter`).
- **On-device transcription** via Apple's on-device speech recognition.
- **On-device summarization** producing a markdown summary and action items via
  Apple's on-device foundation models, with an optional local Gemma model
  (MLX). A runtime resolver picks the best available engine and falls back
  gracefully — down to a small built-in summarizer — so the pipeline always
  completes offline.
- **Notes**: list view and a detail view showing summary, action items, and the
  full transcript. Local storage via SwiftData.
- **Optional account** (email/password) with tokens stored in the Keychain;
  bearer wiring with refresh-once on 401.
- **Continue without an account** guest mode — full on-device recording,
  transcription, and summarization with zero setup; account-only features gated
  behind a sign-in prompt.
- **Integrations** screen with in-app OAuth (`notova://` deep-link callback).
  **Notion export is functional**; Google, Slack, and Salesforce are scaffolded.
- **Native macOS app** (`NotovaMac`): SwiftUI `NavigationSplitView` (Record /
  Notes / Settings) reusing `NotovaCore`; App Sandbox + Hardened Runtime; no
  sign-in gate.
- **Store readiness**: privacy manifests (`PrivacyInfo.xcprivacy`) declaring no
  tracking, app icons, `ITSAppUsesNonExemptEncryption = NO` export compliance,
  Mac App Store entitlements, and versioning (`MARKETING_VERSION = 1.0`).
- **Launch docs**: App Store / Mac App Store listing copy (`store/APP_STORE.md`),
  support page (`SUPPORT.md`), and hostable privacy policy
  (`docs/privacy-policy.md`).

### Privacy
- Audio, transcripts, and summaries are created and stored on-device and are
  never uploaded. No ads, no analytics or tracking SDKs, no third-party tracking.
  Only the account email and note metadata are ever processed server-side, and
  only when signed in.

[1.0.0]: https://github.com/sandeepvijayarao09/notova-ios/releases/tag/v1.0.0
