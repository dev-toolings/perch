# 05 — Design Fidelity

Raising Perch to a premium visual bar **in its own identity**. This is a
design/audit note only: no code changes are proposed as edits here, just
findings and surgical recommendations matched to the existing `Theme.swift`.

## Legal / ethical frame

A competitor app ("Vibe Island") is proprietary. Its NOTICE prohibits reverse
engineering and asset redistribution. Nothing in this document copies, extracts,
or re-bundles that app's creative assets. Where a token is genuinely open (a
libre font, a vendor's own brand mark, public pricing), it is legitimately
sourced **from the original author/vendor** — never lifted from a competitor's
bundle. Everything bespoke (app icon, wallpaper, ceremony sound) must be
original work.

---

## 1. Legit-sourcing table

| Asset | Verdict | Source of truth | Notes |
|---|---|---|---|
| **Font — Departure Mono** (Helena Zhang) | ✅ **REUSABLE** | Author's official distribution (`departuremono.com` / the author's release), under **SIL Open Font License 1.1** | Free/open font. Must be obtained from its original distribution, **not** from any competitor bundle. Perch **already does this correctly**: `apps/mac/Resources/Fonts/DepartureMono-Regular.otf`, registered per-process via `ATSApplicationFontsPath = Fonts` in `Scripts/make-app.sh` (the `.app`'s `Info.plist`), resolved in `Theme.swift` (`family = "DepartureMono-Regular"`). Ship the OFL license text alongside it. |
| **Third-party agent logos** (Claude, Codex, Gemini, Grok, Kimi, …) | ⚠️ **SOURCE FROM EACH VENDOR** | Each vendor's own brand/press kit | Use each vendor's official brand assets under their brand guidelines. Never from a competitor's asset pack. Trademarks stay the property of their owners; respect usage rules (clear space, no recolour where prohibited). Perch's fallback path already avoids the problem: agent glyphs fall back to **its own pixel-art** when no vendor sheet is installed (`AgentGlyph`, `IdleSprite`). |
| **Competitor app icon** | ⛔ **OFF-LIMITS** | — | Must be original. Design a distinct Perch mark. |
| **Competitor onboarding wallpaper** | ⛔ **OFF-LIMITS** | — | Must be original. |
| **Competitor ceremony/notification sound** | ⛔ **OFF-LIMITS** | — | Must be original (commission or synthesize your own). Perch already ships no sprite sheet it does not own — "what would be in one is not ours to redistribute" (`IdleSprite`). Hold the same line for audio. |
| **Model usage pricing** (token costs) | ✅ **DERIVE FROM PUBLIC PAGES** | Each vendor's public pricing page | Public facts, not creative work. Compute cost from published per-token rates; cite the vendor page. This is a data table, not an asset. |
| **Notch geometry / SwiftUI shape** | ✅ **ORIGINAL, KEEP** | Perch's own `NotchShape.swift`, `NotchGeometry.swift` | Derived from the hardware cutout (a physical fact) + Perch's own drawing. No sourcing concern. |

**Rule of thumb:** open-licensed inputs (font, public pricing) are fine from
their origin; vendor marks come from the vendor; anything a competitor authored
as a creative asset is off-limits and must be replaced with original work.

---

## 2. Audit — Perch's current visual system

Read from: `UI/Theme.swift`, `UI/NotchShape.swift`, `UI/Motion.swift`,
`UI/NotchRootView.swift`, `UI/SessionCardView.swift`, `Notch/NotchGeometry.swift`.

### Palette (`Theme.swift`)

A near-black instrument surface, hairline white borders, one saturated accent
per state. Auditable in one place as hex.

| Token | Value | Role |
|---|---|---|
| `surface` | `#000000` | Panel fill (matches the physical black cutout) |
| `raised` | `#1A1A1A` | Card fill (`opacity 0.55 → 0.9` on hover/select/open) |
| `hairline` | `white @ 8%` | Default border |
| `hairlineStrong` | `white @ 14%` | Hover/open border, selected tab background |
| `primary` | `white` | Primary text |
| `secondary` | `white @ 62%` | Secondary text |
| `tertiary` | `white @ 38%` | Chrome / timestamps / disabled |
| `active` | `#4ADE80` green | Working / succeeded / live dot |
| `claude` | `#D97757` | Claude brand → all permission signals |
| `info` | `#60A5FA` blue | Token counts, cache, rank, selection, Codex tint |
| `warning` | `#F59E0B` amber | Waiting-on-you, compacting, Gemini tint |
| `danger` | `#EF4444` red | Failure, permissive-permission badge |

Agent tints (`SessionCardView.agentTint`): Claude→claude, Codex→info,
Gemini→warning, opencode→active, unknown→secondary.

### Typography

**SwiftUI platform designs by intent:** the Vibe binary references the system
`monospaced`, `rounded` and `default` designs rather than a custom family. The
bundled `DepartureMono-Regular.otf` is an unused resource in the inspected app;
it must not be treated as the source of truth for the Island Bar typography.

- `mono(size, weight)` — system monospaced design for commands, paths and numbers.
- `label(size, weight)` — system rounded design for chrome, tabs and titles.
- `prose(size, weight)` — system default design for replies and paragraphs.
- `--diagnose` reports the active trio via `resolvedTypefaceName`.

**Observed size ladder (ad-hoc, not tokenized):** `7` (chevron), `8` (peek
chevron), `9` (age, children, chips, "recent"), `10` (most body/activity/peek),
`11` (titles, project, tabs). Sizes are passed as literals at each call site.

### Notch geometry (`NotchGeometry.swift`, `NotchShape.swift`)

- Cutout detected from `safeAreaInsets.top` + the gap between
  `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Synthetic fallback
  **190×32** on non-notch/external displays. User width/height tuning grows
  symmetrically around centre.
- `NotchShape` is **one persistent shape** for all states (so `animatableData`
  interpolates radii on the same spring as the frame — no popping). Two modes:
  - **strip** — full-width from the top; resting bar + flash.
  - **collar** — hardware-width for the menu-bar height, then flares out
    (`flare = 9`) into a full body below the bezel, preserving the menus either
    side of the cutout.
- Radii vary by state: idle bare strip `bottom 10 / shoulder 6`; painted resting
  strip `12 / 8`; open panel `bottom 18 / shoulder = NotchState.shoulder`; body
  top corners `topRadius 14`. Shoulders are inverse curves so corners meet the
  menu bar on a curve.

### Motion (`Motion.swift`)

- `morph` — `.spring(duration: 0.38, bounce: 0.14)`. The **one** curve for every
  dimension (width, height, radii, collar). Just short of critical damping.
- `content` — `.easeOut(0.16)`. Content swap, faster than the morph so incoming
  content is legible while the panel is still growing.
- `contentSwap` — **asymmetric** transition: insertion = opacity + `scale 0.97`
  from `.top`; removal = opacity only (avoids "sucked backwards through a hole").
- Local micro-motions: card hover/select `.easeOut(0.12)`, card open
  `.easeOut(0.16)`, switcher scroll `.easeOut(0.12)`, pulsing status dot
  `.easeInOut(0.9).repeatForever`.

### Notch layout — current geometry (ASCII)

```
                          menu bar (NOT ours — the collar preserves it)
  ┌───────────────────────╥──────────────╥───────────────────────┐
  │  auxiliaryTopLeftArea  ║   CUTOUT     ║  auxiliaryTopRightArea │
  │                        ║  190 × 32    ║                        │
  ╘════ LEFT FLANK ════════╝              ╚═══ RIGHT FLANK ════════╛
   glyph  gap  [chip]                      [waiting]  [count]
   (agents, breathing)   inset=5 | 5=inset  amber/claude pills
        flank = max(left,right)+inset, symmetric around cutout

  IDLE strip:  bottom 10 / shoulder 6  (bare) → 12 / 8 (painted)

  ── bezel ─────────────────╥──────────────╥─────────────────────
                            ║  collar =    ║          collarHeight
                            ║  cutout w.   ║          = notch h. (32)
                     flare=9 ╲            ╱ flare=9
  ┌──────────────────────────┘            └──────────────────────┐
  │  topRadius 14        PanelHeader (h=26, ±14 padding)          │
  │  ┌────────────────────────────────────────────────────────┐  │
  │  │ [glyph] project · title      chips…  age  ●  chevron    │  │  SessionCard
  │  │         activity line (info/warn)                       │  │  raised #1A1A1A
  │  └────────────────────────────────────────────────────────┘  │  radius 8, spacing 8
  │  ┌────────────────────────────────────────────────────────┐  │
  │  │ …                                                       │  │
  │  └────────────────────────────────────────────────────────┘  │
  │                                              bottomRadius 18   │
  └───────────────────────────────────────────────────────────────┘
        panel hangs BELOW the bezel; morph spring 0.38 / bounce 0.14
```

---

## 3. Recommendations — raise the bar, in Perch's own voice

Surgical, minimal, matched to the existing `Theme.swift` idiom (static tokens,
hex colours, one decision in one place). Each is additive; none changes the
identity (near-black instrument, mono display face, one accent per state).

### 3.1 Tokenize the type scale (highest leverage)

Sizes `7/8/9/10/11` are scattered as literals across every view. Promote them to
a named ladder on `Theme`, same shape as the colour block, so the rhythm is
auditable and consistent:

```
// A minor-third-ish ladder, tuned to Departure Mono's bitmap grid.
enum Size { micro=9, small=10, body=11, title=12 }   // + caption=8 for chrome only
```

Then bump the two densest text roles up one step: card **titles** `11 → 12` and
the **activity line** stays `10` but gains one point of leading. Rationale that
fits the file's voice: a display face earns a display size for the one line that
names the session; the sub-10 sizes stay for chrome only. This is the single
change that most reads as "premium" without touching the palette.

### 3.2 Spacing rhythm on a 4-pt grid

Spacing today mixes `2/3/4/5/6/8/14`. `Theme` already owns `rowSpacing = 8` and
`cornerRadius = 8`. Add a small spacing scale (`xs=4, sm=8, md=12, lg=16`) and
snap the odd values (`3`, `5`, `6`, `14`) to it where it doesn't fight optical
alignment. Keep the deliberate optical exceptions (glyph `.padding(.top, 4)`,
the `inset = 5` flank gap) — but make them the *documented* exceptions rather
than the norm. Consistent vertical rhythm is what separates a dense panel from a
cramped one.

### 3.3 Card hierarchy — one more level of depth

Cards currently separate from the panel only by fill opacity (`0.55 → 0.9`) and
a hairline. Two cheap, on-brand lifts:

- **Selected/open state:** the `info` border at `1.5pt` is good; add a
  barely-there inner accent (e.g. a 2-pt leading rule in `agentTint` on the open
  card) so an expanded card reads as *this agent's* card, reinforcing the
  per-agent colour already computed in `agentTint`.
- **Resting fill:** lift the closed-card fill floor from `0.55 → ~0.6` so cards
  never dissolve into `surface` black at the bottom of a long list. Purely a
  contrast/legibility win; no new token.

### 3.4 Motion — one easing token, two refinements

The spring discipline is already excellent (one `morph` curve for all geometry).
Two additions in the same spirit:

- Promote the repeated `.easeOut(0.12)` / `.easeOut(0.16)` literals into
  `Motion.micro` and reuse them, so local motion is also "one decision in one
  place" (mirrors the doc comment's own stated principle).
- The pulsing status dot uses `0.9s` ease-in-out; consider `1.1s` so a row of
  live sessions breathes slower and calmer — a menu-bar element that pulses too
  fast reads as an alert, not a heartbeat. Trivial, and it matches the existing
  "glanceable, not animated" intent stated in `IdleSprite`.

### 3.5 Notch geometry polish

The shape work is already strong. One refinement: the idle→painted→panel radius
jumps (`10/6 → 12/8 → 18/shoulder`) are interpolated by `animatableData`, which
is right. Consider making the **body top corners** (`topRadius 14`) and the
**bottom** (`18`) share a single ratio so the panel reads as one extruded solid
rather than two radii — e.g. keep bottom `18`, nudge `topRadius 14 → 16`. Sub-2pt
change, but it removes the faint "lid on a box" read when the panel is open.

### Non-goals (keep as-is)

- The **mono-everywhere** decision and the **prose exception** — both are
  well-reasoned in `Theme.swift` and are core to Perch's identity. Do not
  introduce a second display face.
- The **one-accent-per-state** palette. Don't add colours; the recommendations
  above reuse `info`, `agentTint`, and `surface`.
- The **single `morph` spring** for geometry. Untouched.
```
