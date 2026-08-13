# Approval routing — scoped, per-agent, owner-aware

Design spec. No feature code lands in the app from this document; it defines the types and
the seams they plug into so the implementation is a follow-up.

## 1. What Perch already models

The approval path exists end to end today — it is just binary and Claude-shaped.

- **Transport.** `perch-hook` sends one `PerchRequest` per line over a socket
  (`PerchKit/Wire.swift`). A request that needs a decision sets `wantsDecision` and the hook
  **blocks on the socket** until the app answers. The answer is a `PerchResponse`, rendered
  to hook stdout as a `HookOutput` in Claude Code's `hookSpecificOutput` schema. This blocked
  socket *is* the current routing mechanism: resolving a `PendingPermission` resumes a
  continuation, the continuation returns the `PerchResponse`, and the hook prints it. There
  is no separate "send the answer back to the owner" step — the owner is whoever is blocked on
  the other end of that socket.
- **Queue.** `PermissionBroker` (`PerchApp/Permissions/PermissionBroker.swift`) holds
  `PendingPermission`s oldest-first, dedups copies by `duplicateKey`, backstops with a
  ~24h timeout that resolves to `.ask`, and announces every exit through `onResolved`.
- **Request kinds.** `RequestKind.of` (`PerchKit/Questions.swift`) splits a request into
  `.permission`, `.question(AskUserQuestionRequest)`, or `.plan(PlanApprovalRequest)`.
- **The three verbs.** `PermissionDecision` is `allow | deny | ask`. `ask` means "hand it back
  to the agent's own terminal prompt" — this is already the *native-defer* primitive.
- **The one persisted scope.** `PermissionAlertView` offers `Allow` (allow, no rule) and, when
  a rule can be expressed, `Always` (allow + `RememberedRule` at `.localSettings`). Persistence
  rides Claude Code's own `updatedPermissions.addRules` so Perch never races the settings file.
  Plan approval already uses a *session*-scoped `setMode` (`HookOutput.encode`).
- **A weak "am I viewing it".** `InterruptionPolicy` (`PerchKit/Interruption.swift`) compares
  `host` against `Scene.frontmostBundleId` (`smartSuppression`) to decide whether to open the
  panel. This is the seed of ownership, used only for panel suppression today.
- **Agents.** `Agent` (`Wire.swift`) is `claude | codex | gemini | opencode | unknown`; every
  request may carry `client: ClientInfo` (terminal bundle, session id, tmux pane, tty,
  launcher). Codex CLI speaks the same hook vocabulary as Claude. Codex **Desktop** does not
  run hooks at all — `CodexSessions` reads its rollouts off disk, so it can be *observed* but
  never *answered*. `CodexTrust` reads (never writes) `~/.codex/config.toml`.

### The gap

1. **Scope.** Only two points on the spectrum are reachable: *this turn* (`allow`, no rule) and
   *always* (`addRules` at `localSettings`). The middle scope — *this conversation* — already
   exists as `RememberedRule.Destination.session` and as the plan card's `setMode(session)`, but
   no approval UI exposes it, and there is no deny-side equivalent (`never this conversation`).
2. **Per-agent routing.** Everything assumes a blocked hook socket. There is no adapter seam:
   Codex's approval-*mode* semantics, Cursor's marker-file channel, and Codex Desktop's
   no-channel observe-only case all have to be answered the same single way today.
3. **Owner / viewing.** "Who owns this approval" is implicit (the blocked socket) and "am I
   looking at it" is a bundle-id guess used only to suppress the panel. Neither lets Perch
   *step back* when the user answers the same prompt in the terminal — a double-handle risk the
   moment a second channel (marker files, native defer) exists.

## 2. The design

### 2.1 Scope model

A resolution is a **verb** crossed with a **scope**. Scope is the axis the current UI is
missing; the verb axis (`allow`/`deny`/defer) already exists as `PermissionDecision`.

```swift
// PerchKit/Approval.swift (new)

/// How far a grant or refusal reaches.
public enum ApprovalScope: String, Codable, Sendable, CaseIterable {
    /// "Allow just this turn" / "bypass this turn". One-shot, writes no rule.
    case turn
    /// "Allow for this conversation." Lives as long as the session id does.
    case conversation
    /// "Allow for all sites / always." Persisted where the agent keeps its rules.
    case always

    /// Where a *remembered* verb at this scope should be persisted, in the vocabulary
    /// `RememberedRule.Destination` already speaks. `turn` persists nothing.
    public var destination: RememberedRule.Destination? {
        switch self {
        case .turn:         return nil
        case .conversation: return .session        // already honoured by HookOutput.setMode
        case .always:       return .localSettings  // today's "Always"
        }
    }
}

public enum ApprovalVerb: String, Codable, Sendable {
    case allow
    case deny
    /// Hand it back to the agent's own prompt. Scope is ignored (defer is always one-shot).
    case defer_ = "defer"
}

public struct ApprovalResolution: Sendable, Equatable {
    public var verb: ApprovalVerb
    public var scope: ApprovalScope
}
```

Mapping to the wire is mechanical and reuses everything in `Wire.swift`:

| verb / scope         | `PermissionDecision` | rule / mode carried                                   |
|----------------------|----------------------|-------------------------------------------------------|
| allow · turn         | `.allow`             | none                                                  |
| allow · conversation | `.allow`             | `RememberedRule(dest: .session)` (or `setMode` on plan)|
| allow · always       | `.allow`             | `RememberedRule(dest: .localSettings)` — today's Always|
| deny · turn          | `.deny`              | none                                                  |
| deny · conversation  | `.deny`              | deny-rule at `.session`                               |
| deny · always        | `.deny`              | deny-rule at `.localSettings`                         |
| defer · *            | `.ask`               | none (hook stays silent, agent prompts)               |

`RememberedRule` needs a `behavior` (allow/deny) to express the deny-side rules — a one-field
addition, since `HookOutput` already writes `behavior` inside `addRules`.

### 2.2 Per-agent adapter protocol

The verb+scope is *what the user decided*; the adapter is *how that reaches this particular
agent*. The router picks an adapter by `Agent`, the adapter turns a resolution into a
`RoutedDecision`, and the broker performs it.

```swift
// PerchApp/Permissions/ApprovalAdapter.swift (new)

/// What actually happens once a scope is chosen — the four channels Perch can answer over.
enum RoutedDecision {
    /// The blocked-socket path. The continuation returns this PerchResponse and the hook
    /// prints it. Claude and Codex-CLI both land here.
    case hookResponse(PerchResponse)
    /// Cursor: no blocked socket. Perch writes a marker file the agent is polling for.
    case marker(url: URL, contents: Data)
    /// Claude native-defer: return `.ask` so the agent's own approval UI owns the decision.
    case nativeDefer
    /// Codex Desktop and anything else with no answer channel: Perch cannot resolve it.
    /// The card is read-only and the only action is a jump to the owner.
    case observeOnly
}

@MainActor
protocol ApprovalAdapter {
    var agent: Agent { get }
    /// Some agents cannot express every scope (a marker file may only mean "this turn").
    func supports(_ scope: ApprovalScope, for pending: PendingPermission) -> Bool
    /// Turn a decision into the channel that carries it back to this agent.
    func route(_ resolution: ApprovalResolution, for pending: PendingPermission) -> RoutedDecision
    /// Did the user already answer this at the source (terminal / native UI)? If so Perch
    /// withdraws its card instead of double-handling. Cheap, polled while the card is up.
    func resolvedAtSource(_ pending: PendingPermission) -> Bool
}
```

Concrete adapters:

- **`ClaudeApprovalAdapter`** — every scope → `.hookResponse`, building the `PerchResponse`
  from the table above (reusing `PermissionRule.remembered` for the rule content). `defer` →
  `.nativeDefer` (i.e. `.ask`), which is exactly today's "Ask in terminal". `resolvedAtSource`
  is false — the socket is blocked, so nothing else can answer.
- **`CodexApprovalAdapter`** — CLI sessions behave like Claude (same hook vocabulary) →
  `.hookResponse`. `conversation`/`always` map onto Codex's **approval-mode** concept via
  `setMode`-style `updatedPermissions` rather than a per-tool rule where Codex expects a mode.
  A request with no blocked hook (originator `Codex Desktop`, surfaced from `CodexSessions`)
  → `.observeOnly`; `resolvedAtSource` returns true once the rollout advances past the tool call.
- **`CursorApprovalAdapter`** — `.marker`: writes an approval decision file under the project's
  Cursor state dir that the agent polls; `supports` returns true only for `.turn` (and
  `.conversation` if Cursor grows a session marker), false for `.always`. `resolvedAtSource`
  checks whether the marker was consumed or superseded.
- **Fallback** for `gemini`/`opencode`/`unknown`: `.hookResponse` if `wantsDecision`, else
  `.observeOnly` — the safe default, identical to today's behaviour.

### 2.3 Owner / viewing state machine

Every pending approval gets an **owner** identity and a small lifecycle so Perch never resolves
something twice or resolves something it no longer owns.

```swift
// PerchKit/Approval.swift (new)

/// Who this approval belongs to — enough to route back and to tell "am I looking at it".
public struct ApprovalOwner: Sendable, Equatable {
    public var agent: Agent
    public var sessionId: String?
    /// The frontmost-comparison key, from ClientInfo.launcher / terminal bundle.
    public var bundleId: String?
    public var client: ClientInfo?

    public static func of(_ request: PerchRequest) -> ApprovalOwner { /* agent + client */ }
}

public enum ApprovalOwnerState: Sendable, Equatable {
    case requested        // arrived, not yet shown
    case surfaced         // on a card (panel or dot)
    case resolvedByPerch  // user chose verb+scope in Perch
    case resolvedAtSource // user answered in the terminal / native UI — Perch steps back
    case expired          // backstop timeout
    case routedBack       // adapter delivered the answer; leaving the queue
}
```

`PendingPermission` gains `let owner: ApprovalOwner` and `var ownerState`. "Am I currently
viewing it" reuses the existing signal: `owner.bundleId == scene.frontmostBundleId`. When that
is true and the agent has its **own** prompt on screen (native defer or a CLI prompt), Perch
prefers `.surfaced`-but-quiet (today's `smartSuppression`) and lets `resolvedAtSource` retire
the card, rather than racing the user's keystroke in the terminal.

```
        hook line (wantsDecision)                 disk observe (CodexSessions / marker)
                  │                                          │
                  ▼                                          ▼
             ┌─────────────────────────  REQUESTED  ────────────────────────┐
             │   PermissionBroker.request()  ·  owner = ApprovalOwner.of()   │
             │   dedup by duplicateKey (unchanged)                           │
             └───────────────────────────────┬───────────────────────────────┘
                                              │ InterruptionPolicy.decide
                                              │   (panel / dot / notify — unchanged)
                                              ▼
                                          SURFACED ───────────────────────────┐
                                              │                               │ adapter.resolvedAtSource()
                          user picks verb+scope in card                       │ == true  (answered in
                          (Allow·turn / Allow·conversation /                  │  terminal or native UI)
                           Allow·always / Deny·… / Defer)                     ▼
                                              │                        RESOLVED-AT-SOURCE
                                              ▼                        (withdraw, no answer sent)
                                   RESOLVED(verb, scope) ─────────────────────┤
                                              │                               │ backstop 24h
                          ApprovalRouter.route(resolution, pending)           ▼
                                              │                            EXPIRED
             ┌───────────────┬────────────────┼────────────────┬─────────────┘ (verb=.ask)
             ▼               ▼                 ▼                ▼
      .hookResponse      .marker           .nativeDefer     .observeOnly
   (Claude / Codex-CLI: (Cursor: write   (return .ask →    (Codex Desktop /
    continuation returns  marker file      agent's own       no channel: jump
    PerchResponse →       agent polls)     prompt owns it)    to owner only)
    hook stdout)              │                 │                │
             └───────────────┴────────┬────────┴────────────────┘
                                      ▼
                             ROUTED-BACK-TO-OWNER
             blocked session unblocks / marker consumed / prompt handed over;
             PermissionBroker.onResolved fires, card leaves the queue (unchanged exit).
```

## 3. Concrete integration points

1. **`PerchKit/Approval.swift` (new).** `ApprovalScope`, `ApprovalVerb`, `ApprovalResolution`,
   `ApprovalOwner`, `ApprovalOwnerState`, and the scope→`RememberedRule.Destination` mapping.
   Add `behavior: allow|deny` to `RememberedRule` (`Wire.swift`) and emit it in
   `HookOutput.encode`'s `addRules` block (it already writes `behavior` for allow) so deny-side
   scoped rules are expressible. `PermissionRule.remembered` gains a `scope`/`behavior`
   parameter to stamp the destination instead of always `.localSettings`.

2. **`PerchApp/Permissions/ApprovalAdapter.swift` + `ApprovalRouter` (new).** The protocol above
   plus a `@MainActor` registry keyed by `Agent`. `PendingPermission` gains `owner` and
   `ownerState`; `PermissionBroker` gains `resolve(_ pending:, resolution:)` that calls
   `router.route(...)` and either resumes the continuation with the returned `PerchResponse`
   (`.hookResponse`/`.nativeDefer`) or performs the side effect (`.marker`) before `finish()`,
   and `withdraw(_ pending:)` for the `resolvedAtSource`/`observeOnly` paths (leaves the queue
   via the existing `finish` without sending a decision). A lightweight poll while a card is up
   calls `adapter.resolvedAtSource` so a terminal answer retires the card. `AppModel.decide` /
   `answer` / `approvePlan` route through this new overload; the timeout still resolves `.ask`.

3. **`PerchApp/UI` scope buttons.** A shared `ScopePicker` (This turn · This conversation ·
   Always) added to `PermissionAlertView.buttons` — the actual approval card — replacing the
   flat `Allow` / `Always` pair: the user picks a scope, then `Allow`/`Deny` apply the chosen
   scope, and `Defer` maps to today's "Ask in terminal". Each scope button is enabled only when
   `adapter.supports(scope, for: pending)` (so a Cursor marker card hides *Always*, a Codex
   Desktop card shows read-only + *Jump*). The help text shows the resulting destination
   (`Adds Bash(npm run:*) to …session` vs `…settings.local.json`). `QuestionCardView` and
   `PlanCardView` reuse the same `ScopePicker` so the three cards speak one scope vocabulary;
   the plan card's existing `PlanMode` buttons already express a session-scoped grant and fold
   into this as the `conversation` scope.
```
