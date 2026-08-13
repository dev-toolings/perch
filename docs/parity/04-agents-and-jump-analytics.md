# 04 — Broadened host detection & jump analytics

Design spec. No feature code yet. Two originally-designed features grounded in Perch's own
jump and stats code:

- **A. Broadened agent / IDE / terminal detection & jump** — a table-driven host registry so
  the detection matrix is extensible and adding a host is one row.
- **B. Jump analytics** — count and categorise jumps by trigger (auto / click / keyboard)
  plus a total counter, surfaced in the Stats tab.

---

## 1. How a jump works today (grounding)

Two halves, split across the SPM targets on purpose:

| Concern | Where | Nature |
| --- | --- | --- |
| Decide *where* a click lands | `apps/mac/Sources/PerchKit/TerminalJump.swift` | Pure, `Sendable`, unit-testable without AppleEvents |
| Execute the plan | `apps/mac/Sources/PerchApp/Jump/TerminalJumper.swift` | Impure: `NSWorkspace`, `osascript`, remote-control CLIs |

### 1.1 The decision (`PerchKit/TerminalJump.swift`)

`ClientInfo` (`PerchKit/Wire.swift:171`) is the captured identity of a session's host, read
from the hook's own environment (`ClientInfo.fromEnvironment`): `terminal` (`TERM_PROGRAM`),
`session` (`ITERM_SESSION_ID` / `WEZTERM_PANE` / `KITTY_WINDOW_ID` / cmux panel id), `tty`,
`tmuxPane`, `launcher` (`__CFBundleIdentifier`).

`TerminalJump.plan(for:)` turns that into a `JumpPlan { target: JumpTarget, tmuxPane }`.
Today the mapping is spread across **three parallel dictionaries plus one switch**:

- `bundleIds: [String: String]` — `TERM_PROGRAM` value → bundle id (~20 entries).
- `displayNames: [String: String]` — bundle id → UI name (~14 entries).
- `editorSchemes: [String: String]` — bundle id → URL scheme (VS Code / Cursor / Windsurf).
- `plan(for:)` — a `switch bundleId` with one `case` per precise strategy, falling through
  to `.activate(bundleId)` (window-level) for everything else.

`JumpTarget` (the strategy result) has these cases:

```
.iTerm(bundleId, session)          → osascript, lands on the exact split
.appleTerminal(bundleId, tty)      → osascript, lands on the exact tab
.editorURI(bundleId, scheme, tty)  → NSWorkspace.open(<scheme>://kweli.perch-jump/focus?tty=)
.deepLink(bundleId, url)           → NSWorkspace.open (Codex: codex://threads/<id>)
.remoteControl(bundleId, exe, args)→ run the host's own CLI (kitty / wezterm / cmux)
.activate(bundleId)                → bring app forward, window-level only
.unavailable                       → nothing captured / unknown host
```

### 1.2 The execution (`PerchApp/Jump/TerminalJumper.swift`)

`TerminalJumper.jump(to client:)` is `static`, best-effort, and **silent on failure** by
design (a missed jump must leave the panel untouched, never raise). It logs one trace line
(`PerchLog.info("jump: …")`), selects the tmux pane first if present, then `switch plan.target`
to `activate` + (`osascript` | `NSWorkspace.open` | remote-control CLI). Off-main-actor via
`Task.detached` so an unresponsive host cannot freeze the panel.

### 1.3 The three trigger paths today

`TerminalJumper.jump(to:)` has exactly three call sites — and **none of them tells the jumper
how it was triggered**, which is precisely what Feature B needs:

| Call site | Context | Natural trigger |
| --- | --- | --- |
| `AppModel.swift:205` | `SessionSwitcher` `.jump(index)` outcome — the keyboard switcher | **keyboard** |
| `Notch/Notifications.swift:80` | `SessionNotifier.handle` — a system notification was clicked | **click** |
| `UI/NotchRootView.swift:860` | `SessionCardView(onJump:)` — a click on a card in the panel | **click** |

There is **no auto/silent jump today**; `.auto` is designed in but wired only when an
automatic-jump feature lands (e.g. "jump to the session that just needed input"). The recent
"silent jump leaves a trace" commit is about the log line, not an auto-jump.

### 1.4 Persistence patterns already in the codebase

Two, and we mirror the right one:

- **Small Codable state** → JSON under `~/.perch/`. `Preferences` (`PerchKit/Preferences.swift:217`)
  is `Codable`, `load(from:)` / `save(to:)` via `JSONEncoder`, atomic write to
  `~/.perch/preferences.json`. `AdmissionPolicy` follows the same shape.
- **Heavy, queryable data** → SQLite under Application Support. `UsageStore`
  (`PerchKit/UsageStore.swift`) is a SQLite index at
  `~/Library/Application Support/Perch/usage.sqlite`, read off-main-actor.

Jump analytics is a handful of monotonic counters, so it mirrors **Preferences**, not
UsageStore.

---

## 2. Feature A — table-driven host registry

### 2.1 Goal

Collapse the three dictionaries + switch into **one registry of rows**, keyed by bundle id,
where each row fully declares how to jump into that host. Adding a host is one appended row.
Broaden the matrix to cover common terminals and the JetBrains / VS Code / Kiro IDE family.

### 2.2 Data model (in `PerchKit/TerminalJump.swift`)

```swift
public enum HostKind: Sendable { case terminal, ide, app }   // for grouping + analytics

/// How to land precisely inside a host, given the handles ClientInfo captured.
/// Each case is a *builder*: it reads ClientInfo and returns a JumpTarget, or nil when the
/// handle it needs is absent (→ registry falls back to .activate).
public enum JumpStrategy: Sendable {
    case activate                              // window-level only (Ghostty, Warp, JetBrains, Kiro…)
    case appleScript(AppleScriptHandle)        // .iTermSession | .terminalTTY
    case remoteControl(exe: String, args: (ClientInfo) -> [String]?)   // kitty, wezterm, cmux
    case editorURI(scheme: String)             // vscode / cursor / windsurf, needs tty + extension
    case deepLink(url: (ClientInfo) -> String?)// codex://threads/<id>
    case accessibility(AXTabSelector)          // reserved: AX-driven tab/split select (JetBrains…)
}

/// One row = one host. This is the whole detection matrix.
public struct HostDescriptor: Sendable {
    public let bundleId: String                // exact id, or a family prefix (see match())
    public let displayName: String             // replaces `displayNames`
    public let kind: HostKind
    public let termPrograms: [String]          // TERM_PROGRAM values that resolve here (replaces `bundleIds`)
    public let strategy: JumpStrategy
    public var isPrefix: Bool = false           // true for family ids like "com.jetbrains."
}
```

`(ClientInfo) -> …?` closures move the per-host detail (which env handle, how to shape the
args/url) *into the row*, so `plan(for:)` no longer needs a `case` per host. The closures are
pure, keeping the target testable exactly as today.

### 2.3 The registry (single source of truth)

```swift
public static let hosts: [HostDescriptor] = [
    // ── terminals ───────────────────────────────────────────────────────────────
    .init("com.googlecode.iterm2", "iTerm",   .terminal, ["iTerm.app"],        .appleScript(.iTermSession)),
    .init("com.apple.Terminal",    "Terminal",.terminal, ["Apple_Terminal"],   .appleScript(.terminalTTY)),
    .init("com.mitchellh.ghostty", "Ghostty", .terminal, ["ghostty","Ghostty"],.activate),
    .init("dev.warp.Warp-Stable",  "Warp",    .terminal, ["WarpTerminal"],     .activate),
    .init("net.kovidgoyal.kitty",  "kitty",   .terminal, ["kitty"],
          .remoteControl(exe: "kitty", args: { c in c.session.map { ["@","focus-window","--match","id:\($0)"] } })),
    .init("com.github.wez.wezterm","WezTerm", .terminal, ["WezTerm"],
          .remoteControl(exe: "wezterm", args: { c in c.session.map { ["cli","activate-pane","--pane-id",$0] } })),
    .init("com.cmuxterm.app",      "cmux",    .terminal, ["cmux"],
          .remoteControl(exe: "cmux", args: { c in c.session.map { ["focus-panel","--panel",$0] } })),
    // Alacritty / Hyper / tabby / rio keep their TERM_PROGRAM rows with .activate (window-level).

    // ── IDEs (editor URI where the Perch extension exists, else window-level) ────
    .init("com.microsoft.VSCode",           "VS Code",          .ide, ["vscode"],  .editorURI(scheme: "vscode")),
    .init("com.microsoft.VSCodeInsiders",   "VS Code Insiders", .ide, [],          .editorURI(scheme: "vscode-insiders")),
    .init("com.todesktop.230313mzl4w4u92",  "Cursor",           .ide, ["cursor"],  .editorURI(scheme: "cursor")),
    .init("com.exafunction.windsurf",       "Windsurf",         .ide, ["windsurf"],.editorURI(scheme: "windsurf")),
    .init("dev.zed.Zed",                    "Zed",              .ide, ["zed","Zed"],.activate),
    .init("dev.kiro.desktop",               "Kiro",             .ide, [],          .activate),
    .init("com.jetbrains.",                 "JetBrains",        .ide, [],           .activate, isPrefix: true),
    // ^ one prefix row covers the whole family: com.jetbrains.intellij / .pycharm / .goland / …

    // ── apps that are not terminals but own a thread URL ─────────────────────────
    .init("com.openai.codex", "Codex app", .app, ["Codex Desktop"],
          .deepLink(url: { c in c.session.map { "codex://threads/\($0)" } })),
]
```

`.activate` for JetBrains / Kiro / Warp / Ghostty is honest window-level today; upgrading any
of them to precise selection later means swapping that one field to `.accessibility(…)` or
`.remoteControl(…)` — no other code moves.

### 2.4 Dispatch: registry → strategy

`plan(for:)` becomes a lookup + a strategy build, no per-host switch:

```
ClientInfo
   │
   ├─ resolve bundle id:
   │     terminal(TERM_PROGRAM) ─▶ hosts.first { $0.termPrograms.contains(terminal) }
   │     else launcher(bundleId) ─▶ match(launcher)          // GUI apps set no TERM_PROGRAM
   │
   └─ match(bundleId): exact row first, then prefix rows (isPrefix, longest wins)
```

```
                          ┌──────────────────────────────────────────────┐
   ClientInfo             │            HostRegistry (hosts[])             │
  ┌───────────┐  bundleId │  bundleId | displayName | kind | strategy     │
  │ terminal  ├──────────▶│  ---------┼-------------┼------┼-------------- │
  │ session   │           │  iterm2   | iTerm       | term | appleScript  │─┐
  │ tty       │           │  Terminal | Terminal    | term | appleScript  │ │
  │ tmuxPane  │           │  ghostty  | Ghostty     | term | activate     │ │
  │ launcher  │           │  kitty    | kitty       | term | remoteCtrl   │ │
  └───────────┘           │  wezterm  | WezTerm     | term | remoteCtrl   │ │
                          │  cmux     | cmux        | term | remoteCtrl   │ │
                          │  vscode   | VS Code     | ide  | editorURI    │ │
                          │  cursor   | Cursor      | ide  | editorURI    │ │
                          │  windsurf | Windsurf    | ide  | editorURI    │ │
                          │  kiro     | Kiro        | ide  | activate     │ │
                          │  jetbrains.| JetBrains  | ide  | activate  [P]│ │
                          │  codex    | Codex app   | app  | deepLink     │ │
                          └──────────────────────────────────────────────┘ │
                                          │ selected descriptor             │
                                          ▼                                 │
                       ┌───────────────── strategy.buildTarget(client) ─────┘
                       │
        ┌──────────────┼───────────────┬──────────────┬───────────────┐
        ▼              ▼               ▼              ▼               ▼
   appleScript     remoteControl    editorURI      deepLink        activate
   (.iTerm /       (kitty/wezterm/  (vscode/cursor/ (codex://…)     (window-level:
    .appleTerminal) cmux CLI)        windsurf URI)                   Ghostty/Warp/
        │              │               │              │              JetBrains/Kiro)
        └──────────────┴───────────────┴──────────────┴───────────────┘
                                   │  builder returned nil? (handle absent)
                                   ▼
                            fall back to .activate(bundleId)
                                   │
                                   ▼
                       JumpPlan { target, tmuxPane }  ──▶  TerminalJumper.jump
```

`[P]` = prefix row. `JumpTarget`, `JumpPlan`, `summary`, `isPossible`, `editorURL(for:)`,
`script(for:)` and the executor in `TerminalJumper.swift` are **unchanged** — the registry
only changes how a `JumpTarget` is *chosen*, not how it is run.

### 2.5 Adding a new host = one row

```swift
.init("com.newco.editor", "NewCo", .ide, ["newco"], .editorURI(scheme: "newco")),
```

No touch to `displayNames`, `editorSchemes`, or a switch — those are gone, folded into the row.

---

## 3. Feature B — jump analytics

### 3.1 Trigger taxonomy

```swift
public enum JumpTrigger: String, Codable, Sendable, CaseIterable {
    case auto        // future automatic/silent jump (no current call site)
    case click       // a card click or a notification click
    case keyboard    // the SessionSwitcher shortcut
}
```

### 3.2 Counters + persistence (`PerchKit/JumpStats.swift`, new)

Mirrors the `Preferences` pattern exactly — a `Codable` struct, JSON, atomic write under
`~/.perch/`:

```swift
public struct JumpStats: Codable, Sendable, Equatable {
    public var auto = 0
    public var click = 0
    public var keyboard = 0
    /// Jumps whose host descriptor was `.terminal` — the "total terminal-jumps" figure.
    public var terminalJumps = 0

    /// The prompt's requested total: every jump, regardless of trigger.
    public var total: Int { auto + click + keyboard }

    public mutating func record(_ trigger: JumpTrigger, hostKind: HostKind?) {
        switch trigger {
        case .auto:     auto += 1
        case .click:    click += 1
        case .keyboard: keyboard += 1
        }
        if hostKind == .terminal { terminalJumps += 1 }
    }

    public static var defaultURL: URL {                       // ~/.perch/jump-stats.json
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".perch/jump-stats.json")
    }
    public static func load(from url: URL = defaultURL) -> JumpStats { /* JSONDecoder, else JumpStats() */ }
    public func save(to url: URL = defaultURL) { /* createDirectory + JSONEncoder atomic write */ }
}
```

Only three stored trigger counters + a terminal counter; `total` is computed so it can never
drift from its parts. Counters are monotonic (all-time), matching how "all time" already reads
in the Stats tab.

### 3.3 Recording point

A jump is recorded in exactly one place — the single executor — so every trigger path is
counted once and no call site can forget to. `TerminalJumper.jump` gains a trigger parameter:

```swift
static func jump(to client: ClientInfo?, trigger: JumpTrigger = .click) {
    let plan = TerminalJump.plan(for: client)
    PerchLog.info("jump: \(plan.summary) target=\(plan.target) via=\(trigger.rawValue)")
    guard plan.isPossible else { return }              // an unavailable jump is NOT counted
    JumpStatsRecorder.shared.record(trigger, hostKind: TerminalJump.hostKind(for: client))
    … existing execution …
}
```

`JumpStatsRecorder` (a tiny `@MainActor` box, or a method on `AppModel`) owns the loaded
`JumpStats`, mutates it, and `save()`s — debounced/coalesced the same way preferences are, so
a burst of jumps is one write. Only *possible* jumps are counted, matching the log's own
`guard plan.isPossible`.

### 3.4 Call-site changes (three, one line each)

```
AppModel.swift:205         TerminalJumper.jump(to: sessions[index].client, trigger: .keyboard)
Notch/Notifications.swift  TerminalJumper.jump(to: client, trigger: .click)          // :80
UI/NotchRootView.swift     onJump: { TerminalJumper.jump(to: session.client, trigger: .click) }  // :860
```

The default of `.click` keeps any future call correct-by-default for the common case.

### 3.5 Where it shows in `StatsView`

`StatsView` (`PerchApp/UI/StatsView.swift`) already composes stacked sections
(`summary` → `chart` → `models`) out of `StatTile`s and mono rows. Jump analytics slots in as
a new section below `models`, agent-independent (jumps are not per-agent), reusing the existing
`StatTile` component so it reads as the same screen:

```
┌ Jumps ─────────────────────────────────────────────┐   (Theme.label header, like "Tokens")
│  ┌────────┐ ┌────────┐ ┌────────┐                   │
│  │ auto   │ │ click  │ │ key...│   ← three StatTiles (Theme.active/.info/.warning tints)
│  │   3    │ │  128   │ │   41   │                    │
│  │ jumps  │ │ jumps  │ │ jumps  │                    │
│  └────────┘ └────────┘ └────────┘                   │
│  total 172 jumps · 140 to a terminal                │   ← one mono line (Theme.mono(9), tertiary)
└─────────────────────────────────────────────────────┘
```

Data reaches the view the same way tokens do: `UsageModel` (`PerchApp/Usage/UsageModel.swift`,
`@Observable`) gains `private(set) var jumps = JumpStats()` refreshed on the panel's existing
`refresh()`/reload path (or read on appear — jumps change rarely). `StatsView` renders a new
`private var jumpsSection` guarded by `usage.jumps.total > 0`, so a machine that has never
jumped shows nothing — the same "a tab onto an empty screen is worse than no tab" rule the
Stats tab already follows.

---

## 4. Files touched (implementation checklist, for later)

| File | Change |
| --- | --- |
| `PerchKit/TerminalJump.swift` | Add `HostKind`, `JumpStrategy`, `HostDescriptor`, `hosts[]` registry, `match(bundleId:)` (exact→prefix), `hostKind(for:)`; rewrite `plan(for:)` as lookup+build; delete `displayNames` / `editorSchemes` / the switch (folded into rows); broaden matrix (Warp, VS Code Insiders, Kiro, JetBrains prefix) |
| `PerchKit/JumpStats.swift` | **New.** `JumpStats` Codable + `JumpTrigger`, load/save to `~/.perch/jump-stats.json` |
| `PerchApp/Jump/TerminalJumper.swift` | `jump(to:trigger:)`; record on the possible-jump path |
| `PerchApp/AppModel.swift` | `:205` pass `.keyboard`; host the `JumpStats` recorder + debounced save |
| `PerchApp/Notch/Notifications.swift` | `:80` pass `.click` |
| `PerchApp/UI/NotchRootView.swift` | `:860` pass `.click` |
| `PerchApp/Usage/UsageModel.swift` | Expose `jumps: JumpStats`, load on refresh |
| `PerchApp/UI/StatsView.swift` | Add `jumpsSection` (reuse `StatTile`), guarded by `total > 0` |

### Non-goals / assumptions

- `.auto` and `.accessibility` are modelled but not wired — they exist so the future
  auto-jump and AX tab-selection features are one row / one field, not a refactor.
- Counters are all-time monotonic (no per-day buckets); if per-day jump history is later
  wanted, it graduates to a `UsageStore` table, not this JSON file.
- JetBrains precise tab/split selection is out of scope; the family lands window-level via one
  prefix row until an `.accessibility` selector is designed.
