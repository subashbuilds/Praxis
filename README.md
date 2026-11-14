# Praxis

**A pocket-sized AI coding workbench for Android.**

Praxis puts a real project folder, a code editor, a device shell, an optional Alpine Linux environment, a live preview, and an AI coding agent in one app. Files stay on the phone; nothing is hidden behind a proprietary workspace format.

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
- **An agent that edits code.** Bring your own OpenAI-compatible provider and API key. The agent can read, write, search, run commands, download assets, and commit to GitHub. Stop a run at any time with the stop button.
- **A live task checklist.** For multi-step work the agent creates a short checklist above the composer, marks each step in progress and complete, and keeps the list when a run is interrupted or the project is reopened. Tap the bar to see every step.
- **A file-backed editor.** Syntax highlighting, line numbers, word wrap, image and SVG previews, Markdown previews, binary-safe storage, and file-type logos in the explorer and editor header.
- **A device shell with project tools.** Run the tools installed on the phone through `/system/bin/sh`, see the real working directory and exit code, and open **Tools** to manage environment values and project skills without leaving the shell.
- **Environment values and secrets.** Add build and runtime variables under Tools → Environment. They are passed to npm scripts, shell commands and deploys. Secret values stay on the device; the agent sees the name and can use it, but never sees the value.
- **Approvals only for destructive work.** Edits and ordinary commands run without interruption. Deleting or removing files requires approval, and the dialog keeps Cancel and Approve visible above a scrollable list of what will be removed.
- **A real Alpine environment.** Settings → **Linux Environment** prepares Alpine 3.21.7 under proot, repairs incomplete rootfs links, installs Node.js, Python, PHP, or Go with `apk`, and provides an interactive shell with the project mounted at `/workspace`. The shell header reports guest CPU and RAM, and tapping the Alpine pill opens this page.
- **A live preview.** Static web projects, Markdown, images and SVGs can be inspected without leaving the app.
- **An Integrations page.** Connect GitHub, Vercel, Cloudflare, Expo (EAS), Tavily, and Supabase. GitHub drives commit, push, pull, branch, and pull-request actions; Vercel drives static deploys; Cloudflare deploys static sites to Pages, while server projects are detected and reported as unsupported on-device. The agent can read connected workflow runs and deployment status with the `integration_status` tool, including failing job names, instead of asking for pasted logs. Every token stays on the device and can be removed from the page.
- **Skills, with discovery.** Create or edit reusable instructions, import `.md` and `.txt` files, or discover public `SKILL.md` files through GitHub's free API. Global skills apply everywhere; project skills under `.praxis/skills/<name>/SKILL.md` still load for that project.
- **Import without losing bytes.** Add files or merge a folder into an existing project. Android uses the system folder picker, copies the selected tree into app-private cache, then imports every child recursively. Existing folders merge, collisions are resolved one by one, and the imported tree expands immediately.
- **Logs you can inspect and export.** Review model requests by task, including round counts, token usage when the provider reports it, and repeated calls. Export the aggregate as privacy-preserving JSON.
- **GitHub-style Markdown preview.** README previews render badge runs, SVG and raster network images, GFM tables, task lists, HTML headings, and ordinary Markdown without leaving the editor.

## Requirements

- Android 7.0 or newer.
- A provider with an OpenAI-compatible chat-completions endpoint, an API key, and a model name.
- Optional: a GitHub token for cloning private repositories, pushing, or pull requests.
- For the bundled Linux Environment: an arm64-v8a Android device and a network connection for package installs.
- For local development: Flutter 3.24.5, Dart 3.5.x, the Android SDK, and JDK 17.

## Linux Environment

Open **Settings → Linux Environment** to set up an on-device Alpine 3.21.7 environment. The minirootfs, the proot binary, and its companion loader are bundled with the app; the first setup extracts the rootfs into the app's support directory and does not need a rooted phone.

- Install Node.js, Python, PHP, or Go from the runtime cards, or run `apk add <package>` yourself in the shell.
- This is Alpine, so use `apk`, not `apt` or `apt-get`.
- The project is mounted at `/workspace`, so files edited in Praxis are the same files the shell sees.
- The Linux Environment screen shows disk usage, guest memory and CPU load, live processes, installed runtime versions, and safe cache/reset actions. An idle guest reads as idle rather than as an unmeasured value.
- The first setup validates the shell before marking the rootfs ready. If an older incomplete rootfs is found, it is rebuilt; Alpine's symlinks are materialized as hardlinks or copies, and commands run through `/bin/busybox sh` so the environment does not depend on a missing `/bin/sh` link.
- Package installs need network access. Resetting the environment removes the rootfs and installed runtimes; project files are never touched.
- The shell has an inline prompt rather than a separate input bar. Tapping the terminal opens the keyboard, with a scrollable symbol row and ESC/Ctrl/arrow controls above it. Output is selectable, and the copy button copies the full transcript.

## Integrations

Open **Settings → Integrations** to connect services. The page is also available directly from the add-integration catalog.

| Service | Used for |
| --- | --- |
| GitHub | Repository sync, branches, commits, pushes, and pull requests |
| Vercel | Static deployments |
| Cloudflare | Pages deployments for static output; Workers server code requires a desktop or CI runner |
| Expo (EAS) | Access-token storage for EAS builds |
| Web Search (Tavily) | API-key storage for web search |
| Supabase | Access-token storage and Management API check |

GitHub and Vercel are checked against their APIs before the account is saved. Cloudflare and Supabase tokens are verified remotely as well; Expo and Tavily tokens are validated for presence and stored locally. More than one account per service is supported, with an active account used by Push and Deploy.

## Skills

Open **Settings → Skills** for the installed-skill list. From there you can:

- Create a skill by typing a name and instructions.
- Edit, enable, disable, or delete an installed skill.
- Import one or more `.md` or `.txt` files. Front matter is parsed when present.
- Search public GitHub repositories and browse their `SKILL.md` files, then install one with a tap.

Discovery uses GitHub's public REST API, so it needs no account. Anonymous rate limits apply; adding a GitHub token under Integrations raises the limit. Project-local skills under `.praxis/skills/<name>/SKILL.md` remain supported and load into that project's prompts.

## Agent round controls

Praxis records one entry per model request through its round logger. The agent also includes independent, compile-time switches for the execution-loop improvements added in Phase 1. All are on by default and can be disabled in a development build:

| Flag | What it controls |
| --- | --- |
| `PRAXIS_PREFETCH` | Adds capped tree, Git state, open-file and search context before the first request; skips trivial requests and filters secrets and `.gitignore` paths |
| `PRAXIS_COMPOUND_TOOLS` | Enables `read_files`, `search_and_read`, `run_commands`, `apply_patch`, and post-edit verification |
| `PRAXIS_BATCHED_EXECUTION` | Runs independent read/search calls concurrently and keeps result ordering |
| `PRAXIS_LOOP_GUARDS` | Stops identical repeated calls, repeated schema failures and edit/fail loops |
| `PRAXIS_RESULT_SIZING` | Returns counts and the relevant entries for large listings, logs and search results, with an explicit way to fetch more |

For example:

```sh
flutter run --dart-define=PRAXIS_PREFETCH=false
```

Ordinary edits and commands run without approval. `run_commands` and `apply_patch` ask only when they remove files or folders: a command batch that contains `rm`, `rmdir`, `unlink`, `git clean` or `git reset --hard`, or a patch that deletes a file. The approval dialog lists every command in a scrolling body with Cancel and Approve pinned below it; tapping outside the dialog cancels. A missing approval UI refuses a destructive action instead of bypassing it.

Resumed tasks keep change expectations, so replying **Continue** after an allowance limit does not end after a single read.

## Tools, environment and deploys

Open the **Tools** button in the shell header for two tabs:

- **Environment** — add, edit and remove variables. Values are available to `npm run build`, shell commands run by the agent, and deploys. Mark a value as a secret to keep it out of the agent prompt; the agent still sees the variable name so it can use it.
- **Project skills** — the same installed project skills that load from `.praxis/skills/`.

Environment entries are stored at `.praxis/environment.json` inside the project. Secret values never enter the conversation. The task checklist is stored at `.praxis/todos.json`, so it survives a paused run, a stop, or an app restart and is available to the next agent turn. A large text file is guarded by a preview and an **Open anyway** action, so tapping a multi-megabyte file does not freeze the editor.

The deploy sheet explains whether the project is static **Cloudflare Pages** output or contains server code. The runtime stays visible during the deploy stages and in the success panel.

After a deployment, Praxis fetches the real build log from Cloudflare's Pages `history/logs` endpoint and shows it in the result, where it can be selected or copied. The agent's `integration_status` tool can also fetch Pages build logs with `action: logs`; the target is a Pages project name or `project/deployment-id`.

The Cloudflare deploy path is Pages-only:

- A static frontend is built if needed and uploaded to **Cloudflare Pages**.
- Server code — API routes under `api/`, `pages/api/`, `app/api/`, a `server.*` entry, Express/Koa/Fastify/Nest/Hono, or an explicit `wrangler.toml` — is detected, but Workers deployment is unavailable because Wrangler's workerd runtime requires glibc and cannot run in the app's Alpine (musl) environment.
- Deploy server code from a desktop or CI runner, or provide static Pages output.

## Logs and export

The Logs screen groups model requests by task and shows rounds, explore/edit/retry classifications, repeated calls, and provider-reported token counts. Use **Export** to save a JSON file suitable for sharing or archiving. The export contains counts, task identifiers, tool names and outcomes; it does not contain prompts, tool arguments, file contents, or API keys.

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

CI runs the same checks and builds a release APK on every push to `main` or `master` and every pull request. CI signs its APK with the same release keystore when the secrets are configured, and fails a push or manual run when they are missing. Pull requests without access to the secrets fall back to the debug key.

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
| `lib/core/agent.dart` | Agent loop, tools, prompts, context prefetch, batching, loop guards, verification and provider fallback |
| `lib/core/context_prefetch.dart` | Capped first-request context with secret and `.gitignore` filtering |
| `lib/core/linux_environment.dart` | Alpine extraction, proot process management, runtime installs and live resource stats |
| `lib/core/integrations.dart` | GitHub Contents, Git Data and refs APIs; Vercel deployments |
| `lib/core/import_picker.dart` | Android SAF tree picker bridge with app-private cache copy |
| `lib/core/skill_discovery.dart` | GitHub repository search, SKILL.md discovery and installation |
| `lib/state/app_state.dart` | Projects, drafts, chats, skills, usage, stop control and push state |
| `lib/screens/` | Project list, editors/previews, Logs, Linux Environment, Integrations and Skills |
| `lib/widgets/file_glyph.dart` | Branded file and folder glyphs for the explorer and editor header |
| `lib/widgets/readme_image.dart` | README image renderer with badge and SVG support |
| `android/app/src/main/kotlin/` | Native folder picker and recursive SAF copy |
| `lib/workspace/` | Conversation, files, shell and preview tabs |
| `.github/workflows/` | CI and the manual signed-release pipeline |

## Privacy and security

- Project files, chats, API keys, provider settings, and the optional Alpine rootfs are stored on the device.
- When you run the agent, the prompt and relevant project context — including prefetched excerpts and tool results — are sent to the provider you configured. Prefetch excludes `.gitignore` paths, `.env*`, credential/key files, and known generated directories.
- API keys are sent only to the provider endpoint you configure. Integration tokens are sent only to the service they belong to. Cloudflare, Supabase, GitHub, and Vercel tokens are checked against their APIs when saved; Expo and Tavily tokens are stored without a remote check.
- Project environment values stay in `.praxis/environment.json`. Non-secret values are included in the agent prompt; secret values are replaced by the variable name only. Values are passed to local build commands and deploys, never written into conversation messages or tool results.
- The agent can read and write files only inside the current project. The device shell is rooted at the project folder; the Alpine environment mounts it at `/workspace`.
- Binary assets are copied byte-for-byte and are never decoded as UTF-8.
- Do not put credentials in project files. Use the in-app settings and GitHub Actions secrets.
- The device shell only uses binaries already installed on the phone. Node.js, Python, PHP, and Go are not bundled: install them from Linux Environment with `apk`, or use binaries the phone already provides. Git is not preinstalled either; use the phone's Git or run `apk add git` in Alpine.
- Skill discovery downloads instructions you choose from public repositories. Review imported skills before enabling them; they become part of the agent prompt.

## Contributing

Issues and pull requests are welcome. Before opening a PR:

1. Keep the change focused and preserve the existing visual language.
2. Run `dart format`, `flutter analyze`, and `flutter test`.
3. Include the reasoning behind user-visible behavior changes, and screenshots for UI changes.
4. Do not include credentials, generated build output, or keystores.

The project follows the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

## License

MIT. See [LICENSE](LICENSE).
