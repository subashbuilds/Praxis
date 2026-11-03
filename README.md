# PolyDev — Android Studio project

Rebuilt Android project for **com.xapi.polydev 1.0.0 (13)**.

The shipped app is a Flutter app with an obfuscated Dart AOT snapshot
(`libapp.so`), so a Java/Kotlin translation would be a reimplementation with no
fidelity. The faithful Android Studio project for this artifact is a **Flutter
project with its Android module** — open the `polydev/` folder in Android Studio
(Flutter + Dart plugins) and it syncs the `android/` Gradle module
(`applicationId com.xapi.polydev`, minSdk 24, targetSdk 36, versionCode 13).

## Open it

```
Android Studio → Open → polydev/
# first run
flutter pub get
flutter run            # device or emulator
```

The Gradle wrapper is checked in (`android/gradle/wrapper/…`, Gradle 8.10.2).
If your Flutter install regenerates platform files, `flutter create .` inside
`polydev/` restores anything missing without touching `lib/`.

Nothing was built on the analysis machine — it has 3.9 GB RAM and no Android
SDK, so a Gradle build would have been killed. Source is verified by
`flutter analyze` only (see below).

## What is inside

```
lib/
  main.dart, app.dart          app shell, dark theme, state scope
  theme/tokens.dart            palette, type roles, spacing, motion
  theme/app_theme.dart         Material 3 theme with chrome removed
  models/                      project, chat items, provider catalogue
  state/app_state.dart         projects, agent thread, shell, settings
  screens/                     home, workspace, settings, legal, code, sheet
  workspace/                   agent, files, terminal, preview, composer
  widgets/                     brand, buttons, hairlines, chips, cards
assets/
  fonts/                       Inter, JetBrains Mono, Lora (from the APK)
  icons/                       30 provider + brand marks (from the APK)
  images/                      logo, splash art (from the APK)
  legal/                       privacy + terms, en/ru/uz (from the APK)
android/                       Gradle module, manifest, launcher icons
docs/REVERSE_ENGINEERING.md    evidence log: what was seen, inferred, unknown
DESIGN.md                      tokens, rules and intent of the interface
```

## Behaviour

Everything is local. No network calls, no keys, no analytics.

- Create a project (Flutter / Node / Python) and it appears in the list.
- Agent thread: send a prompt, watch the simulated plan → command → edit → summary.
- Shell: `ls`, `pwd`, `node -v`, `flutter analyze`, `npm run dev`, `git status`, `help`, `clear`.
- Files: browse the tree, open a file for a read-only syntax-coloured view.
- Preview: device frame with the running dashboard, deploy chips, reload.
- Settings: provider picker (searchable, 24 providers), integrations, preferences,
  data reset with confirmation, full legal docs with EN/RU/UZ switch.

## Rebuild fidelity

Kept: package identity, SDK levels, permission set, provider catalogue and marks,
fonts, legal copy, plan names, device-limit concept, dark-first surface.

Reconstructed: layout, spacing, colour ramp, screen structure, agent/terminal/
preview chrome. The Dart snapshot is minified, so the original widget trees are
not recoverable; see `docs/REVERSE_ENGINEERING.md` §4.

## Verification status

- `flutter analyze` — see the check run in the hand-off notes.
- Not built (no Android SDK/emulator on this machine), not run, no screenshots.
  First `flutter run` on your machine is the real visual check.
