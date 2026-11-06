# Praxis

**A pocket-sized AI coding workbench for Android.**

Praxis puts a real project folder, a code editor, a device shell, a live preview, and an AI coding agent in one app. Files stay on the phone; nothing is hidden behind a proprietary workspace format.

[![Build & test](https://github.com/subashbuilds/Praxis/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/subashbuilds/Praxis/actions/workflows/ci.yml)
[![Release APK](https://github.com/subashbuilds/Praxis/actions/workflows/release.yml/badge.svg)](https://github.com/subashbuilds/Praxis/actions/workflows/release.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.24.5-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)](https://www.android.com)
[![Version](https://img.shields.io/badge/version-2.2.0-F26B3F)](https://github.com/subashbuilds/Praxis/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-2EA043)](LICENSE)

## Download

Grab the latest signed APK from [GitHub Releases](https://github.com/subashbuilds/Praxis/releases/latest). The release asset is a universal Android APK named `praxis-<version>.apk`.

## What Praxis does

- **Real projects, real files.** A project is a normal folder in the app's documents directory. Clone a Git repository or start from a template.
- **An agent that edits code.** Bring your own OpenAI-compatible provider and API key. The agent can read, write, search, run commands, download assets, and commit to GitHub.
- **A file-backed editor.** Syntax highlighting, line numbers, word wrap, image and SVG previews, Markdown previews, and binary-safe storage.
- **A device shell.** Run the tools installed on the phone through `/system/bin/sh`, and see the real working directory and exit code.
- **A live preview.** Static web projects, Markdown, images and SVGs can be inspected without leaving the app.
- **GitHub and Vercel integrations.** Commit, push, pull, create branches, and deploy static sites. Tokens are kept in local settings.
- **Project skills.** Add reusable instructions under `.praxis/skills/<name>/SKILL.md`; they are included in every agent prompt for that project.
- **Import without losing bytes.** Add files or merge a folder into an existing project. Collisions are resolved one by one.

## Requirements

- Android 7.0 or newer.
- A provider with an OpenAI-compatible chat-completions endpoint, an API key, and a model name.
- Optional: a GitHub token for cloning private repositories, pushing, or pull requests.
- For local development: Flutter 3.24.5, Dart 3.5.x, the Android SDK, and JDK 17.

## Build from source

```bash
git clone https://github.com/subashbuilds/Praxis.git
cd Praxis
flutter pub get
flutter run
```

To build an installable APK:

```bash
flutter build apk --release
```

The unsigned-during-development output is written to `build/app/outputs/flutter-apk/app-release.apk`. Without release signing environment variables, Gradle falls back to the debug key so local builds still install.

### Verification

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

CI runs the same checks and builds a release APK on every push to `main` and every pull request.

## Signed releases

Releases are manual. In **Actions → Release APK → Run workflow**, choose the tag (defaults to `v2.2.0`) and optionally mark it as a pre-release. The workflow builds, signs, verifies, uploads, and publishes the APK.

Add these repository secrets under **Settings → Secrets and variables → Actions**:

| Secret | Required | Purpose |
| --- | --- | --- |
| `KEYSTORE_BASE64` | Yes | Release keystore, Base64-encoded with `base64 -w0 release.jks` |
| `KEYSTORE_PASSWORD` | Yes | Keystore password |
| `KEY_ALIAS` | Yes | Key alias inside the keystore |
| `KEY_PASSWORD` | No | Key password; defaults to `KEYSTORE_PASSWORD` |

The workflow writes the decoded keystore to the runner's temporary directory, never to the repository. The resulting asset is `praxis-<version>.apk` and the signature is checked with `apksigner` before publishing.

## How it fits together

Praxis is intentionally small and inspectable. The important boundaries are:

| Area | Responsibility |
| --- | --- |
| `lib/core/vfs.dart` | Sandboxed project filesystem; every path is normalized and cannot escape the project root |
| `lib/core/agent.dart` | Agent loop, tools, prompts, mutation tracking, provider fallback |
| `lib/core/integrations.dart` | GitHub Contents, Git Data and refs APIs; Vercel deployments |
| `lib/state/app_state.dart` | Projects, drafts, chats, skills, usage, push state |
| `lib/screens/` | Project list and full-screen editors/previews |
| `lib/workspace/` | Conversation, files, shell and preview tabs |
| `.github/workflows/` | CI and the manual signed-release pipeline |

## Privacy and security

- Project files, chats, API keys, and provider settings are stored on the device.
- API keys are sent only to the provider endpoint you configure. GitHub and Vercel tokens are sent only to their respective APIs.
- The agent can read and write files only inside the current project. The shell is rooted at the same project folder.
- Binary assets are copied byte-for-byte and are never decoded as UTF-8.
- Do not put credentials in project files. Use the in-app settings and GitHub Actions secrets.
- Praxis never bundles Node, Python, or Git. Commands that depend on those binaries fail with a clear error unless the phone already provides them.

## Contributing

Issues and pull requests are welcome. Before opening a PR:

1. Keep the change focused and preserve the existing visual language.
2. Run `dart format`, `flutter analyze`, and `flutter test`.
3. Include the reasoning behind user-visible behavior changes, and screenshots for UI changes.
4. Do not include credentials, generated build output, or keystores.

The project follows the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

## License

MIT. See [LICENSE](LICENSE).
