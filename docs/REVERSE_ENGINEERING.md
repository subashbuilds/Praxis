# Reverse-engineering log — com.xapi.polydev 1.0.0 (13)

Everything below is from static inspection of the attached XAPK. No runtime
instrumentation was performed, so behaviour that only appears at runtime
(network calls, entitlements, the agent loop) is **unknown** unless noted.

## 1. Attachment integrity

The file first delivered as `com.xapi.polydev_1.0.0.xapk` was **not** a ZIP.
It was a 20,606-byte HTML page (`<!DOCTYPE html>`, title
"View com.xapi.polydev_1.0.0.xapk"): the FileToLink viewer page at
`f2l.indevs.in`, saved by a browser instead of the download itself.

The same URL serves the real object with `Content-Type: application/octet-stream`
and `Content-Length: 29435701`, so the real XAPK was fetched from it:

```
curl -sSL 'https://f2l.indevs.in/f/aa7b310dbb55dea136d8/com.xapi.polydev_1.0.0.xapk' \
  -o com.xapi.polydev_1.0.0.xapk      # 29,435,701 bytes, "Zip archive data"
```

**Seen:** archive signature `PK\x03\x04`; six entries.

## 2. Package identity

From `manifest.json` inside the XAPK (`seen`):

| field | value |
|---|---|
| package_name | `com.xapi.polydev` |
| name | PolyDev |
| version_code | 13 |
| version_name | 1.0.0 |
| min_sdk_version | 24 |
| target_sdk_version | 36 |
| splits | `config.arm64_v8a`, `config.en`, `config.mdpi` |
| total_size | 29,239,909 |

Permissions (`seen`, manifest.json + binary `AndroidManifest.xml` string pool):
`INTERNET`, `ACCESS_NETWORK_STATE`, `WAKE_LOCK`, `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_SPECIAL_USE`, `POST_NOTIFICATIONS`, `BILLING`,
`CHECK_LICENSE`, `RECEIVE` (FCM), `READ_GSERVICES`,
`BIND_GET_INSTALL_REFERRER_SERVICE`, `ACCESS_ADSERVICES_*`, plus the
app-specific `com.xapi.polydev.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.

## 3. Runtime shape

`unzip -l` and `file` show this is a **Flutter** app (`seen`):

- `lib/arm64-v8a/libflutter.so` (11.1 MB) and `libapp.so` (17.5 MB, Dart AOT)
- `assets/flutter_assets/` with 1,022 files
- `libtermux.so`, `libterminal_jni.so`, `libproot.so`, `libloader.so`,
  `libsqlite3.so`, `libdartjni.so`
- asset `assets/alpine/alpine-minirootfs-3.21.7-aarch64.tar.gz` (3.85 MB)

**Inferred:** the app runs an Alpine userland through proot, exposes it as a
PTY-backed terminal, and stores data in SQLite. This matches the Terms text
("runs a real terminal") and the bundled rootfs.

Java/Kotlin side is thin: `classes.dex`, Firebase (auth, messaging, analytics),
Play Billing / `purchases_flutter`, Credentials API, plus
`assets/adi-registration.properties`. jadx was not needed: no app logic lives
in DEX beyond plugin glue.

## 4. Dart recovery limits

`libapp.so` was mined for printable runs (`python3` scan → 47,182 runs, 46,715
unique). Only a handful of symbols survive:

```
package:re_editor, package:aiagent, package:isolate_contactor,
package:firebase_messaging_platform_interface, package:stack_trace
HtmlPreviewScreen, HomePage, UninstPage, FormPage, WebView
```

**Seen:** that is a minified/obfuscated AOT build — class and member names are
stripped. **Unknown:** original Dart file layout, state management choice,
exact widget trees, API schemas. `blutter`/`hermes-dec` would not restore the
original source; a faithful *source* clone is not recoverable from this
artifact. The reconstruction therefore targets the **interface**: tokens,
copy, screens, states and assets.

## 5. Product surface found in assets and docs

- 30 provider marks: openai, anthropic/claude, gemini/googlegemini/google,
  openrouter, groq, deepseek, mistral, cerebras, cohere, huggingface, nvidia,
  minimax, moonshot, qwen, siliconflow, yi, baichuan, gemma, meta, opencode,
  freeai, agnesai, ollama, vercel, cloudflarepages, github, polydev.
- Fonts: Inter (4 weights), JetBrains Mono (4), Lora Medium.
- `github-dark.css` + `github-markdown-dark.css` → dark markdown rendering.
- `packages/file_icon/Seti` and `material_file_icon` → file tree with icons.
- Legal docs in **en / ru / uz** (privacy policy, terms of use), last updated
  2026-08-06.
- Terms, §1: "on-device AI coding agent for mobile: it edits files, runs a real
  terminal, previews the running app, and can deploy projects to Vercel and
  Cloudflare Pages."
- Privacy, §1.3: projects, code, chat history and provider tokens are local
  only; §1.4: own-key requests go straight to the provider, built-in traffic
  goes through an OpenRouter proxy; §1.7: Firebase Analytics with a
  "Usage statistics" switch in Settings.
- Terms, §2: paid tiers **Pro** and **Ultra**; privacy §1.1: a device limit per
  plan.

## 6. What the reconstruction keeps vs invents

**Kept from evidence:** package id, name, version/build, min/target SDK,
permission set, provider catalogue and marks, fonts, legal documents (verbatim),
plan names (Pro/Ultra), device-slot concept, privacy-copy claims, dark theme,
Alpine/proot terminal framing, Vercel/Cloudflare deploy targets.

**Reconstructed (inferred):** screen layout and navigation, spacing, colour
ramp, agent thread design, terminal chrome, preview frame, settings grouping.
No original screen was available to compare against, so fidelity here is
editorial, not measured.

**Simulated:** agent replies, shell output, deploy actions, billing state. The
project ships no network code and no keys.
