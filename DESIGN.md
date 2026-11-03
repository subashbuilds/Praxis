# PolyDev — interface design

## Mode

**Operate.** The visitor is finishing a task on a phone, often one-handed,
often in bed. Success is a fast, legible loop between prompt → diff → run →
deploy. Expression lives in precision: hairlines, mono metadata, the ember
signal. Nothing animates for decoration.

## World

**Ember terminal.** The shipped mark is burnt orange (#D2603C) on graphite, and
the APK ships a github-dark stylesheet — so the interface is warm-black rather
than blue-black, with a single ember accent doing all the signalling. Inter
carries human copy, JetBrains Mono carries anything the machine produced
(paths, branches, commands, versions), Lora appears twice as an editorial
counterweight (wordmark, oversized empty/plan moments).

## Tokens

| role | value | notes |
|---|---|---|
| canvas | `#0A0908` | warm near-black, not `#000` |
| surface | `#12100E` | cards, sheets |
| raised | `#1A1714` | inputs, pressed cards |
| overlay | `#241F1B` | inactive control fill |
| line | `#2C2621` | 1 px hairline, the only border |
| line strong | `#3B342D` | focus / pressed border |
| text | `#F4EFE9` | 17.0:1 on canvas |
| text muted | `#B7ADA2` | 8.7:1 |
| text dim | `#877E74` | 4.7:1 |
| ember | `#E4693F` | 6.0:1 — icons, links, active tabs |
| ember deep | `#B94723` | gradient end, never text |
| on ember | `#1A0E08` | 5.9:1 on ember |
| mint | `#7FD1A8` | success / running preview |
| amber | `#E8B45C` | pending, storage, Python |
| rose | `#F07A6E` | destructive, removed lines |
| sky | `#8AB4F0` | Dart, keywords in code |

Accent discipline: ember marks *the current thing* — active tab, primary CTA,
agent attribution, focus ring, selected provider. It is never a background
wash, never used for success or warning (mint/amber own those).

Type scale: 30/25/16.5/14/13.5/12.5/11/10 with mono overlines at 10/1.6
tracking. Body line-height 1.5; code 1.62. Numerals in mono everywhere they
represent machine state.

Spacing: 4/8/12/16/20/24/32/40; page gutter 20. Radii: 10 (chips, inputs),
14 (cards), 18 (composer), 24 (sheets), 999 (pills). Motion: 110 ms press,
180 ms state, 320 ms tab settle, `easeOutCubic`.

## Layout rules

- No elevation, no shadows except a single ember glow under the primary CTA.
- One container shape: 1 px hairline on `surface`. Grouped lists use a single
  panel with inset dividers, not stacked cards.
- Machine text is uppercase-mono at 10 px with 1.6 tracking; it never competes
  with Inter headings.
- Thumb zone: workspace tabs sit at the bottom, composer above them; header
  actions stay in the top 48 px.
- Every tap target ≥ 44 px; switches and icon actions get 9 px padding.

## Screen intent

**Projects** — the only place the wordmark is large. One ember CTA, projects as
hairline cards with branch and freshness as mono metadata, device slot as a
plan reminder rather than a banner.

**Workspace** — the agent thread is the spine: user bubbles right, agent prose
left with the mark, tool output in a darker well. Files, shell and preview are
tabs, not separate routes, so state survives switching.

**Settings** — a ledger: grouped rows, status pills on the right, destructive
action isolated in its own group and confirmed by dialog.

## Accessibility

Text pairs above meet WCAG AA at their sizes; ember is only used for large or
bold text, icons and 1 px indicators. Icon-only actions carry tooltips and
semantics labels. Live states are text-labelled ("running", "passed"), not
colour-only. Layouts are built with `Flexible`/`Wrap` so 1.3× text scale does
not clip chips or tab labels.

## Known gaps

The shipped app's real screens were not observable (obfuscated AOT, no device),
so this is a designed reconstruction, not a pixel match. Rendering was not
verified in an emulator on this machine — no Flutter SDK/Android emulator was
available and the box is too small to build.
