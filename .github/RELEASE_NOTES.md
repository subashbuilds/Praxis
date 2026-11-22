## Praxis 2.2.0 — First public release

Praxis is a pocket-sized AI coding workbench for Android. It keeps your project in a normal folder on your phone and brings an editor, a device shell, an optional Alpine Linux environment, a live preview, and an AI coding agent together in one app.

### Highlights

- **An agent that finishes the job** — answers questions and explains code without forcing file edits, works through multi-step tasks with a live checklist, and resumes from the last completed step after a stop or provider limit.
- **Live thinking** — expandable reasoning that follows new output, pauses when you scroll up, and resumes when you return to the bottom. The panel stays open while new reasoning arrives.
- **GitHub from your phone** — clone, branch, compare, commit, push, and pull. Existing files, binaries, and deletions are handled without overwriting local edits, and files covered by `.gitignore` stay out of pushes.
- **Build logs without guessing** — read GitHub Actions logs for any job by id or name, paged from the failure to the start of the log. Cloudflare Pages and Vercel build logs are available too.
- **A real editor** — syntax highlighting, line numbers, word wrap, find and undo, Markdown preview, image and SVG previews, and binary-safe storage.
- **Files that stay yours** — projects are ordinary folders. Import files or merge whole folders, with collision handling and byte-preserving copies.
- **On-device shell and Alpine Linux** — run the tools installed on the phone through the device shell, or prepare Alpine 3.21.7 with Node.js, Python, PHP, or Go. The project is mounted at `/workspace`.
- **Live preview** — inspect static web projects, Markdown, images, and SVGs without leaving the app.
- **Skills and templates** — create reusable instructions, import `.md` files, discover public `SKILL.md` skills, and start projects from built-in templates.
- **Integrations** — GitHub, Vercel, Cloudflare, Expo EAS, Tavily web search, and Supabase. Credentials stay on the device and are never shown to the agent.

### Reliability

- Planned answers and reviews complete without an unnecessary edit round.
- Reverting a waiting commit brings its files back as uncommitted edits with their diffs intact.
- GitHub Actions logs can target any job in a run, not only the first failing jobs.
- Ignored files never appear in the push sheet, so generated output and secrets cannot be committed by accident.
- Reset now removes saved conversations, drafts, checklists, and checkpoints along with project files.
- Fixed a streaming timer leak, false continuation prompts after polite closings, and stale draft restoration after a finished reply.
- Rejects non-GitHub URLs instead of mistaking another host for a repository owner.

### Download

- `Praxis-2.2.0-universal.apk` — recommended for most devices
- `Praxis-2.2.0-arm64-v8a.apk` — smaller package for modern 64-bit phones
- `Praxis-2.2.0-armeabi-v7a.apk` — for older 32-bit phones

Requires Android 7.0 or newer. The release workflow records each APK's SHA-256 in the run summary.

### Getting started

1. Install the APK.
2. Open **Settings → Providers** and add an OpenAI-compatible endpoint, API key, and model.
3. Create a project, clone a repository, or start from a template.
4. Optional: connect GitHub in **Settings → Integrations** for commits, branches, and Actions logs.
5. Ask the agent for a change, or edit files directly.

### Notes

- Bring your own provider key. Keys remain on the device and are not included in prompts.
- The bundled Alpine environment currently targets arm64-v8a devices; package installs require network access.
- Cloudflare Pages deploys static output on-device. Server-side Workers code should be built and deployed on a desktop or CI runner.
- This is the first public release. Please report issues with the app version and, where possible, the relevant build or agent log.
