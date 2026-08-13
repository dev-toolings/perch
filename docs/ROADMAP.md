# Perch roadmap — breadth where it is cheap, soul kept

Vibe Island (the category reference) wins on breadth: ~14 agent integrations, push
notifications, SSH remotes, commercial polish. Perch keeps what it alone has — local,
free, the public leaderboard, the pixel-art creatures — and takes breadth where it
costs little. Ordered by leverage over effort.

## P3 — Phone push without a server (S)

ntfy.sh: a private topic, one HTTPS POST, a free iOS app. Zero infrastructure, which
is the Perch way. A `NotificationRouter` posts when an agent is blocked on a person
**and** nobody is at the screen (locked, or idle past a threshold — `SceneMonitor`
already knows). Nothing is ever sent while you are in front of the machine.

*Done when: Claude asks a question while you are at the coffee machine → the phone
buzzes in under 5 s.*

## P1 — Agent breadth (M)

The design lesson from the category: **an agent is a config, not a module** — one
generic installer per hook-file shape, and a new tool is a spec entry.

1. Extract a generic hook installer: a `HookSpec` (settings path, JSON shape, events)
   per tool. The settings.json `hooks` schema is shared by Cursor CLI, Copilot CLI
   and most forks.
2. opencode first — its usage is already read (`OpencodeUsage.swift`), but its live
   sessions had no agent case of their own. Cheapest win: an `.opencode` agent, a
   sprite, its hook spec.
3. Then Cursor, Copilot, Amp through the generic spec. Gemini is in the enum but has
   no hooks — complete it on the way.

*Done when: a Cursor session shows as a card with project, status and jump, without a
single new Swift file written specifically for Cursor.*

## P2 — Multi-provider quotas (M)

Today Claude + Codex + opencode, each hand-wired. Their lesson: a `UsageProvider`
protocol + refresh planner + rollup. Migrate the three, then add Gemini and one more
(Kimi has a simple API). The resting bar already draws two quotas; make it N.

*Done when: adding a provider is one file conforming to the protocol, zero UI edits.*

## P4 — First-class SSH remotes (L)

`perch-remote-hook.sh` and `remote.sh` already exist — the base is there in script
form. The gap is UX: a host list in Settings, one-click remote hook install, a
"remote" badge on cards. After P1–P3: this serves power users, P1 serves everyone.

## P5 — Distribution & robustness (ongoing)

- Developer ID + notarisation (today "out of scope v1" in `make-app.sh` — the first
  wall for any outside user).
- MetricKit for crashes/hangs, written into `~/.perch` — diagnostics without Sentry,
  faithful to zero telemetry.
- Their jump-planner "shadow mode" is elegant but oversized here; the pure
  `TerminalJump` tests carry that weight.

## Quick wins (between phases)

- Sprite animation on hover only: ~40 MB resident instead of ~260 (purgeable, but
  Activity Monitor counts it).
- Confetti when a plan completes.
- Sound packs: `SoundSettings` already takes custom files; packs are mostly tidying.

## Sequence

**P3 → P1.1+1.2 → P2 → P1.3 → P5 (signing) → P4.** P3 first because three days buys a
capability people feel every day, and it lets the generic-installer design mature.
