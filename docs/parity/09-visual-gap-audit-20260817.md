# 09 — Visual gap audit: Vibe Island 1.0.44 island vs Perch (2026-08-17, PM)

**Question.** Doc 08 says the main island is "Matched". The person using both
apps says it is not. Which is right, where exactly does the island diverge, and
what would have to change in Perch for the island to read as the same product?

**Reference.** `/Applications/Vibe Island.app`, `CFBundleShortVersionString`
1.0.44, build `44eb7db9bcfb`, proprietary (Superfluous Studio, `NOTICE.txt`
forbids reverse engineering). **Method for this document: black-box only** —
the existing 1× captures under `.artifacts/vibe-island-captures/` and
`.artifacts/vibe-island-reaudit-20260817-r*/`, cropped and zoomed 3× with a
CoreGraphics helper, plus pixel probes (crops and helpers kept under
`.artifacts/visual-gap-20260817/`). Written first as a black-box audit; then,
at the person's explicit request, the numbers were **re-read from the binary**
— see **doc 10** (`10-vibe-binary-ui-contract-20260817.md`), which supersedes
every font size / opacity estimate below. Where doc 10 contradicts a finding
here, the finding carries a `→ doc 10:` note and doc 10 wins.

**Ours.** Perch `main` @ working tree of 2026-08-17 (uncommitted), sources
`apps/mac/Sources/PerchApp/UI/*` and `Notch/*`. Perch side evidence: the live
captures in `.artifacts/perch-captures/fresh/expanded-live-r101.jpeg` and
`.artifacts/perch-local-reaudit-20260817-r2/current/native-final-*.jpeg`, plus
`Perch --render` off-screen renders (`.artifacts/visual-gap-20260817/renders/`).

**Prior art.** Docs 05 (design fidelity), 06 (ISO audit), 07 (static contract),
08 (live comparison). This document *extends* 08 and downgrades several of its
"Matched" rows. IDs continue as `VIBE-9xx`.

**Tags.** `[OBSERVED]` measured on a capture · `[VERIFIED]` read in Perch source
at `file:line` · `[INFERRED]` deduced, says from what · `[UNKNOWN]` looked, could
not tell.

---

## Verdict

Doc 08's "Matched" rows for the main island are **structural**, not visual: the
canvas is 680×580, the section order is right, the pieces exist. What the eye
sees is still two products, for four reasons that are all in Perch's own code:

1. **Typeface family.** Vibe's island chrome is SF (system default) at 12–13 pt,
   regular/semibold, white on black; monospace appears only inside transcript
   bodies and the compact strip. Perch draws the usage header, tag pills, task
   overflow, activity lines and the whole compact strip in `Theme.mono` at 9–10
   pt, and its "label" design is `.rounded`, which Vibe does not use in the
   island. Two points smaller and a different family is the single largest
   contributor to "pas iso" (VIBE-901..904).
2. **Contrast.** Perch's `secondary` is 62 % white and `tertiary` 38 %; Vibe's
   compact strip label and count are ~100 % white bold, its task-board heading is
   ~70 % white semibold, its done-rows are ~45 % white with strikethrough. Perch
   reads dimmer everywhere except the in-progress task row (VIBE-905, 913).
3. **Containers.** Vibe's task board and unlock CTA are rounded cards with a
   ~2–3 % white fill (task) or 5 % fill + hairline (CTA), 20 pt / 12 pt inset
   from the panel edge; Perch's task board is bare text with a −42 pt gutter hack
   (VIBE-910..912). Vibe's transcript card has a two-tone header/body; Perch's
   is close (VIBE-915).
4. **Sprites and marks.** Vibe's compact strip and card carry a two-sprite
   status pair (large + small companion, colour by state) drawn *right next to
   each other*, and its label sits at the trailing edge beside the count. Perch
   draws one sprite of a different silhouette and a left-aligned dim label
   (VIBE-920..923). Header icons differ: Vibe uses filled `gearshape.fill` and a
   grey `speaker.slash`; Perch outline gear and an orange mute (VIBE-903).

Settings panes and onboarding are within polish distance (VIBE-930..933) and
are **not** the reason the app looks wrong. Alert / permission / notification /
question states of Vibe were **never captured** and remain `[UNKNOWN]`
(VIBE-940); they cannot be compared until a Screen Recording capture of Vibe in
those states exists.

**Moves, in order:** (1) retype the island — one `Theme` change per role, no
per-view fiddling; (2) task board and CTA/footer as cards with Vibe's insets;
(3) compact strip: alignment, weight, sprite pair; (4) header icons and usage
chip; (5) then capture Vibe's alert/notification/question states and repeat.
Explicitly deferred: commercial CTA content (product-model), extra locales,
animation-curve byte parity.

---

## Findings

### A. Expanded panel — header (`ExpandedView`, `UsageHeaderCycle`, `UsageLimitsStrip`)

- **VIBE-901** Usage chip typography. Vibe: `[OBSERVED]` round grey provider
  badge (≈12 pt circle, light grey), then `7d` **white semibold ~12 pt SF**,
  `90%` **red semibold**, `3d2h` grey regular — all sans, baseline y≈17
  (`expanded-live-r78.jpeg` crop `v-header.png`). Perch: `[VERIFIED]`
  `Theme.mono(9)` tertiary label + `Theme.mono(9, .semibold)` percentage +
  `Theme.mono(9)` reset (`UsageLimitsView.swift:172-191`), badge is a 12×12
  `RoundedRectangle(cornerRadius: 3)` at 45 % white with a 7 pt SF Symbol
  (`NotchRootView.swift:980-996`). Gap: family (mono vs SF), size (9 vs ~12),
  colour of the label (38 % vs ~100 %), badge shape (rounded square vs circle).
  → doc 10: label `11 bold` SF, percentage `11 bold monospaced`, reset `11
  regular` (`UsageHeaderInline`).
- **VIBE-902** Percentage colour scale. Vibe at 90 %: pure red `[OBSERVED]`.
  Perch at 90 %: orange (`Theme.warning` per the tint ramp) `[OBSERVED
  expanded-live-r101]`. Threshold or ramp differs; Vibe's 76 % is orange-red
  (`expanded-session-with-pass.jpeg`), so Vibe's ramp reaches red earlier.
- **VIBE-903** Header buttons. Vibe: `[OBSERVED]` grey `speaker.slash` (~13 pt,
  ~55 % white) and **filled** `gearshape.fill` (~14 pt, ~85 % white), centres at
  x≈603 and x≈632, y≈18. Perch: `[VERIFIED]` `ShoulderButton` 12 pt semibold,
  `speaker.slash` tinted `Theme.warning` (orange) when muted, `gearshape`
  outline in `Theme.tertiary` (`NotchRootView.swift:329-346, 883-897`). Gap:
  weight/fill, size, colour.
- **VIBE-904** Header band height. Vibe: chip and buttons centred at y≈17–18
  under a canvas whose panel body starts at y=0 `[OBSERVED]`. Perch: 40 pt
  header row (`NotchRootView.swift:899`) with content at y≈20 `[OBSERVED
  r101]`. ≈2–3 pt lower; minor.

### B. Expanded panel — session card (`SessionCardView`, `SessionCardTitleParts`, `TagPill`)

- **VIBE-905** Title row. Vibe: `[OBSERVED]` `perch · Recopier la vibe Island
  dans Perch` in **SF semibold ~13 pt white**, dot separator ~55 % white; title
  baseline y≈57, starts x≈84 (48 pt after the sprite column start at x≈36).
  Perch: `[VERIFIED]` `Theme.label(fontSize + 1, .semibold)` = **SF Rounded 12
  pt** (`SessionCardView.swift:563`), title x≈68 `[OBSERVED r101]`. Gap:
  rounded vs default design, 1 pt, and 16 pt less indent. → doc 10: title is
  `Font.system(12, .medium)` SF (crop over-estimated weight/size); the indent
  gap stands.
- **VIBE-906** Prompt line ("Vous : …"). Vibe: `[OBSERVED]` SF regular ~12 pt,
  ~65 % white, directly under the title (≈18 pt baseline-to-baseline), same x as
  title. Perch: `[VERIFIED]` `Theme.prose(contentFontSize)` = SF 11 pt,
  `Theme.secondary` (62 %) (`SessionCardView.swift:163-164`); **not shown in the
  live capture r101** because `[VERIFIED]` `PanelLayout.showsPrompt` and
  `showsTasks` are both `self == .detailed` (`PerchKit/Preferences.swift:27-28`)
  and Clean is the default (doc 08). Vibe's Clean/default panel shows the
  prompt line **and** the task board (`collapsed-session-with-pass.jpeg`,
  `expanded-live-r78.jpeg`) — so Perch's Clean mode hides two things Vibe's
  Clean mode shows. This is a behaviour gap, not a styling one.
- **VIBE-907** Activity line (Clean mode). Vibe: `[OBSERVED]` `Bash` in blue
  SF ~11 pt + command in grey SF, one line, under the prompt
  (`collapsed-session-with-pass.jpeg` y≈92). Perch: `[VERIFIED]`
  `Theme.mono(contentFontSize - 1)` tinted (`SessionCardView.swift:365-366`)
  → 10 pt monospace. Gap: family and size.
- **VIBE-908** Tag pills. Vibe: `[OBSERVED]` `Codex` blue text on ~10 % blue
  capsule, `ChatGPT` / `cmux` / `<1m` ~70 % white on ~10 % white; **SF ~10.5 pt
  medium**, ≈5 pt horizontal / 2 pt vertical padding, corner ≈4 (rounded rect,
  not a full capsule); `BYPASS` red on 12 % red. Perch: `[VERIFIED]`
  `Theme.mono(9, .medium)`, `padding(.horizontal, 4) .vertical(1.5)`,
  `Capsule()` (`SessionCardView.swift:768-775`). Gap: monospace vs SF, 9 vs
  ~10.5, capsule vs rounded-rect. → doc 10: Vibe `TagPill` is `9 medium` SF,
  padding 5/2, `RoundedRectangle`, `(brand ?? white).opacity(0.12)` — so the
  size already matches; design, padding and shape differ.
- **VIBE-909** Status dot. Vibe: green dot **between** the client pill and the
  jump pill (`^G ↗`) on the Claude card, none on the Codex card `[OBSERVED
  expanded-session-with-pass / expanded-live-r78]`. Perch: green dot **after**
  the age pill on the Codex card `[OBSERVED r101]`. Order/eligibility differs.

### C. Expanded panel — task board (`TaskBoardView`)

- **VIBE-910** Container. Vibe: `[OBSERVED]` the board sits in a rounded card
  x 36→643 (≈608 wide = panel width − 2×20), y 107→228, fill ≈#040404–#050505
  over #000 (≈2–3 % white), radius ≈10, no visible stroke. Perch: `[VERIFIED]`
  no background; `TaskBoardView` pads 4/7 and the card pulls it into the gutter
  with `.padding(.leading, -42).padding(.trailing, -42)`
  (`SessionCardView.swift:203-207`, `TaskBoardView.swift:38-41`).
- **VIBE-911** Heading. Vibe: `[OBSERVED]` `Tâches` **SF semibold ~12 pt ~70 %
  white**, then `(5 terminées, 1 en cours, 0 ouvertes)` regular ~11.5 pt ~55 %.
  Perch: `[VERIFIED]` one string in `Theme.label(10, .medium)` `Theme.tertiary`
  (`TaskBoardView.swift:24-27`) → SF Rounded 10 pt at 38 %. Gap: split
  weight, size, family, contrast.
- **VIBE-912** Rows. Vibe: `[OBSERVED]` in-progress: blue filled dot ≈7 pt +
  **white SF ~12.5 pt medium**; done: grey **filled checkbox with tick**
  (`checkmark.square.fill`, ~11 pt, ~45 %) + **strikethrough** ~45 % white text;
  overflow `… +3 terminées` SF ~11.5 pt ~45 %, indented to the text column; row
  pitch ≈22 pt; heading→first row ≈22 pt. Perch: `[VERIFIED]` marks 8 pt
  (`TaskBoardView.swift:70-73`), text `Theme.label(11, …)` (SF Rounded 11),
  no strikethrough, overflow `Theme.mono(9)` (`TaskBoardView.swift:34`), row
  spacing 8 (≈19 pt pitch, matches the height formula at
  `NotchRootView.swift:851`). Gap: family/size, strikethrough, overflow font,
  pitch. → doc 10 §5: heading `11 medium` white 0.5 + stats `10` white 0.35;
  rows `11` SF, done rows `.strikethrough(color: white 0.2)`; marks 7×7 blue
  0.7 / 9×9 stroke white 0.25 / `checkmark.square.fill` 10 white 0.35 in a 12
  pt column; overflow `10` white 0.3 indented 16; container radius 8, white
  0.02, padding 10 / 12.
- **VIBE-913** Contrast of open rows. Vibe: open (pending) rows show an empty
  square + ~85 % white text (`expanded-live-r78` has 0 open, so this is
  `[INFERRED]` from Vibe's done/in-progress ramp — needs a capture with open
  tasks). Perch: `Theme.secondary` 62 % `[VERIFIED TaskBoardView.swift:104]`.

### D. Expanded panel — transcript, CTA, footer

- **VIBE-914** Transcript card. Vibe: `[OBSERVED]` header band `Vous :` grey SF
  ~11.5 pt left, `Terminé` grey right, band fill ≈#161616, body fill ≈#0B0B0B,
  body text **SF Mono ~11.5 pt ~90 % white** with 1 blank line between blocks,
  card x 36→643, radius ≈10, hairline stroke, a scrollbar at the right. Perch:
  `[OBSERVED --render]` header `You:` **mono green** + prompt in SF; body SF
  prose. Gap: header label font/colour, body family (Vibe keeps raw markdown in
  mono; Perch renders it).
- **VIBE-915** Unlock CTA row (`FreeModeCallToActionRow`, doc 07). Vibe:
  `[OBSERVED]` x 28→652, y 244→296 (52 pt), fill #0D0D0D + 1 pt #171717
  stroke, radius ≈12; lock glyph in a 28 pt grey circle; title SF semibold 13
  white; subtitle SF 11 ~65 %; `↗` at the right. Perch: absent by decision (doc
  08). **SKIP** stays; but the *footer line* below it (`+1 sessions
  supplémentaires avec une licence`, SF 11 ~55 %, centred, y≈309) is what gives
  Vibe's panel its bottom margin (~20 pt under the last card). Perch ends 12 pt
  under the last row (`NotchRootView.swift:903`) → panel bottom looks tighter.
- **VIBE-916** Panel width and margins. Vibe: `[OBSERVED]` body x 16→663
  (648 pt) in the 680 canvas; content gutter 20 pt (session sprite x≈36, task
  card x=36), CTA gutter 12 pt. Perch: body ≈650 `[doc 08]`, `.padding
  (.horizontal, 20)` `[VERIFIED NotchRootView.swift:899-905]`. **Match**.

### E. Compact / resting strip (`IdleView`, `PixelStatusIconCompact`)

- **VIBE-920** Geometry. Vibe: `[OBSERVED idle.jpeg / idle-working-two.jpeg]`
  black pill x 243→437 (**194 pt**) × 30 pt, bottom corners ≈12, no stroke.
  Perch: `[OBSERVED native-final-rest]` x≈243→437 too, height 28
  (`NotchRootView.swift:592`). **Match** on the box.
- **VIBE-921** Label. Vibe: `[OBSERVED]` **SF Mono bold ~11 pt, ~100 % white**,
  `Recopier la vibe…` (idle → session title) / `Bash: sed -n 206,…` (working →
  tool + args), **right-aligned against the count** with ≈14 pt gap; count
  `2` bold ~11 pt white, right padding ≈12. Perch: `[VERIFIED]` label
  `Theme.mono(9)` `Theme.secondary` (62 %), `maxWidth: 102, alignment:
  .leading` then `Spacer` then count `Theme.mono(10)` (`NotchRootView.swift:
  552-580`). Gap: size (9 vs 11), weight (regular vs bold), colour (62 % vs
  100 %), alignment (leading vs trailing).
- **VIBE-922** Sprites. Vibe: `[OBSERVED v-work.png]` primary sprite ≈20×14 at
  x≈250, companion ≈11×11 immediately after (gap ≈4), colours by state: green
  idle-done, blue working, amber needs-you; the *primary* sprite is brighter
  than the companion. Perch: `[VERIFIED]` `PixelStatusIconCompact` rows exist
  with 2 pt / 1 pt cells (`NotchRootView.swift:420-481`), tint at 72 % opacity
  for `x` cells; `[OBSERVED p-idle.png]` the drawn sprite is a *different
  silhouette* (Space-Invader with antennae, ≈9×7 cells at 2 pt = 18×14) and
  visibly bluer/dimmer than Vibe's. Gap: silhouette rows and opacity.
- **VIBE-924** What Clean / Detailed means. Vibe: `[OBSERVED
  display-native-1012, crop v-display-modes.png]` the two thumbnails are
  **compact-strip** schematics — Épurée: dot + count; Détaillée: dot + title
  bar + count + statuses — with the captions "Plus de place pour la barre de
  menus" / "Titres et statuts des sessions visibles d…". The setting governs
  how much the **collapsed strip** says. Perch: `[VERIFIED]` the same two
  labels and the same "More room for the menu bar" caption
  (`fr.lproj/Localizable.strings:212,393-395`), but the enum drives the
  **expanded panel** (`PanelLayout.showsPrompt/showsTasks`,
  `Preferences.swift:27-28`, consumed at `NotchRootView.swift:839-846,1035`),
  and nothing in the compact strip reads it. Same words, different meaning:
  Perch Clean strips content Vibe never strips, and Perch Detailed does not
  widen the strip as Vibe's does. `[INFERRED]` from thumbnails + captions;
  a live Vibe capture in Détaillée would make it `[OBSERVED]`.
- **VIBE-923** Idle text choice. Vibe idle shows the **session title**; Perch
  shows the last activity `exec` `[OBSERVED]`. `[INFERRED]` from one capture
  each — confirm with a second idle capture on Vibe.

### F. Settings and onboarding (regression check only)

- **VIBE-930** General/Notifications/Display/Sound: same controls, same
  defaults `[OBSERVED r3 vs local r2]`. Residual: Perch shows a sidebar-toggle
  glyph in the title bar and larger traffic lights (window style), Vibe's popup
  buttons have a bordered chevron style; row separators inside grouped forms.
  **Polish only.**
- **VIBE-931** Onboarding "Tout est prêt" card: same layout, copy, switches,
  pager `[OBSERVED r105 vs r106]`. **Match.**
- **VIBE-932** Onboarding icon: Vibe's badge (white rounded square with the
  black pixel creature) vs Perch's black icon `[OBSERVED]`. Own asset;
  **SKIP** (not ours to copy).
- **VIBE-933** Display pane preview strip: Vibe's preview pill renders the
  compact label in the same bold mono as the live strip; Perch's preview
  renders `Recopier la vibe Island…` lighter `[OBSERVED display-native-1012 vs
  display-final-native-1022]`. Fixing VIBE-921 fixes this if the preview shares
  `IdleView`.

### F2. Motion

- **VIBE-925** Panel morph. Vibe: `[BIN doc 10 §0]` `spring(response: 0.25,
  dampingFraction: 0.7)` on the root ZStack, hover highlights `easeInOut
  (0.15)`, appear `scaleEffect(1.02)`. Perch: `[VERIFIED]` `spring(duration:
  0.38, bounce: 0.14)` + content `easeOut(0.16)` (`Motion.swift`). Vibe's is
  ≈35 % faster and slightly less bouncy. **COPY**.

### G. Not observable yet

- **VIBE-940** `[UNKNOWN]` Vibe's permission alert, completion notification
  card (`CompletionCardView`), question card, status warning card
  (`StatusWarningCardView`), child-agent attention row, hover-peek, and every
  transition (hover expand, mouse-leave collapse, completion dwell). No capture
  exists in `.artifacts`. Perch has its own alert/flash/peek designs
  (`--render --phases`), and doc 08 only proves click-expand/collapse. Until
  those Vibe states are captured, any parity claim about them is unfounded.

---

## Matrix

| Capability | Vibe 1.0.44 (tagged) | Perch today (tagged) | Gap | Decision | Why | Owner | Evidence |
|---|---|---|---|---|---|---|---|
| Canvas / body width | 680 canvas, 648 body, 20 pt gutter `[OBS]` | 680 / ≈650 / 20 `[VER]` | none | — | already matched | client | VIBE-916 |
| Island typeface roles | SF default for chrome; SF Mono only for transcript body + compact strip `[OBS]` | `.rounded` labels, mono for pills/usage/overflow/activity `[VER]` | family + 1–3 pt | **ADAPT** | keep `Theme` tokens, change their resolution | client | VIBE-901,905,907,908,911,912,921 |
| Text contrast ramp | ≈100/70/45 % `[OBS]` | 100/62/38 % `[VER]` | secondary/tertiary too dim | **COPY** | pure token change | client | VIBE-905,911,913,921 |
| Usage header chip | circle badge, SF 12 semibold, red at 90 % `[OBS]` | rounded-square badge, mono 9, orange at 90 % `[VER]` | shape/family/size/ramp | **COPY** | glanceable numbers, no invariant | client | VIBE-901,902 |
| Header buttons | grey `speaker.slash`, filled gear `[OBS]` | orange mute, outline gear `[VER]` | fill/colour | **COPY** | — | client | VIBE-903 |
| Session title/prompt/activity | SF 13 semibold / 12 / 11 with 48 pt text indent `[OBS]` | SF Rounded 12 / SF 11 / mono 10, 32 pt indent `[VER]` | family/size/indent | **COPY** | — | client | VIBE-905..907 |
| Clean layout content | prompt line + task board always in the panel `[OBS]` | `showsPrompt`/`showsTasks` false in Clean `[VER]` | two sections missing by default | **COPY** | Clean = less chrome, not less content | client | VIBE-906 |
| Clean / Detailed semantics | governs the compact strip verbosity `[INF]` | governs the expanded panel `[VER]` | wrong surface | **ADAPT** | keep the preference key, re-point it at the strip; panel content follows the Session Card toggles | client | VIBE-924 |
| Tag pills | SF 10.5 medium, rounded-rect r≈4 `[OBS]` | mono 9, capsule `[VER]` | family/shape | **COPY** | — | client | VIBE-908 |
| Status dot position | before jump pill, Claude only `[OBS]` | after age pill, Codex too `[OBS]` | order/eligibility | **ADAPT** | keep Perch's eligibility rule, move the dot | client | VIBE-909 |
| Task board container | card, 2–3 % white, r≈10, 20 pt gutter `[OBS]` | bare, −42 pt hack `[VER]` | container | **COPY** | remove the negative padding, add the card | client | VIBE-910 |
| Task heading/rows | split-weight heading, strikethrough done, 22 pt pitch `[OBS]` | single tertiary heading, no strike, 19 pt pitch `[VER]` | style | **COPY** | — | client | VIBE-911..913 |
| Transcript card | two-tone, mono body, `Vous :` grey `[OBS]` | close; header label mono green `[OBS]` | header + body family | **ADAPT** | keep Perch's markdown rendering, retype header | client | VIBE-914 |
| Unlock CTA / footer | card + centred footer line `[OBS]` | absent `[VER]` | product | **SKIP** (CTA) / **ADAPT** (bottom margin) | no licence backend; keep the ~20 pt bottom breathing room | client | VIBE-915 |
| Compact strip box | 194×30, r 12 `[OBS]` | 194×28 `[VER]` | 2 pt | **COPY** | — | client | VIBE-920 |
| Compact label/count | mono bold 11 white, trailing `[OBS]` | mono 9 62 % leading `[VER]` | size/weight/colour/alignment | **COPY** | — | client | VIBE-921 |
| Panel morph curve | `spring(0.25, 0.7)` `[BIN]` | `spring(0.38 s, bounce 0.14)` `[VER]` | speed | **COPY** | one token in `Motion.swift` | client | VIBE-925 |
| Compact sprites | 20×14 + 11×11 pair, bright primary `[OBS]` | different rows, 72 % tint `[VER]` | silhouette/opacity | **ADAPT** | redraw our own rows to Vibe's proportions and state colours; do not copy pixels 1:1 (their art) | client | VIBE-922 |
| Idle label content | session title `[INF]` | last activity `[OBS]` | content | **WATCH** | confirm on a second capture, then copy | client | VIBE-923 |
| Settings panes | same controls `[OBS]` | same `[OBS]` | title-bar chrome | **ADAPT** | polish after the island | client | VIBE-930 |
| Onboarding | same `[OBS]` | same `[OBS]` | icon asset | **SKIP** | not ours | — | VIBE-931,932 |
| Alert / notification / question / peek / transitions | `[UNKNOWN]` | own designs `[VER]` | unknown | **WATCH** | needs Screen Recording capture of Vibe first | user + client | VIBE-940 |

---

## Recommended moves (ordered)

0. **Clean layout shows the prompt line and the task board** (`PanelLayout`
   flags) — the cheapest and most visible fix (VIBE-906) — and re-point the
   Clean/Detailed preference at the compact strip, where Vibe has it
   (VIBE-924).
1. **Retype the island in `Theme.swift` only** — `label()` → `.default`
   design; sizes per doc 10 (title 12 medium, body 11, captions 10, pills 9
   medium, collapsed 11 semibold mono); opacities per element (0.9 / 0.7 /
   0.5 / 0.35 / 0.3) rather than a single `secondary`/`tertiary`. Then fix the callers that hard-code
   `Theme.mono(9)` for non-code text (VIBE-901, 907, 908, 912, 921).
2. **Task board as a card** — background `Color.white.opacity(0.03)`, radius
   10, padding 14/12, gutter aligned to the panel (drop the −42 pt), split
   heading, strikethrough for done, 22 pt pitch, overflow in SF (VIBE-910..913).
   Update the height formula at `NotchRootView.swift:851` accordingly.
3. **Compact strip** — label 11 pt bold 100 %, trailing alignment with a fixed
   gap to the count, height 30, redraw the sprite pair to Vibe's proportions and
   state colours in Perch's own pixel rows (VIBE-920..922).
4. **Header** — circle badge, 11 bold label / 11 bold mono percentage / 11
   regular reset, red threshold, grey `speaker.*.fill` 13, `gearshape.fill`
   13 (VIBE-901..903, doc 10 §1–2).
4b. **Motion** — `Motion.morph` → `spring(response: 0.25, dampingFraction:
   0.7)`; hover `easeInOut(0.15)` (VIBE-925).
5. **Bottom margin** — 20 pt under the last card in place of the CTA row
   (VIBE-915).
6. **Capture Vibe's remaining states** (needs Screen Recording for the
   terminal host `cmux`), then extend this document (VIBE-940) before touching
   `PermissionAlertView`, `FlashView`, `PeekView`, `QuestionCardView`.
7. Settings title-bar chrome and popup style (VIBE-930) last.

Verification for 1–5: `Perch --render /tmp/x.png [--idle|--phases]` side by
side with the Vibe crops in this document, then a native capture of the local
build once permission exists. Update `PanelPreview` first — it still draws a
tab header the live panel no longer has, so its renders currently over-report
the gap (VIBE-side finding S-2 below).

---

## Not read / not verified

- No Vibe capture exists for: alert, notification card, question card, warning
  card, child-agent attention row, hover-peek, any transition, Detailed layout
  with subagents, a card with open (pending) tasks, a card in amber
  (needs-you) state.
- Vibe font sizes in sections A–E were estimated from 1× JPEG crops at 3× zoom
  and are now **superseded by doc 10** where it has a `[BIN]` value; colours
  from JPEG (±3/255) still stand only where doc 10 has no opacity.
- Doc 07's binary-derived type inventory was re-used (view names) and its
  `fieldmd-named.json` served to pick the views; not otherwise re-verified.
- Vibe website (`vibeisland.app`) was fetched for context only; no screenshot on
  it was used as evidence.

## Side findings (ours)

- **S-1** `PanelPreview.scene`/`phases` draw a header with `activity / stats /
  rank` tabs and a close button that the live `ExpandedView` no longer has
  (`PanelPreview.swift` vs `NotchRootView.swift:868-899`); the offline harness
  is out of date and misleads any visual review.
- **S-2** `expanded-live-r101` shows the Codex trust banner at the top of the
  panel above the session card; doc 07 says Vibe has a `CodexHookTrustBannerView`
  too but its look was never captured — the banner's styling is unverified.
- **S-3** `Theme.swift` header comment says the direction is "monospaced text";
  the same file's type section says Vibe uses system designs. The comment and
  the tokens disagree, and the callers followed the comment.
