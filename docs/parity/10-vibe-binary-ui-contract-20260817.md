# 10 — Vibe Island 1.0.44: island UI contract read from the binary (2026-08-17, evening)

**Why this exists.** Doc 09 measured the visual gap from 1× JPEG captures and
flagged its font sizes/colours as ±0.5 pt / ±3/255 estimates. The person
asked for the reference to be extracted from the app itself. This document
holds the values **read from the arm64 slice of `/Applications/Vibe
Island.app/Contents/MacOS/vibe-island`** (build `44eb7db9bcfb`, 1.0.44) so
Perch can be adjusted to numbers, not impressions.

**Method.** `workflow-rev decompile` (static inventory → `.artifacts/
vibe-island-rev-20260817-r8/`), then: `otool -tvV` of the arm64 slice; Swift
`__swift5_proto` conformance records parsed to find each `View.body` getter
(resilient witness #6 of the `SwiftUI.View` conformance) — `conf.py`,
`bodygetters.json`; a call-trace extractor (`fn.py`, `flat.py`) that prints
every SwiftUI stub call with the immediates feeding it (`fmov`, 64-bit double
patterns in `x0/x2` for `Optional<CGFloat>` frame args, `__const` pool loads,
`Font.Design` case witnesses); a font-call harvester over all 657
`Font.system(size:weight:design:)` sites (`fonts3.py`, `fonts.json`). All
scripts and outputs live under `.artifacts/vibe-island-rev-20260817-r8/`
(`view-listings.txt`, `fonts.json`, `bodygetters.json`, `conformances.json`).

**Tags.** `[BIN]` read in the disassembly at the address given ·
`[BIN~]` read nearby but attribution to the view is inferred from string
context · `[OBS]` from a capture (doc 09).

**Boundaries.** No licence/trial/purchase code path was read or altered; no
asset was extracted; the study is limited to layout constants of the island
views. Vibe's pixel-art sprite rows were **not** extracted (their art).

---

## 0. Global

- Panel morph animation: `Animation.spring(response: 0.25, dampingFraction:
  0.7)` applied to the root `ZStack` `[BIN 0x100798424]`. Other springs in the
  same cluster: `(0.4, 0.8)`, `(0.3, 0.8)`; `easeOut(0.25)`; `easeOut(1.1)`;
  appear `scaleEffect(1.02)` `[BIN 0x10079a00c]`. Perch: `spring(duration:
  0.38, bounce: 0.14)` (`Motion.swift`).
- Session-card hover animation: `easeInOut(0.15)` `[BIN 0x10086fd48]`.
- Design usage across the whole binary: `.monospaced` witness referenced 98×,
  `.default` 11×, `.rounded` 3× (settings only) `[BIN fonts.json]`. The
  island chrome is **SF default**; monospace is used for the collapsed pill
  label, usage percentages, transcript bodies and command text.
- Content font size preference (`contentFontSize`, default 11) drives only
  the transcript / tool-detail views (`var`-sized calls cluster at
  0x733000–0x748000 and 0x805000–0x80d000). Session-card chrome sizes are
  **fixed**.

## 1. Collapsed pill (`NotchContentView`, cluster 0x100798000–0x1007b2000)

| Element | Value | Ref |
|---|---|---|
| Label (activity / title) | `Font.system(11, .semibold, .monospaced)`, `Color.white` | `[BIN 0x1007a2338, 0x1007a2634]` |
| "N sessions" caption | `Font.system(9, .medium)` SF, white 0.7 | `[BIN 0x1007a3090]` |
| Secondary mono caption | `Font.system(10, .medium, .monospaced)` | `[BIN 0x1007a3498]` |
| Sprite frames | 20×20 (single) and 32×20 (pair) with opacities 0.5 / 0.25 / 0.2 | `[BIN~ 0x1007a18b8, 0x1007a1a2c]` |
| Pill box | 194×30, bottom radius ≈12 | `[OBS idle.jpeg]` |
| Header buttons | `speaker.wave.2.fill` / `speaker.slash.fill`, `Font.system(13, .regular)`; gear same 13 regular | `[BIN 0x1007abed8, 0x1007ac310]` + strings |
| Header exclamation badge | `Font.system(10, .semibold)` | `[BIN 0x1007ad270]` |

## 2. Usage header (`UsageHeaderInline`, cluster 0x100a03000–0x100a10000)

| Element | Value | Ref |
|---|---|---|
| Window label (`7d`) | `Font.system(11, .bold)` SF | `[BIN 0x100a05b94]` |
| Percentage | `Font.system(11, .bold, .monospaced)` | `[BIN 0x100a05994]` |
| Reset time | `Font.system(11, .regular)` / `(11, .regular, .monospaced)` | `[BIN 0x100a05e7c, 0x100a067e4]` |
| Compact (`monthlyShort`) variant | 10 regular label, 10 semibold mono %, 9 mono reset | `[BIN 0x100a0eda8, 0x100a0efac, 0x100a0f2d8]` |
| Reset arrow / credit inline | 10 bold, 11 bold mono | `[BIN 0x100a071c8, 0x100a07344]` |
| Mini bar reset text | 8 regular / 9 semibold mono | `[BIN 0x100a0a6b8, 0x100a0ac88]` |

## 3. Session card (`SessionCardView`, cluster 0x10086eb88–0x1008809e0)

| Element | Value | Ref |
|---|---|---|
| Card container | `HStack(alignment: .center)`, `.padding(.horizontal, 8).padding(.vertical, 6)`, background `RoundedRectangle(cornerRadius: 10)` filled `white.opacity(0.08)` when hovered else `.clear`, overlay stroke `white.opacity(0.06)` lineWidth 1, `.animation(.easeInOut(0.15))` | `[BIN 0x10086f450–0x10086fd68]` |
| Secondary highlighted container | padding 8/8, radius 10, fill white 0.1, stroke white 0.08 | `[BIN 0x10086fef4–0x100870848]` |
| Title | `Font.system(12, .medium)` SF, white | `[BIN 0x100870e80, 0x100874eac]` |
| Small dot next to title | 6×6, white 0.2 | `[BIN 0x100870e08]` |
| "You:" prefix | `Font.system(11, .medium)` SF, white 0.5 | `[BIN 0x100877cfc, "User message prefix"]` |
| Prompt text | `Font.system(11)` SF, white 0.7 | `[BIN 0x100877e20]` |
| Status text (Working…, Ready, Thinking, Compacting) | `Font.system(11)` SF; medium for labels (Interrupted, Thinking, May need attention, Compaction completed) | `[BIN 0x10087a970, 0x10087ace8, 0x10087e4f0, 0x100879bd4, 0x10087f728, 0x10087ef18]` |
| Status text opacities | 0.9 (primary), 0.8, 0.7, 0.5, 0.4 (secondary) | `[BIN 0x100874810, 0x100879c5c, 0x10087a4ac, 0x10087b03c, 0x10087e6c8]` |
| Attention glyph | `exclamationmark.circle` 9 pt, `orange.opacity(0.8)`; label orange 0.7 | `[BIN 0x10087f5a0–0x10087f7a0]` |
| Small status glyphs | 9 pt (`arrow.triangle.2.circlepath`, `checkmark.circle.fill`, `exclamationmark.triangle.fill`) | `[BIN 0x10087e9b4, 0x10087edd4, 0x10087f1f4]` |
| Mono status variant | `Font.system(11, .medium, .monospaced)` | `[BIN 0x10087fa68]` |
| Brand colours | `Color(.sRGB, red:green:blue:opacity: 1)` per provider | `[BIN 0x1008715e4, 0x1008765e4]` |
| Inner rows padding | 4 / 4 | `[BIN 0x100873064, 0x1008732b4]` |

## 4. Tag pills / indicators

| View | Value | Ref |
|---|---|---|
| `TagPill` | `Font.system(9, .medium)` SF; `.padding(.horizontal, 5).padding(.vertical, 2)`; background `RoundedRectangle` filled `(brand ?? white).opacity(0.12)`; optional trailing icon `Font.system(7, .bold)`; text opacity 0.7 variant | `[BIN 0x100890088, 0x1008900bc, 0x1008900e0, 0x10089023c, 0x10089072c, 0x1008907dc]` |
| `JumpToTerminalPill` | label 9 medium (default design), `arrow.up.right` icon 7 semibold; hover `easeInOut(0.15)` | `[BIN 0x10088e9e0, 0x10088eaa0, 0x10088e140]` |
| `StateIndicator` | height 24; colours gray / green / purple / blue / orange at opacity 0.7 (0.4 inactive); dot geometry 3 / 2 | `[BIN 0x100883524–0x1008835b0]` |
| `ChildAgentsSection` container | padding 12 / 10, `RoundedRectangle(10)`, fill white 0.08, stroke white 0.15 lw 1 | `[BIN 0x1008837a4–0x1008839f4]` |

## 5. Task board (`TaskListView` 0x1008809e0, `TaskRowView` 0x10088285c)

| Element | Value | Ref |
|---|---|---|
| Container | `VStack(alignment: .leading)`, `.frame(maxWidth: .infinity, alignment: .leading)`, `.padding(.vertical, 10).padding(.horizontal, 12)`, background `RoundedRectangle(cornerRadius: 8)` filled `white.opacity(0.02)` | `[BIN 0x100880b8c–0x100880cf4]` |
| Header row | `HStack(.center)`, `.padding(.bottom, 3)` | `[BIN 0x10088103c]` |
| "Tasks" | `Font.system(11, .medium)` SF, white 0.5 | `[BIN 0x100881b90, 0x100881c04]` |
| Stats "(n done, n running, n open)" | `Font.system(10)` SF, white 0.35 | `[BIN 0x100881cb0, 0x100881d2c]` |
| Overflow "… +n done" | `Font.system(10)` SF, white 0.3, `.padding(.leading, 16)`, `.padding(.top, 2)` | `[BIN 0x1008826f8–0x1008827fc]` |
| Row | `HStack(.center)`, `.padding(.vertical, 2)`; mark column `.frame(12×12)` | `[BIN 0x10088346c, 0x1008829c8]` |
| Row text | `Font.system(11)` SF, white with per-status opacity table; done → `.strikethrough(true, color: white.opacity(0.2))` | `[BIN 0x100882a5c, 0x100882bdc, 0x100882c04]` |
| In-progress mark | 7×7 rounded shape, `blue.opacity(0.7)` | `[BIN 0x100882e8c, 0x100882ebc]` |
| Pending mark | 9×9 `RoundedRectangle(2)` stroke `white.opacity(0.25)` lw 1 | `[BIN 0x100883034–0x100883140]` |
| Done mark | `checkmark.square.fill` `Font.system(10)`, `white.opacity(0.35)` | `[BIN 0x100883200–0x100883280]` |

## 6. Free-mode CTA / footer / show-all (cluster 0x10086c000–0x10086eb88)

| Element | Value | Ref |
|---|---|---|
| CTA lock badge | icon 12 semibold white 0.9 in 28×28 circle white 0.08 | `[BIN 0x10086d5c0–0x10086d658]` |
| CTA arrow | 10 semibold white 0.55 | `[BIN 0x10086d758]` |
| CTA title / subtitle | 12 semibold white / 10 regular white 0.58 | `[BIN 0x10086dba8, 0x10086dd10]` |
| Footer "+n more sessions with a license" | 11 regular, white 0.48 (0.72 hovered), padding 2 / 4 | `[BIN 0x10086e5e8–0x10086e740]` |
| Show all sessions | 11 regular | `[BIN 0x10086c7f4]` |

## 7. Other island cards (font sites, `[BIN~]`)

- Codex hook trust banner: title 12 semibold, subtitle 10, button 11 medium
  (`0x10088aef4`, `0x10088b044`, `0x10088bd38`); other banners identical
  12 semibold / 10 (`0x100884404`, `0x100887620`).
- Empty state: title 13, subtitle 11, glyph 24, "Waiting for session" 12
  (`0x10088cba0`, `0x10088cd40`, `0x10088d08c`, `0x10088d1d8`).
- Completion card: `You:` prefix `contentFontSize` medium; body
  `contentFontSize` monospaced (`0x100807320`, `0x100807770`).
- Status warning card: `contentFontSize` semibold title / regular body
  (`0x100808798`, `0x1008088e8`).
- Question card: title 10 semibold, "(n questions)" 9, waiting 10 medium,
  wizard buttons 10–11 medium, multi-select badge 8 (`0x1007f1634`,
  `0x1007f187c`, `0x1007eef9c`, `0x1007fdd94`, `0x1007f93bc`).
- Approval: pending count 11 semibold, detail rows 9 medium / 9
  (`0x1007e5988`, `0x10073886c`, `0x10073a538`).
- Subagents section title 11 medium, count 10 (`0x1007680b0`, `0x10076824c`).
- Onboarding uses `Font.custom("DepartureMono…", 20)` for the tagline and a
  26 bold custom title (`0x1007d2598`, custom sites) — the only custom-font
  use found in the island/onboarding.

## 8. What this changes in doc 09

- VIBE-901: header is **11 bold** (label SF, % mono), not "~12 semibold SF".
- VIBE-905: title is **12 medium SF**, not "13 semibold"; prompt 11 regular
  white 0.7 with a 11 medium white 0.5 "You:" prefix.
- VIBE-908: pills are **9 medium SF**, padding 5/2, rounded-rect, opacity
  0.12 — Perch's TagPill is already 9 medium; only the design (mono→SF), the
  padding (4/1.5→5/2) and the shape (Capsule→RoundedRectangle) differ.
- VIBE-911/912: header 11 medium 0.5 + stats 10 0.35; rows 11; done rows
  strikethrough white 0.2; marks 7/9/10 in a 12 pt column; container radius
  8, white 0.02, padding 10/12.
- VIBE-921: collapsed label is **11 semibold monospaced white** — confirmed.
- New: morph spring `(0.25, 0.7)` vs Perch `(0.38 s, bounce 0.14)`.

## Not read

- `VStack`/`HStack` spacing values (generic inits, not stubs) — row pitch is
  taken from captures (≈22 pt).
- The per-status opacity table for task-row text (`ldr d0, [x9, x8, lsl #3]`
  at `0x100882adc`) — values not resolved; capture suggests ≈1.0 / 0.85 / 0.45.
- `NotchShape` corner radii and the collapsed/expanded width/height maths in
  `NotchWindowController` (AppKit side, not SwiftUI stubs).
- Sprite pixel rows (deliberately).
