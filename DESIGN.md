# DevNest — design notes

The interface is a tool, not a landing page: warm graphite, one ember accent,
hairlines instead of shadows, and type that distinguishes people from machines.
Code surfaces use GitHub's dark palette so edits and diffs feel familiar.

## Tokens

| Token | Value | Use |
|---|---|---|
| `Pal.canvas` | `#0A0908` | page background |
| `Pal.surface` | `#12100E` | panels, sheets |
| `Pal.raised` | `#1A1714` | inputs, chips, pills |
| `Pal.line` / `lineStrong` | `#2C2621` / `#3B342D` | 1 px borders |
| `Pal.text` | `#F4EFE9` | primary copy |
| `Pal.textMuted` / `textDim` | `#B7ADA2` / `#877E74` | secondary, meta |
| `Pal.ember` | `#E4693F` | primary action, active tab, brand |
| `Pal.mint` | `#7FD1A8` | success, ready, local |
| `Pal.amber` | `#E8B45C` | needs attention (no key, unsaved) |
| `Pal.rose` | `#F07A6E` | destructive and errors |
| `Pal.ghBg` / `ghPanel` / `ghLine` | `#0D1117` / `#161B22` / `#30363D` | editor and diff wells |
| `Pal.ghText` / `ghMuted` | `#E6EDF3` / `#8B949E` | code, comments |
| `Pal.ghKeyword` / `ghString` / `ghAttr` / `ghTag` / `ghNumber` | `#FF7B72` / `#A5D6FF` / `#D2A8FF` / `#7EE787` / `#79C0FF` | syntax |
| `Pal.ghAddBg` / `ghAddText` | `#12261E` / `#7EE787` | added diff rows |
| `Pal.ghDelBg` / `ghDelText` | `#2D1417` / `#FFA198` | removed diff rows |

Type: **Inter** for interface, **JetBrains Mono** for paths, commands, code and
diffs, **Lora** only for the wordmark. Radii: 10/14/24; pills for status and
controls. Motion is 110–320 ms `easeOutCubic`; no Material elevation or splash.

## Structure

- **Home** — wordmark, one promise, the active model, one ember primary action,
  then a hairline list of real projects.
- **Workspace** — a fixed header (project, kind, **Providers** pill), an
  optional strip of configured provider pills, then Agent, Files, Shell and
  Preview. The tab bar is the only chrome at the bottom.
- **Agent** — user messages are right-aligned ember-tinted bubbles; assistant
  copy is plain on the canvas. Reasoning is a collapsed **Thinking** pill, and
  tool calls are collapsed pills too. A write pill shows `+added / −removed` in
  mint and rose; opening it reveals a line-numbered GitHub diff. Tapping the
  open body collapses it. The composer keeps attach, text and send only.
- **Files / Preview** — both open with a ship bar: **Push** and **Deploy** run
  against the open project. Files explores disk; Preview renders the web entry.
- **Editor** — GitHub-dark panel, mono type, line-number gutter, language chip,
  saved/unsaved state and the wrap preference from Settings.
- **Shell** — the device's own `/system/bin/sh` in a near-black well, with a
  mint `device sh` pill, the real cwd, streaming output and exit codes.
- **Settings** — providers, skills (with import), integrations, continuation
  switches, editor and data.

## Rules

1. One accent for action and selection. Success is mint, risk is amber, failure
   is rose — never ember.
2. Status is always text plus colour, never colour alone.
3. Every container is a 1 px hairline on a flat surface. No elevation.
4. Machine output is mono; human copy is Inter. Diffs keep GitHub's +/− and
   red/green semantics, with old and new line numbers.
5. Destructive actions are confirmed and named in the copy.
6. Empty states say what will appear there and how to create it.
7. The mark is a rounded terminal frame with `>_` in ember; the launcher icon
   uses the same mark reversed on ember.
8. Provider pills always show which model they will call; a pill without a key
   opens its setup sheet instead of switching silently.

## Verified

`flutter analyze` clean; eighteen unit tests cover the path sandbox, both
shells, agent tool execution, diff rows and counts, provider JSON migration,
reasoning parsing, model-list parsing and key failover. UI is verified by
analysis only — the headless VM stalls when pumping the app.
