# Notova Support (iOS & macOS)

Thanks for using Notova. This page answers the most common questions for the
iPhone and Mac apps. If it doesn't cover your issue, email us at
`<FILL IN: support email>`.

## What Notova does

Notova records audio — from your microphone, a Bluetooth microphone, or an audio
file you import — and then **transcribes and summarizes it entirely on your
device**. You get a transcript, a summary, and a list of action items. Your
audio, transcripts, and summaries stay on your device and are never uploaded.

An optional account (email + password) adds cross-device sync of note *metadata*
(title, duration, timestamps) and lets you connect export integrations. You can
also use the app with no account at all.

## Common questions

### Which permissions does Notova ask for, and why?
- **Microphone** — to record audio.
- **Speech Recognition** (iOS) — to transcribe on-device.

Both are requested the first time you record/transcribe. If you declined, enable
them in **Settings → Notova** (iOS) or **System Settings → Privacy & Security →
Microphone / Speech Recognition** (macOS).

### Does anything get uploaded to a server?
No audio, transcript, or summary ever leaves your device. AI runs 100%
on-device. The only thing that can touch our backend is your account email and
note *metadata* — and only if you sign in. There are no ads, no analytics SDKs,
and no third-party tracking.

### Why does my summary look short or generic?
Notova picks the best summarizer available on your device. On an iPhone or Mac
with Apple's on-device foundation models, you get a full summary. If no on-device
model is available — or before you enable a local model — Notova falls back to a
small built-in summarizer so the flow always completes. That fallback is
intentionally brief and generic. To get richer summaries, use a device that
supports Apple's on-device models, or optionally enable a local Gemma model.
Transcription quality is unaffected by this.

### How do I import an existing audio file?
On the **Record** screen, choose **Import audio file** and pick a file. Notova
transcribes and summarizes it the same way it handles a live recording.

### How does "Continue without an account" work?
On the sign-in screen, tap **Continue without an account** to use Notova as a
guest with zero setup. Recording, transcription, and summarization all work fully
offline. Account-only features (cross-device metadata sync and integrations) show
a sign-in prompt instead. You can create an account later without losing your
on-device notes. (The Mac app has no sign-in gate at all — it opens straight to
the Record window.)

### How do I connect an integration / export a note?
Sign in, open **Settings → Integrations**, and connect a provider. Then, from a
note, choose **Export**. **Today, only Notion export is functional.** Google,
Slack, and Salesforce appear as options but are scaffolded and not yet working —
connecting or exporting to them will report that they aren't implemented yet.

### Where are my notes stored? How do I delete them?
Locally on your device. Delete a note to remove it, or uninstall the app to
remove everything on-device. To delete your account and any synced metadata, use
in-app account deletion or email us.

## Current limitations (honest status)

- Only **Notion** export works; other integrations are scaffolded.
- Summaries use your platform's on-device model when available, otherwise a small
  built-in fallback that produces brief, generic output.

## Contact

Email: `<FILL IN: support email>`

Source (Apache-2.0): https://github.com/sandeepvijayarao09/notova-ios
Privacy policy: see [`docs/privacy-policy.md`](docs/privacy-policy.md).
