# DevNest — design notes

The interface is a tool, not a landing page: warm graphite, one ember accent,
hairlines instead of shadows, and type that distinguishes people from machines.

## Tokens

| Token | Value | Use |
|---|---|---|
| `Pal.canvas` | `#0A0908` | page background |
| `Pal.surface` | `#12100E` | panels, sheets |
| `Pal.raised` | `#1A1714` | inputs, chips |
| `Pal.line` / `lineStrong` | `#2C2621` / `#3B342D` | 1 px borders |
| `Pal.text` | `#F4EFE9` | primary copy |
| `Pal.textMuted` / `textDim` | `#B7ADA2` / `#877E74` | secondary, meta |
| `Pal.ember` | `#E4693F` | primary action, active tab, brand |
| `Pal.mint` | `#7FD1A8` | success, ready, local |
| `Pal.amber` | `#E8B45C` | needs attention (no key, unsaved) |
| `Pal.rose` | `#F07A6E` | destructive and errors |
| `Pal.terminal` | `#070706` | shell well, code blocks |

Type: **Inter** for interface, **JetBrains Mono** for paths, commands and code,
**Lora** only for the wordmark. Radii: 10/14/24; pills for status. Motion is
110–320 ms `easeOutCubic`; no Material elevation or splash.

## Structure

- **Home** — wordmark, one promise, the active model, one ember primary action,
  then a hairline list of real projects.
- **Workspace** — a fixed header (project, kind, model state) over four tabs:
  Agent, Files, Shell, Preview. The tab bar is the only chrome at the bottom.
- **Agent** — the transcript uses overlines (`YOU`, `DEVNEST`) rather than
  bubbles; tool calls become bordered cards with a mono header and a code well.
  Errors are bordered rose panels, never silent.
- **Files / Shell / Preview** — the three ways to inspect the same folder, so
  the agent's work is always checkable by hand.
- **Settings** — providers first, then skills, integrations, editor, data.

## Rules

1. One accent for action and selection. Success is mint, risk is amber, failure
   is rose — never ember.
2. Status is always text plus colour, never colour alone.
3. Every container is a 1 px hairline on a flat surface. No elevation.
4. Machine output is mono; human copy is Inter. Do not mix.
5. Destructive actions are confirmed and named in the copy.
6. Empty states say what will appear there and how to create it.
7. The new mark is a rounded terminal frame with `>_` in ember; the launcher
   icon uses the same mark reversed on ember.

## Verified

`flutter analyze` clean; ten unit tests cover the path sandbox, the shell's
real file operations, agent tool execution and provider error mapping. UI is
verified by analysis only — the headless VM stalls when pumping the app.
