# 11 — Vibe Island 1.0.44: `PixelStatusIcon`, read from the binary (2026-08-18)

**Why.** The island's pet had been reconstructed from 1× captures, then taken
from the SVG on vibeisland.app. Neither animates. This document holds what the
app itself draws, read from the arm64 slice (`otool -tvV`, symbolic decode of
the `Canvas` closures with a small emulator; scripts under `/tmp/vi` during the
session, method as in doc 10). Perch's `VibePet` (`NotchRootView.swift`) is a
port of it.

**Where.** `PixelStatusIcon.body` 0x1007de8d0 → shared body 0x1007e0040;
draw closure 0x1007ddbb0–0x1007de8d0; appearance switch 0x1007e0434; helpers:
feet 0x1007e0d10, `?` mark 0x1007e14fc, X mark 0x1007e18a0, working ring
0x1007e1c1c, small mark 0x1007e1140. Init at 0x1007e0868 creates the timer.

## Contract

| Item | Value | Ref |
|---|---|---|
| Grid | 13 × 8 cells, `p = min(w/13, h·0.125)`, translated by `((w−13p)/2, (h−8p)/2)` | `[BIN 0x1007ddca8–0x1007ddcdc]` |
| Cell rect | `(x·p + 0.15, y·p + 0.15, p − 0.3, p − 0.3)` | `[BIN 0x1007ddd6c–0x1007dddac]` |
| Timer | `Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()`, `@State phase: Int` from 0 | `[BIN 0x1007e0940–0x1007e09b0]` |
| Pet | antennae (2,2) (5,2); rows 3 and 4 on x 1…6; eyes black on row 3 at (2,3) (5,3); feet row 5 | `[BIN 0x1007dddac–0x1007de3ac]` |
| Feet frames | 0: 2 3 5 6 · 1: 1 3 5 6 · 3: 2 3 4 6; walk = `phase % 4` (mode 1), `phase % 3 == 1 ? 1 : 0` (mode 3), `(phase/3) odd ? 1 : 0` (mode 2), static (mode 0) | `[BIN 0x1007e0d80–0x1007e1008]` |
| Idle extra | cursor: cells (10,y) (11,y) for y 2…5, drawn when `phase % 8 < 5` | `[BIN 0x1007de470–0x1007de55c]` |
| Working extra | ring `[(10,2),(11,2),(12,3),(12,4),(11,5),(10,5),(9,4),(9,3)]` at 0x100f06e68; cell `ring[(phase+i) % 8]` with opacity `1 − 0.12·i`, i 0…7; solid 2×2 at (10–11, 3–4) | `[BIN 0x1007e1c94–0x1007e1ee0]` |
| Request extra | `?`: (10,1)(11,1)(9,2)(12,2)(12,3)(11,4), dot (10,6)(11,6) when `phase % 8 ≤ 3` | `[BIN 0x1007e15b4–0x1007e183c]` |
| Ended extra | X: (9,2)(12,2)(10,3)(11,3)(10,4)(11,4)(9,5)(12,5) | `[BIN 0x1007e1958–0x1007e1bb8]` |
| Colours (base / bright) | idle #22C55E / #4ADE80 · working #3B82F6 / #60A5FA · alert #F97316 / #FB923C · purple #A855F7 / #BF85FC · grey 0.45 / 0.6 | `[BIN 0x1007e0bbc–0x1007e0d10, globals 0x100f84f80…]` |
| Status → flags | 0 idle: static · 1,3 blue: feet mode 1, eye mode 1 · 2 purple: eye mode 1 · 4 orange: feet mode 3 + tone swap while `phase ≤ 3` · 5 orange: feet mode 2 | `[BIN 0x1007e0434–0x1007e0868]` |

## Not resolved

- The exact eye-glance cells for eye modes 0/1 (a `%16` cycle and a `& 4` toggle
  are read; Perch glances to (3,3)/(6,3) on the toggle).
- Which of statuses 5/6/7 carries grey vs purple, and the status-6 "comet"
  (table at 0x100f06f38 with four fading dots at x = 1p, 0.75p, 0.5p, 0.25p).
- Which of the two tones each body row uses (the site paints antennae bright and
  the body base; Perch follows the site).
