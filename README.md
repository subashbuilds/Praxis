# Praxis

A local-first coding workbench for Android. Real project folders, a real device
shell, a GitHub-style editor, a live WebView preview, and an AI agent that edits
those files with your own model keys — all on the phone.

Built with Flutter; the Android module is a standard Android Studio project.

## What works

| Area | Behaviour |
|---|---|
| Projects | Real folders under the app's documents directory, with starter files for Web, Flutter, Python or empty projects. Long-press to delete. |
| Agent | OpenAI-compatible providers plus Anthropic, with tool calling: `list_files`, `read_file`, `write_file`, `run_command`. Stop mid-run. |
| Conversation | Your messages sit right-aligned in an ember bubble. Reasoning is collapsed into a **Thinking** pill. Tool calls collapse into pills; a write pill carries `+added / −removed`, and tapping expands a line-numbered GitHub-style diff with red/green rows. Tapping the open box collapses it again. |
| Attachments | The composer's paperclip picks photos or any file, copies them into the project's `attachments/` folder, shows them in the message, and tells the agent their paths. |
| Files | A recursive explorer over the project folder. Tap a file to edit it, create files and folders, long-press to delete. Changes hit disk immediately. |
| Editor | GitHub-dark syntax highlighting for HTML, CSS, JS/TS, Dart, Python, JSON, Markdown and YAML, with a synced line-number gutter and a wrap switch in Settings. |
| Agent shell | A sandboxed file shell for the agent: `ls`, `cd`, `pwd`, `cat`, `echo >`, `mkdir`, `touch`, `rm`, `mv`, `cp`, `tree`, `find`, `grep`, `wc`, `head`, `tail`. |
| Shell tab | A real device shell through `/system/bin/sh` in this project's directory — streaming stdout/stderr, exit codes, `cd` that persists, stop button. Any binary installed on the phone (`git`, `curl`, `tar`, `python`) runs here; nothing is simulated. |
| Preview | Loads the project's `index.html` (or first `.html`) in a WebView, with reload. Relative CSS/JS works. |
| Providers | A single **Providers** pill opens every provider; those with keys also appear as quick-switch pills inside the project. Each provider supports **several keys**, a chosen active key, and a live **Fetch models** list with per-model checkboxes and a **Select all / Deselect all** toggle. |
| Failover | When a key is rate-limited or out of credit, the agent asks whether to use the next key; then whether to move to another configured provider. Settings can make either step automatic. |
| Skills | Named prompt fragments; add them manually or **import `.md` / `.txt`** files as skills. |
| Integrations | GitHub (create/update a repo, commit the project's text files) and Vercel (static deploy with URL). Tokens live in Settings; **Push** and **Deploy** now sit in the Files and Preview tabs of every project. |

There is no bundled free model. Every hosted provider needs your API key;
Ollama is the only keyless option and it talks to a server on your network.

## Running it

```bash
flutter pub get
flutter run
```

Toolchain: Flutter 3.24.5, Dart 3.5.4, Android compileSdk 36, minSdk 24.
CI (`.github/workflows/ci.yml`) runs `dart format`, `flutter analyze`,
`flutter test`, then builds the release APK artifact `devnest-release-apk`.

Release builds are debug-signed because no release keystore is committed.

## Using it

1. **Settings → Models** → tap a provider, paste one or more keys, fetch models,
   tick the ones you want, then **Use this model**.
2. Open a project and tap the **Providers** pill to switch. Providers with keys
   appear as pills above the tabs.
3. Ask for a change. Tap the **Thinking** pill for reasoning, and tap any tool
   pill to inspect its diff or output.
4. Use **Push** / **Deploy** in Files or Preview once the matching token is in
   Settings → Integrations.

## Limits, stated plainly

- The **agent's** shell is sandboxed to file verbs; it has no Node, Python, git
  or Flutter runtime. The **Shell tab** is the real device shell, but Praxis
  does not bundle those binaries — it runs what the phone already has.
- Preview renders web projects only. Flutter and Python projects are edited and
  stored, not compiled on device.
- Attached images are copied into the project and shown, but they are not sent
  to the model as vision input; text files can be read by the agent by path.
- Agent runs depend on the provider's tool-calling support. Some small models
  cannot call tools reliably; pick a model that does.
- GitHub pushes text files only (binaries are skipped), one commit per file via
  the contents API. Vercel deploys static files; no build step runs server-side.
- No account, no analytics. Files and keys stay on the device.

## Layout

```
lib/
  core/        agent, ai client, diff, shells, vfs, integrations, storage
  models.dart  project, provider, skill, chat types
  screens/     home, workspace, editor, settings, provider form
  workspace/   agent, files, shell, preview tabs
  theme/       tokens and theme
  widgets/     UI kit, code editor, project ship bar
test/          vfs, shells, agent loop, diffs, failover, provider parsing
```

The `docs/` folder keeps the original reverse-engineering notes that informed
the product model.
