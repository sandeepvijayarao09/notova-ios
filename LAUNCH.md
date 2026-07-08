# Notova — Launch Runbook (v1.0.0)

A single, consolidated submission runbook for shipping Notova 1.0.0 to the App
Store, the Mac App Store, and Google Play, plus deploying the backend and hosting
the legal/support pages.

> **This file is shared, identical, across all three repos** (`notova-ios`,
> `notova-android`, `notova-backend`), like `ROADMAP.md`. Relative links in each
> section resolve inside that section's repo — the Apple links live in
> `notova-ios`, the Play links in `notova-android`, and the backend links in
> `notova-backend`.

Release date target: **2026-07-08** · Version: **1.0.0** · License: Apache-2.0

---

## What's already done in the repos

Everything below is committed; the remaining work needs paid developer accounts,
signing identities, live secrets, and a deployment host (see the sections after).

- [x] **Real on-device AI engines** (no cloud AI). iOS: Apple Speech +
      Apple on-device foundation models (optional local Gemma via MLX). Android:
      `SpeechRecognizer` + Gemini Nano / on-device Gemma via LiteRT-LM (import or
      download a model). A runtime resolver picks the best available engine and
      falls back gracefully to a small built-in summarizer, so the pipeline
      always completes offline.
- [x] **Guest mode**: "Continue without an account" on iOS and Android; the
      macOS app has no sign-in gate at all.
- [x] **Apple privacy manifests**: `App/PrivacyInfo.xcprivacy` and
      `MacApp/PrivacyInfo.xcprivacy` (no tracking, email for app functionality,
      required-reason APIs declared).
- [x] **App icons**: iOS 1024, macOS full 16–1024 set, Android adaptive launcher
      icon (store 512×512 to be exported).
- [x] **Export compliance**: `ITSAppUsesNonExemptEncryption = NO` on both Apple
      targets (standard OS/HTTPS/Keychain only).
- [x] **Signing/release config**: iOS automatic-signing-ready + `DEVELOPMENT_TEAM`
      slot in `project.yml`; Mac App Sandbox + Hardened Runtime entitlements;
      Android R8 minify + resource shrink with keep rules, release signing driven
      by `keystore.properties`, ABI splits, `versionCode = 1` /
      `versionName = "1.0.0"`.
- [x] **Android foreground service + local notifications**: "Recording…"
      (foreground-service mic), "Processing recording…" (background), "Note
      ready" (completion). All local; no push.
- [x] **Store copy**: `store/APP_STORE.md` (iOS + Mac) and `store/PLAY_STORE.md`.
- [x] **Legal/support docs**: `PRIVACY.md`, hostable `docs/privacy-policy.md`,
      and `SUPPORT.md` per repo; backend `DEPLOY.md`.
- [x] **Backend**: `/v1` API (auth, OAuth broker with PKCE + AES-256-GCM,
      metadata sync, billing stub), Dockerfile + docker-compose.yml + .env.example.
- [ ] **Screenshots**: capture on signed builds per device class (checklists in
      the store-copy files).

---

## Apple (iOS + Mac App Store)

Covers `com.notova.app` (iOS) and `com.notova.mac` (macOS). Reference:
[`store/APP_STORE.md`](store/APP_STORE.md), [`RELEASE.md`](RELEASE.md).

- [ ] **Enroll in the Apple Developer Program** ($99/yr).
- [ ] Set **`DEVELOPMENT_TEAM`** in `project.yml` (base settings) and enable
      automatic signing in Xcode (or configure fastlane match), then
      `xcodegen generate`.
- [ ] Register **App IDs**: `com.notova.app` and `com.notova.mac`.
- [ ] Create **App Store Connect** records for both apps (name, subtitle,
      Productivity category).
- [ ] Archive & upload:
      `xcodebuild -project Notova.xcodeproj -scheme Notova -destination 'generic/platform=iOS' archive` (and the `NotovaMac` scheme for macOS), then export/upload via Organizer or Transporter.
- [ ] Fill the **App Privacy** questionnaire (email = collected/linked/app
      functionality/no tracking; audio/transcripts/summaries = not collected) —
      see `store/APP_STORE.md`.
- [ ] Complete the **age-rating** questionnaire (all "none" → 4+).
- [ ] Set **Support URL** (hosted `SUPPORT.md`) and **Privacy Policy URL**
      (hosted `docs/privacy-policy.md`).
- [ ] Upload **screenshots** per device class: iPhone 6.9" & 6.5" (required),
      iPad if enabled, Mac 16:10.
- [ ] Paste the **App Review notes** (from `store/APP_STORE.md`): no demo account
      needed — "Continue without an account" on iOS; macOS has no sign-in gate.
- [ ] Do a **signed-build smoke test** (record/import → transcribe → summarize),
      especially on macOS (sandbox changes file-container paths).
- [ ] **Submit for review** (both apps).

---

## Google Play

Covers `com.notova.app`. Reference: [`store/PLAY_STORE.md`](store/PLAY_STORE.md),
[`RELEASE.md`](RELEASE.md).

- [ ] **Create a Google Play Developer account** ($25 one-time).
- [ ] Create the app entry for **`com.notova.app`**.
- [ ] **Generate an upload key** and fill `keystore.properties` (from
      `keystore.properties.example`):
      `keytool -genkeypair -v -keystore notova-upload.jks -alias notova-upload -keyalg RSA -keysize 2048 -validity 10000`.
- [ ] **Enroll in Play App Signing** (Google holds the app signing key; yours is
      the rotatable upload key).
- [ ] Build the bundle:
      `JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew :app:bundleRelease`
      → `app/build/outputs/bundle/release/app-release.aab`.
- [ ] **Upload the .aab to a testing track** (internal/closed) first.
- [ ] Fill the **Data safety** form (email = collected/account
      functionality/not shared/no tracking, only when signed in;
      audio/transcripts/summaries = not collected/not shared) — see
      `store/PLAY_STORE.md`.
- [ ] Complete the **content rating** questionnaire (→ Everyone).
- [ ] Set the **Privacy Policy URL** (hosted `docs/privacy-policy.md`).
- [ ] Upload the **feature graphic** (1024×500), **app icon** (512×512), and
      phone/tablet **screenshots**.
- [ ] **Smoke-test a signed release build on a physical device** (R8 keep-rule
      gaps only surface at runtime).
- [ ] Promote to production and **submit**.

---

## Backend deployment

Reference: [`DEPLOY.md`](DEPLOY.md). Docker + docker-compose are already present.

- [ ] Choose a **container host** (Fly.io / Render / Railway / a VPS).
- [ ] Build/run the container (`docker compose up --build`, or push the image to
      your host).
- [ ] Set a strong **`JWT_SECRET`** and **`TOKEN_ENCRYPTION_KEY`** (openssl/node
      commands in `DEPLOY.md`).
- [ ] Set **`PUBLIC_BASE_URL`** to the real deployed HTTPS URL (used to build
      OAuth redirect URIs).
- [ ] Register/point the **`notova.app` / `api.notova.app`** domain at the
      deployment (mobile/desktop clients default to `https://api.notova.app`).
- [ ] Add per-provider **OAuth client id/secret** env vars (`NOTION_*`, and
      `GOOGLE_*` / `SLACK_*` / `SALESFORCE_*`). Note: only **Notion** export is
      implemented; the others return **501**. Billing checkout is a **stub**.
- [ ] Verify `GET /v1/health` returns `{ status: "ok", version }` over HTTPS.

---

## Hosting the legal/support pages

- [ ] Host **`docs/privacy-policy.md`** at a stable public URL (GitHub Pages, a
      static host, or your marketing site).
- [ ] Host **`SUPPORT.md`** at a stable public URL.
- [ ] Fill every **`<FILL IN: …>`** token first: legal entity name, contact
      email, support email, postal address, and the privacy-policy URL — across
      `PRIVACY.md`, `docs/privacy-policy.md`, `SUPPORT.md`, and the store-copy
      files.
- [ ] Paste the resulting URLs into the App Store Connect and Play Console
      listing fields (Support URL + Privacy Policy URL).
