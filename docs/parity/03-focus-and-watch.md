# Focus / Do-Not-Disturb awareness & Apple Watch mirroring

Design spec. No feature code yet. Two features, grounded in Perch's existing
interruption pipeline. Both build on machinery that already ships — this is mostly
about naming and extending it, not inventing a new subsystem.

## Where this plugs in (current pipeline)

Everything Perch decides about "how loudly to speak" already funnels through one pure
policy and one call site:

- `apps/mac/Sources/PerchKit/Interruption.swift` — `Scene`, `QuietSettings`,
  `Interruption` (`.full` / `.quiet` / `.none`), and `InterruptionPolicy` with
  `decide`, `notifies`, `playsSound`, `isQuietScene`.
- `apps/mac/Sources/PerchApp/Notch/SceneMonitor.swift` — reads the machine state that
  feeds `Scene`: `isFocusActive`, `isScreenObscured`, `isScreenShared`,
  `frontmostBundleId`.
- `apps/mac/Sources/PerchApp/AppModel.swift` — `announce(_:client:)` (line ~346) is
  "the one place that decides whether something takes the screen"; `notify(...)`
  (~365) and `maybePush(...)` (~381) are the other two consumers.
- `apps/mac/Sources/PerchApp/Notch/SoundPlayer.swift`,
  `.../Notch/Notifications.swift`, `.../Transport/PushNotifier.swift` — the three
  output channels (sound, macOS notification, phone push).

Key finding: **Focus/DND awareness is already ~70% built.** `SceneMonitor.isFocusActive()`
reads the DND assertion file, and `InterruptionPolicy.isQuietScene` already downgrades
`.full` → `.quiet` when `settings.duringFocus && scene.isFocusActive`. `.quiet` already
means exactly "mark it with a dot, no panel, no sound." Feature A is therefore hardening
+ a manual toggle + per-agent focus, not a new pipeline.

---

## Feature A — Focus / Do-Not-Disturb awareness

### A.1 What exists vs. what's missing

| Signal | Today | Gap |
|---|---|---|
| Focus / DND on | `isFocusActive()` reads `~/Library/DoNotDisturb/DB/Assertions.json` | Read-only, no live signal; only refreshed on-demand in `announce()` |
| Screen locked | `com.apple.screenIsLocked` / `Unlocked` distributed notif | ok |
| Screensaver | `com.apple.screensaver.didstart` / `didstop` | ok |
| Display sleep / system sleep | — | not observed at all |
| Screen shared/recorded | `NSScreen.isCaptured` (on-demand) | ok |
| Manual "I'm presenting / heads-down" | — | no user-driven quiet toggle |

### A.2 macOS APIs to add

**Focus status — the honest public API.** There is no public "which Focus mode is on"
API on macOS. Two grounded options, in order of preference:

1. **Keep the assertion-file read** in `SceneMonitor.isFocusActive()` (already there,
   already documented as best-effort) as the baseline. It needs no entitlement and no
   authorization prompt — consistent with Perch never asking for Accessibility.
2. **Add `INFocusStatusCenter` (SiriKit / App Intents, macOS 12+)** as an *optional,
   opt-in* upgrade. `INFocusStatusCenter.default.requestAuthorization` +
   `.focusStatus.isFocused` gives a first-class on/off signal and a
   `focusStatusDidChange`-style push (via `INFocusStatusCenter` delegate), removing the
   need to poll the file. Cost: the entitlement `com.apple.developer.focus-status`, an
   `NSFocusStatusUsageDescription` Info.plist string, and a one-time permission prompt.
   Gives boolean only (not the mode name) — which is all `isQuietScene` needs.

   Design decision: ship #1 as default (zero-prompt, Perch-ethos), expose #2 behind a
   Settings toggle for users who want live, reliable Focus tracking.

**Screen lock / sleep / screensaver.** Extend `SceneMonitor.start()`:

- Keep the two existing `DistributedNotificationCenter` observers.
- Add `NSWorkspace.shared.notificationCenter` observers for
  `screensDidSleepNotification` / `screensDidWakeNotification` (display sleep) and
  `willSleepNotification` / `didWakeNotification` (system sleep). Each sets/clears
  `scene.isScreenObscured`, same field the lock observers already drive. No policy
  change needed — `whenScreenObscured` already covers it.

**Frontmost app** already handled via `NSWorkspace.shared.frontmostApplication`.

### A.3 Quiet / Focus mode — how it gates behavior

Two distinct "quiet" concepts, and the spec keeps them separate:

- **Scene-driven lockdown (exists).** Screen shared/locked/Focus → `isQuietScene` true
  → `decide()` returns `.quiet` for *everything, blocking requests included* (the
  screen-share-on-a-projector case). Leave this exactly as-is.
- **Manual Focus mode (new).** A user-toggled "heads-down" mode that is *lighter* than
  the lockdown: no auto-expand, no sound, a completion dot only — **but a blocking
  approval still earns the panel** (the task's "approvals still included"). This is the
  everyday "let me code, but don't let an agent sit blocked silently" mode.

Implementation shape (no code yet):

- Add `var manualQuiet: Bool` to `QuietSettings` (with the same tolerant
  `decodeIfPresent` default-false pattern the struct already uses, so existing
  `~/.perch/quiet.json` still decodes).
- `InterruptionPolicy.decide` gains one early branch:
  `if settings.manualQuiet && !kind.isBlocking { return .quiet }`. Blocking kinds fall
  through to the existing `kind.isBlocking → .full`, so approvals still open. Sound and
  auto-expand are already downstream of `.full`, so both are suppressed for the muted
  kinds for free.
- Toggle surfaces: the right-click menu on the notch (`NotchController` already routes
  the strip), a `GlobalHotKey` binding, and Settings. Toggling it is a pure
  `QuietSettings.save(...)` write + in-memory update on `AppModel.quiet` — no new
  observers.
- The dot: the notch already draws a completion dot for `.quiet` outcomes (the
  `activityPulse` / idle flank path in `NotchController`), so "subtle completion dot
  only" needs no new view.

Note the `notifies()` path is deliberately independent (it fires when the notch *can't*
be seen). Decision: **manual Focus mode should also gate macOS notifications** for
non-blocking kinds — add the same `!manualQuiet || kind.isBlocking` guard to
`notifies()`, otherwise "heads-down" would still bark completions into Notification
Center. Phone push (`maybePush`) stays governed by `PushDecision` / "away" — being
heads-down at the machine already means not-away, so nothing changes there.

### A.4 Per-agent focus command

Perch already has the outbound half: `TerminalJump.editorURL` builds
`<scheme>://kweli.perch-jump/focus?tty=…` and `TerminalJumper.jump(to:)` /
`SessionNotifier.handle` already focus the terminal that raised a request. What's
missing is an *inbound* trigger to focus a specific agent on demand.

Two grounded channels, reusing existing transport:

1. **A `perch://` URL scheme (new, small).** Register a URL type in the app's
   Info.plist and handle it in `AppDelegate`
   (`application(_:open:)` / `NSAppleEventManager` `getURL`). `perch://focus?session=<id>`
   or `perch://focus?agent=<name>` looks up the session in `AppModel.activity.sessions`
   and calls `TerminalJumper.jump(to: client)`. Lets Raycast/Alfred/Shortcuts/a
   Stream Deck focus "the Codex session" in one keystroke.
2. **A `__focus` line event on the existing `EventServer`.** The loopback line server
   already dispatches `__status`, `__decide`, `__usage` (see `Wire.swift`,
   `AppModel.handle`). Add `Wire.focusEvent = "__focus"` carrying a session id; the
   `perch-hook` CLI (already token-authed against `~/.perch/runtime.json`) can then
   focus an agent from a shell script. Zero new network surface.

### A.5 ASCII — Focus / DND data flow

```
 macOS state sources                     SceneMonitor (refresh + observers)
 ───────────────────                     ─────────────────────────────────
  DistributedNotif                        scene.isScreenObscured  ─┐
   screenIsLocked/Unlocked  ───────────▶                          │
   screensaver did start/stop                                     │
  NSWorkspace (NEW)                                               │
   screens/systemDidSleep/Wake ─────────▶ scene.isScreenObscured  │
  DND assertion file  ────┐                                       │
  INFocusStatusCenter(NEW)├──────────────▶ scene.isFocusActive    ├──▶ Scene
  NSScreen.isCaptured ─────────────────── ▶ scene.isScreenShared  │
  frontmostApplication ──────────────────▶ scene.frontmostBundleId┘
  Manual Focus toggle (NEW) ─────────────▶ QuietSettings.manualQuiet
                                                     │
                                                     ▼
                       InterruptionPolicy.decide / notifies / playsSound
                                                     │
              ┌──────────────────┬───────────────────┬─────────────────┐
              ▼                  ▼                    ▼                 ▼
         .full → panel      .quiet → dot only    SoundPlayer      SessionNotifier
         (blocking always)  (no sound/expand)    (only if .full)  (only if !quiet)
                                                     │
                    per-agent focus (NEW): perch://focus?session=…
                    or EventServer __focus  ──────▶ TerminalJumper.jump(to:)
```

---

## Feature B — Apple Watch mirroring

### B.1 Honest feasibility verdict

**There is no direct Mac → Apple Watch push.** A Watch pairs with an *iPhone*, not a
Mac. A macOS app has no API to reach a Watch it isn't paired with, and cannot host a
watchOS target of its own — watchOS apps ship only inside an iOS app bundle. So any
"Watch mirroring" from a Mac app must route through a phone. Two real paths:

**Path 1 — Reuse the existing ntfy pipeline → iPhone → automatic Watch mirroring
(RECOMMENDED).** Perch already POSTs to ntfy (`PushNotifier.swift`,
`PushSettings.swift`, gated by `PushDecision`). The ntfy iOS app receives that as a
normal iOS notification. **iOS already mirrors notifications to a paired Watch
automatically** when the iPhone is locked / on the wrist — "Apple Watch mirroring" is,
for a notification-only feature, essentially *already shipping transitively today*. The
Watch shows the agent-waiting / completion alert; tapping it opens ntfy on the phone.
Replies/approvals cannot happen there anyway, which matches the requirement exactly
(Watch is notification-only; answering stays on the Mac).

Work required is small and stays on-ethos (zero infrastructure, free):

- Make `pushedKinds` cover the Watch-worthy set. Today it defaults to the two blocking
  kinds (`.approvalNeeded`, `.questionAsked`); add `.taskComplete` as an opt-in so
  "done" reaches the wrist, still behind the `isAway` gate in `maybePush`.
- Enrich the ntfy request in `PushNotifier.send` with ntfy's own headers so the Watch
  card reads well: `Priority` (high for blocking, default for completion → drives the
  haptic), `Tags` (emoji shown as the icon: e.g. `question`, `white_check_mark`),
  and `Title` already set. No JSON envelope, no new dependency.
- Optionally a `Click` header carrying a `perch://focus?session=…` deep link (feature
  A.4) so tapping the Watch/phone card can, once back at the Mac, focus the agent.

**Path 2 — Dedicated iOS + WatchKit companion app with APNs (NOT recommended).** A
native companion could show complications, custom haptics, and a glanceable
agent-status face. But it requires: an Apple Developer account, an APNs certificate, a
**server that holds device tokens and sends the push** (Perch has no server — the whole
push design is "without a server"), an iOS app, and a watchOS target. This contradicts
the roadmap's stated ethos ("Zero infrastructure, which is the Perch way",
`docs/ROADMAP.md` P3) and buys little for a notification-only feature. Document it as a
known option, do not build it.

**Verdict:** ship Path 1. It is already 90% there via the existing ntfy → iPhone →
system Watch mirroring; the remaining work is three header/settings tweaks, no new Mac →
Watch code, and it honors "Watch is notification-only, replies stay on the Mac" by
construction.

### B.2 ASCII — Watch mirroring path

```
  Mac (Perch)                         Cloud            iPhone              Watch
  ───────────                         ─────            ──────              ─────
  agent blocks / finishes
        │
        ▼
  AppModel.maybePush ──(isAway? dedup?)──▶ guard
        │  yes
        ▼
  PushNotifier.send  HTTPS POST
    Title / Priority / Tags ───────────▶ ntfy.sh ─────▶ ntfy iOS app
    (RECOMMENDED PATH 1)               (or self-host)        │
                                                             │ iOS Notification
                                                             │ Mirroring (automatic,
                                                             ▼ phone locked/on wrist)
                                                       ┌─────────────────────┐
                                                       │  Watch shows alert  │
                                                       │  (notification-only)│
                                                       └─────────────────────┘
                                                             │ tap
                                                             ▼
                                             opens ntfy on phone; answering the
                                             agent still happens back on the Mac
                                             (optional Click: perch://focus?session=…)

  ─────────────────────────────────────────────────────────────────────────────
  PATH 2 (NOT recommended): Perch ─▶ [new push server + APNs] ─▶ iOS companion ─▶
  WatchKit app. Requires infra Perch deliberately does not have. Documented, not built.
```

### B.3 Files touched (Path 1)

- `apps/mac/Sources/PerchKit/PushSettings.swift` — default `pushedKinds` gains an
  opt-in `.taskComplete`; a Watch-priority/tags mapping could live here as pure data.
- `apps/mac/Sources/PerchApp/Transport/PushNotifier.swift` — add `Priority` / `Tags`
  (and optional `Click`) headers.
- `apps/mac/Sources/PerchApp/AppModel.swift` — `maybePush` already the only caller; no
  structural change.
- No new iOS/watchOS target.

---

## Summary of decisions

- Focus/DND is mostly built; add `NSWorkspace` sleep/wake observers, an optional
  `INFocusStatusCenter` upgrade, and a **manual Focus mode** (`QuietSettings.manualQuiet`)
  that mutes non-blocking kinds to a dot while approvals still open.
- Gating stays inside the existing pure `InterruptionPolicy` — one new branch in
  `decide()` and one in `notifies()`; sound/auto-expand suppression comes for free.
- Per-agent focus via a new `perch://focus` URL scheme and/or a `Wire.focusEvent` on the
  existing loopback `EventServer`, reusing `TerminalJumper.jump(to:)`.
- Apple Watch: no direct Mac → Watch path exists. Reuse ntfy → iPhone → automatic system
  Watch mirroring (already transitively working); native WatchKit companion is possible
  but off-ethos and not recommended.
