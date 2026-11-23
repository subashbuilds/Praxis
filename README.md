# Praxis

A coding workbench for Android. Praxis keeps a project in a normal folder on the phone and puts a code editor, a device shell, an optional Alpine Linux environment, a live preview, and an AI coding agent in one app.

[![Build & test](https://github.com/subashbuilds/Praxis/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/subashbuilds/Praxis/actions/workflows/ci.yml)
[![Release APK](https://github.com/subashbuilds/Praxis/actions/workflows/release.yml/badge.svg)](https://github.com/subashbuilds/Praxis/actions/workflows/release.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.24.5-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)](https://www.android.com)
[![Version](https://img.shields.io/badge/version-2.2.1-F26B3F)](https://github.com/subashbuilds/Praxis/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-2EA043)](LICENSE)

## Download

Get the latest signed APK from [GitHub Releases](https://github.com/subashbuilds/Praxis/releases/latest).

- `Praxis-<version>-universal.apk` works on most devices.
- `Praxis-<version>-arm64-v8a.apk` is smaller and targets modern 64-bit phones.
- `Praxis-<version>-armeabi-v7a.apk` targets older 32-bit phones.

Each release includes a `SHA256SUMS` file. To check a download, place the APK and `SHA256SUMS` in the same folder, then run:

```sh
sha256sum -c SHA256SUMS      # Linux
shasum -a 256 -c SHA256SUMS  # macOS
```

Requires Android 7.0 or newer.

## What it does

- **Projects are folders.** Create a project, clone a Git repository, or start from a template. Files stay in the app documents directory.
- **The agent edits code.** Connect an OpenAI-compatible provider with your own key. The agent can read, write, search, run commands, download assets, and commit to GitHub.
- **Stop and retry.** The stop button ends a run and shows when it is stopping. Rate limits, provider outages, and network timeouts are retried up to five times with a visible countdown before the error is shown.
- **A live task checklist.** Multi-step work gets a checklist above the composer. It survives a pause or an app restart.
- **An editor.** Syntax highlighting, line numbers, word wrap, find, undo, Markdown preview, image and SVG previews, and binary-safe storage.
- **A device shell and Alpine Linux.** Run the tools installed on the phone, or prepare Alpine 3.21.7 under proot with Node.js, Python, PHP, or Go. The project is mounted at `/workspace`.
- **A live preview.** Inspect static web projects, Markdown, images, and SVGs in the app.
- **Skills.** Write reusable instructions, import `.md` files, or discover public `SKILL.md` skills on GitHub.
- **Integrations.** GitHub, Vercel, Cloudflare, Expo EAS, Tavily, and Supabase. Tokens stay on the device and are never sent to the agent.
- **Logs.** Review model requests by task, including round counts, token usage, and repeated calls. Export privacy-preserving JSON.

## Requirements

- Android 7.0 or newer.
- A provider with an OpenAI-compatible chat-completions endpoint, an API key, and a model name.
- Optional: a GitHub token for private repositories, pushing, or pull requests.
- For the bundled Linux environment: an arm64-v8a device and a network connection for package installs.
- For local development: Flutter 3.24.5, Dart 3.5.x, the Android SDK, and JDK 17.

## Linux environment

Open **Settings → Linux Environment**. The Alpine minirootfs, proot, and its loader are bundled with the app. The first setup extracts the rootfs into the app support directory and does not need a rooted phone.

- Install Node.js, Python, PHP, or Go from the runtime cards, or run `apk add <package>` in the shell.
- Use `apk`, not `apt` or `apt-get`.
- The project is mounted at `/workspace`, so the shell sees the same files the editor does.
- The screen shows disk use, guest memory, CPU load, live processes, and installed runtime versions. The shell header shows the same guest CPU and memory readings.
- Resetting the environment removes the rootfs and installed runtimes. Project files are not touched.

## Build from source

```sh
git clone https://github.com/subashbuilds/Praxis.git
cd Praxis
flutter pub get
flutter run
```

Build an installable APK:

```sh
flutter build apk --release
```

Without release signing variables, Gradle uses the debug key so local builds still install.

Check the project before opening a pull request:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

CI runs the same checks on every push to `main` or `master` and every pull request. It also builds a release APK. Documentation-only changes skip CI.

## Releases

Releases are manual. In **Actions → Release APK → Run workflow**, choose the tag and optionally mark the release as a pre-release. The workflow builds and signs three APKs, creates `SHA256SUMS`, verifies the signatures, and publishes the release.

Add these repository secrets under **Settings → Secrets and variables → Actions**:

| Secret | Required | Purpose |
| --- | --- | --- |
| `KEYSTORE_BASE64` | Yes | Release keystore, Base64-encoded with `base64 -w0 release.jks` |
| `KEYSTORE_PASSWORD` | Yes | Keystore password |
| `KEY_ALIAS` | Yes | Key alias inside the keystore |
| `KEY_PASSWORD` | No | Key password; defaults to `KEYSTORE_PASSWORD` |

Release notes come from [`.github/RELEASE_NOTES.md`](.github/RELEASE_NOTES.md). The workflow decodes the keystore into the runner's temporary directory, never into the repository.

## Project layout

| Path | Responsibility |
| --- | --- |
| `lib/core/agent.dart` | Agent loop, tools, prompts, retries, loop guards, verification |
| `lib/core/ai.dart` | Streaming clients for OpenAI-compatible and Anthropic APIs |
| `lib/core/linux_environment.dart` | Alpine extraction, proot commands, runtime installs, resource sampling |
| `lib/core/vfs.dart` | Sandboxed project filesystem |
| `lib/core/integrations.dart` | GitHub, Vercel, Cloudflare, and other service APIs |
| `lib/state/app_state.dart` | Projects, chats, checkpoints, usage, stop control, pushes |
| `lib/screens/` | Project list, editor, Logs, Linux Environment, Integrations, Skills |
| `lib/workspace/` | Conversation, files, shell, and preview tabs |
| `.github/workflows/` | CI and the signed release pipeline |

## Privacy

- Project files, chats, API keys, provider settings, and the Alpine rootfs stay on the device.
- The prompt and relevant project context are sent to the provider you configure. Prefetch skips `.gitignore` paths, `.env*`, credential files, and generated directories.
- API keys go only to their provider. Integration tokens go only to the service they belong to.
- Environment values live in `.praxis/environment.json`. Secret values are passed to local commands but replaced by their names in the agent prompt.
- Skill discovery downloads instructions you choose. Review imported skills before enabling them.

## Contributing

Issues and pull requests are welcome. Keep changes focused, preserve the existing visual language, and run `dart format`, `flutter analyze`, and `flutter test` before opening a pull request. Do not include credentials, generated build output, or keystores.

The project follows the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

## License

MIT. See [LICENSE](LICENSE).
