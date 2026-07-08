# Notova for Apple — App Store & Mac App Store release guide

Covers `com.notova.app` (iOS) and `com.notova.mac` (macOS). The project is generated with
XcodeGen — **always `xcodegen generate` after editing `project.yml`.**

## Already configured in the repo

- **Privacy manifests** (required by Apple): `App/PrivacyInfo.xcprivacy`, `MacApp/PrivacyInfo.xcprivacy`
  — declare no tracking, email collected for app functionality only, and required-reason API uses.
- **App icons**: iOS `App/Assets.xcassets/AppIcon.appiconset` (1024) and macOS
  `MacApp/Assets.xcassets/AppIcon.appiconset` (full 16–1024 set).
- **Export compliance**: `ITSAppUsesNonExemptEncryption = NO` on both targets (only standard
  OS/HTTPS/Keychain encryption) — no per-submission encryption questionnaire.
- **Mac App Store sandbox**: `MacApp/NotovaMac.entitlements` — App Sandbox + mic + user-selected
  read-only files + outbound network; Hardened Runtime enabled.
- **Versioning**: `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1` (base settings).
- **Usage strings**: microphone + speech-recognition on both targets.

## Build / archive

```bash
xcodegen generate
# iOS archive:
xcodebuild -project Notova.xcodeproj -scheme Notova -destination 'generic/platform=iOS' archive \
  -archivePath build/Notova-iOS.xcarchive
# macOS archive:
xcodebuild -project Notova.xcodeproj -scheme NotovaMac -destination 'generic/platform=macOS' archive \
  -archivePath build/Notova-Mac.xcarchive
# then export + upload with `xcodebuild -exportArchive` or Xcode Organizer / Transporter.
```

## App Review access — resolved

App Review needs to be able to use the app without your backend:
- **iOS** now has a **"Continue without an account"** path on the sign-in screen
  (`SessionStore.continueWithoutAccount()`), matching Android. A guest lands in the app with full
  on-device recording/transcription/summarization; account-only features (sync, integrations) are
  gated behind `SessionStore.hasAccount` and show a sign-in prompt instead of erroring.
- **macOS** has no sign-in gate at all — it opens straight to the Record/Notes/Settings window.

So no demo account is required for review. (You may still provide one in review notes if you want
reviewers to exercise the signed-in sync/integrations flows against `api.notova.app`.)

## Requires your Apple Developer account (cannot be done from the repo)

1. **Apple Developer Program** ($99/yr). Set `DEVELOPMENT_TEAM` (base settings in `project.yml`)
   and enable automatic signing in Xcode, or use fastlane match.
2. **App IDs** for `com.notova.app` and `com.notova.mac`; **App Store Connect** records for each.
3. **App privacy** questionnaire in App Store Connect — mirror the privacy manifests: email
   (linked, app functionality, no tracking); audio/transcripts/summaries **not collected**.
4. **Screenshots** per required device class (iPhone 6.9"/6.5", iPad if supported; Mac 16:10).
5. **Category** (Productivity), **age rating** questionnaire, support URL, **privacy policy URL**
   (template in `PRIVACY.md`).
6. **Mac App Store** distribution uses Apple's "3rd Party Mac Developer" signing; the App Sandbox
   entitlement is already set. (For distribution *outside* the store, use Developer ID + notarize;
   Hardened Runtime is already enabled.)
7. Submit for review.

## Notes

- On first transcription the app requests **Speech Recognition** permission (and microphone for
  recording). Both usage strings are configured.
- Verified: iOS app builds, macOS app builds + `NotovaMacTests` pass, with sandbox/entitlements
  and icons in place. Do a signed-build smoke test (record/import → transcribe → summarize) before
  release, especially on macOS where the sandbox changes file-container paths.
