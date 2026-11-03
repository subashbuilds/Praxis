# DevNest

A local-first coding workbench for Android. Real project folders, a real file
shell, a live WebView preview, and an AI agent that edits those files with your
own model key — all on the phone.

Built with Flutter; the Android module is a standard Android Studio project.

## What works

| Area | Behaviour |
|---|---|
| Projects | Real folders under the app's documents directory, with starter files for Web, Flutter, Python or empty projects. Long-press to delete. |
| Files | A recursive explorer over that folder. Tap a file to edit it, create files and folders, long-press to delete. Changes hit disk immediately. |
| Shell | A genuine file shell: `ls`, `cd`, `pwd`, `cat`, `echo >`, `mkdir`, `touch`, `rm`, `mv`, `cp`, `tree`, `find`, `grep`, `wc`, `head`, `tail`, `clear`, `help`. |
| Preview | Loads the project's `index.html` (or first `.html`) in a WebView, with reload. Relative CSS/JS works. |
| Agent | OpenAI-compatible providers plus Anthropic, with tool calling: `list_files`, `read_file`, `write_file`, `run_command`. Tool calls are shown inline. Stop mid-run. |
| Models | OpenAI, Anthropic, Gemini, OpenRouter, Groq, DeepSeek, Mistral, Cerebras, Together, keyless Ollama on your network, and any custom OpenAI-compatible endpoint. Keys are stored on device. |
| Skills | Named prompt fragments toggled on or off; enabled ones are appended to every agent run. |
| Integrations | GitHub (create/update a repo and commit the project's text files) and Vercel (deploy those files, get the URL). Tokens are local. |

There is no bundled free model. Every hosted provider needs your API key;
Ollama is the only keyless option, and it talks to a server on your machine.

## Running it

```bash
flutter pub get
flutter run
```

Toolchain used: Flutter 3.24.5, Dart 3.5.4, Android compileSdk 36, minSdk 24.
CI (`.github/workflows/ci.yml`) runs `dart format`, `flutter analyze`,
`flutter test`, then builds a release APK artifact.

Release builds are debug-signed because no release keystore is committed.

## Using a model

1. Settings → Models → tap a provider.
2. Paste its API key and confirm the model name and base URL.
3. **Test connection** does a real one-shot call.
4. **Use this model** makes it active.

Then open a project, ask for a change, and watch the tool calls land.

## Limits, stated plainly

- The shell has no Node, Python, Flutter or git binaries. It reads and writes
  files; it cannot execute them. `node -v` says so instead of pretending.
- Preview renders web projects only. Flutter and Python projects are edited and
  stored, not compiled on device.
- Agent runs depend on the provider's tool-calling support. Some small models
  cannot call tools reliably; pick a model that does.
- GitHub pushes text files only (binaries are skipped), one commit per file via
  the contents API. Vercel deploys are static; no build step runs server-side.
- No account, no analytics. Files and keys stay on the device.

## Layout

```
lib/
  core/        agent, ai client, shell, vfs, integrations, storage
  models.dart  project, provider, skill, chat types
  screens/     home, workspace, editor, settings, provider form
  workspace/   agent, files, shell, preview tabs
  theme/       tokens and theme
test/          vfs + shell, agent tool loop, provider errors
```

The `docs/` folder keeps the original reverse-engineering notes that informed
the product model.
