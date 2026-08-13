# Remote agent deployment

Design spec. Run a coding-agent session on a **remote host** (or a container) and still get
Perch's notch UI, notifications, jump-affordances and permission prompts locally on the Mac.

Status: design only. No feature code is written into the app by this document. A working
**CLI-only prototype already exists** in `scripts/remote.sh` + `scripts/perch-remote-hook.sh`;
this spec is about promoting that prototype into a first-class, in-app Transport feature with a
tunnel state machine and a Settings surface.

---

## 1. How Perch's event channel works today (grounding)

The whole system is one request/response line protocol over a loopback TCP socket.

- **Listener.** `Transport/EventServer.swift` binds an **ephemeral 127.0.0.1 TCP port** with
  `NWListener`. It is deliberately locked down: `parameters.acceptLocalOnly = true` and
  `parameters.requiredInterfaceType = .loopback` — the comment says *"Never expose this beyond
  the machine."* On ready it publishes the handshake.
- **Handshake.** `PerchKit/Runtime.swift` writes `~/.perch/runtime.json` (mode `0600`) with
  `{ port, token, pid, version }`. `token` is a 32-byte hex CSPRNG string; `port` and `token`
  **change on every launch**. `load()` refuses a handshake whose `pid` is dead, so a stale file
  never makes a hook dial a dead port.
- **Framing.** `PerchKit/Wire.swift`: one JSON object per line, `\n`-delimited, both directions.
  `Wire.protocolVersion = 1`.
- **Local hook.** `perch-hook/main.swift` is a compiled Swift binary run by Claude Code / Codex
  on every hook event. It reads the payload on stdin, loads `runtime.json`, builds a
  `PerchRequest` (token, event, `wantsDecision`, `ClaudeHookPayload`, `ClientInfo`, `agent`),
  and round-trips it via `PerchKit/LineClient.swift` — a dependency-free **BSD-socket** client
  (`connect` to `127.0.0.1:port`, send one line, read one line). For a `PermissionRequest` it
  blocks up to 24h; telemetry events get 2s.
- **App side.** `EventServer` decodes the line, **checks `request.token == token`**, and calls
  the handler `AppModel.handle(_:)` (`PerchApp/AppModel.swift`). That method records activity,
  drives the notch (flash/alert/notify/push), and for decision events awaits the user via
  `PermissionBroker` before replying with a `PerchResponse` (also token-stamped).
- **Fail-open everywhere.** No `runtime.json`, no reply, or a token mismatch → the hook `exit 0`
  with no stdout, so the agent behaves exactly as if Perch were not installed.

Two properties in `Wire.swift` already exist **specifically to support non-local, non-Swift
clients** and are the seam this feature builds on:

- `PerchRequest.rawOutput: Bool?` — a client that cannot parse JSON sets this; the app then
  answers with `PerchResponse.outputB64` (base64 of the exact stdout bytes, built once in Swift
  via `renderedOutputBase64`). A remote shell hook stays a shell hook.
- `Wire.usageEvent ("__usage")` — a remote reporting its own plan quota "down the tunnel that
  already exists rather than over a second channel." Handled by `AppModel.recordRemoteUsage`.

**Conclusion for the design:** the channel is a token-gated, newline-framed JSON round-trip to a
loopback port. Anything that can open a TCP connection to that loopback port and echo the token
is a valid client. Remote deployment is therefore a *transport/topology* problem — get the
remote's bytes onto the Mac's loopback — not a protocol change.

---

## 2. Getting a remote's events onto the Mac's loopback

### 2.1 Chosen approach: SSH reverse tunnel (outbound from the Mac)

The listener is loopback-only and must stay that way (approving tool calls is at stake). So we do
**not** expose the port; instead the Mac dials **out** over SSH and asks the remote to forward a
port on *its own* loopback back to the Mac's listener:

```
ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -R 17890:127.0.0.1:<perch_port> user@host
```

The remote hook then connects to `127.0.0.1:17890` on the remote, SSH carries those bytes to the
Mac and delivers them to `127.0.0.1:<perch_port>` — i.e. straight into `EventServer` as if a local
hook had connected. **The loopback-only invariant is preserved**: bytes only ever arrive on the
Mac's 127.0.0.1, and the token still gates every request. This is exactly what the prototype's
`remote.sh connect` does; the design promotes it into a managed, auto-reconnecting subprocess.

Why reverse tunnel over the alternatives:

- *Outbound connection from remote → Mac* would require the Mac's port reachable from the network
  (breaks the loopback invariant; needs firewall/NAT holes). Rejected.
- *Bind EventServer on 0.0.0.0 + real TLS/mTLS* is a second security-critical surface to own.
  Rejected for v1; SSH already gives us transport auth, encryption and NAT traversal for free.

### 2.2 Transports (all four land bytes on the Mac loopback)

| Transport | How the remote reaches the Mac | Notes |
|---|---|---|
| **Plain remote SSH host** | reverse tunnel `-R 17890:127.0.0.1:<port>`; hook uses `/dev/tcp/127.0.0.1/17890` | the default path |
| **Remote Docker over SSH** | reverse tunnel to the host, then `docker exec` the agent in a container that shares the host net **or** `-R` published into the container | container needs `127.0.0.1:17890` reachable; simplest is `--network=host` on Linux, else forward into the container |
| **Local Docker container** | **no tunnel** — container dials the Mac directly via `host.docker.internal:<port>` (Podman: `host.containers.internal`) | inverted flow; prototype `remote.sh docker` |
| **Manual / air-gapped** | operator pastes the hook + `config` by hand; then any of the above transports for the bytes | corporate nets block scp far more than ssh; prototype `remote.sh manual` |

### 2.3 Auth

- **SSH:** public-key only for the tunnel subprocess (`-N` cannot type a password). Config carries
  `identityFile`, `proxyCommand`, `port`, and free-form `extraOptions`.
- **MFA / keyboard-interactive:** a bare `Process` running `ssh -N` cannot service an interactive
  prompt. Design: establish a **ControlMaster** master connection *first* in a mode that can prompt
  (either a short-lived interactive `ssh` the user completes, or an askpass helper), then the `-N`
  tunnel and all deploy/`scp` calls reuse it via `ControlPath` with `ControlPersist`. MFA is entered
  once per master.
- **Perch token:** unchanged — echoed both ways. Because the Mac's `token` rotates every launch,
  the tunnel controller must **re-push `~/.perch-remote/config` (mode 600) on every (re)connect and
  whenever `runtime.json` changes**, exactly as `remote.sh connect` re-pushes it. A stale token is
  the classic "why did it silently stop working" failure.

### 2.4 Delivering & launching the remote hook

Two shapes, chosen by the host config's `platform`:

1. **Shell hook (default).** Ship `scripts/perch-remote-hook.sh` verbatim (bash `/dev/tcp`, `nc`
   fallback, no jq/curl, no compiled dependency). Portable across amd64/arm64 with one artifact.
   This is what the prototype already does and what keeps "manual/air-gapped" a copy-paste.
2. **Compiled hook (optional, `platform = linux/amd64 | linux/arm64`).** For hosts where `/dev/tcp`
   is disabled and `nc` is absent, ship a cross-compiled `perch-hook-linux-<arch>`. The **platform
   pick** selects which artifact is scp'd; `uname -m` on the remote can auto-detect and set it.
   Requires adding Linux build products to the release (see risks). *Recommendation: default to the
   shell hook; treat the binary as an opt-in.*

Wiring the remote's CLIs = merge hook entries into the remote `~/.claude/settings.json`
(and `~/.codex/hooks.json`, opencode plugin) pointing at the deployed hook with
`--source <agent>` and per-event timeouts — the same table `remote.sh deploy` writes. Existing
non-Perch hooks are preserved; a settings backup is written first.

---

## 3. Architecture / data flow

```
   MAC (local)                         SSH transport                 REMOTE HOST
 ┌───────────────────────────┐                               ┌──────────────────────────────┐
 │ Perch.app                 │                               │  coding agent (Claude/Codex)  │
 │                           │                               │        │ hook event           │
 │  AppModel.handle(_)       │                               │        ▼                       │
 │      ▲     │ PerchResponse │                               │  perch-remote-hook.sh          │
 │      │     ▼   (+outputB64)│                               │  (reads stdin payload)         │
 │  EventServer (NWListener)  │                               │        │                       │
 │  127.0.0.1:<port>  ◄───────┼───────────────────────────────┼─ 127.0.0.1:17890              │
 │  acceptLocalOnly=true      │   ssh -N -R 17890:127.0.0.1:  │   (reverse-forwarded port)     │
 │      ▲                     │        <port>   user@host     │        │ token+port from        │
 │      │ reads               │   (ControlMaster for MFA)     │        ▼ ~/.perch-remote/config │
 │  ~/.perch/runtime.json     │                               │  ~/.claude/settings.json hooks │
 │  {port,token,pid}  ───push─┼──────────────scp/exec────────►│  ~/.perch-remote/{hook,config} │
 │                           │                               └──────────────────────────────┘
 │  NEW ── RemoteManager      │
 │   ├ RemoteStore  (hosts)   │   Local Docker variant (NO tunnel): container dials the Mac at
 │   ├ TunnelController×N     │   host.docker.internal:<port> directly; same PerchRequest/JSON.
 │   └ RemoteDeployer         │
 │  Settings ▸ "Remote" pane  │   Air-gapped variant: operator pastes hook+config by hand,
 │  (status: connected 4m ago)│   then bytes travel by whichever transport is reachable.
 └───────────────────────────┘
```

Everything left of the SSH boundary that is **NEW** is the scope of this feature. The listener,
`AppModel.handle`, `Wire`, and the remote hook script already exist and are reused unchanged.

---

## 4. Swift-level integration points in Perch

New code lives in a new folder `apps/mac/Sources/PerchApp/Transport/Remote/`. The three
load-bearing integration points, in priority order:

### Integration point 1 — `TunnelController` (the reverse tunnel as a managed subprocess)

`Transport/Remote/TunnelController.swift`, `@MainActor`, one instance per connected host.

- Owns a `Process` running `ssh -N -R <remotePort>:127.0.0.1:<perchPort> …`, with
  `ExitOnForwardFailure=yes`, `ServerAliveInterval=30`, `ServerAliveCountMax=3`.
- Before spawning, reads the current `RuntimeInfo` (`PerchKit/Runtime.swift`) for `port` + `token`
  and calls `RemoteDeployer.pushConfig(...)` to write `~/.perch-remote/config` (mode 600) on the
  remote. Re-pushes on every reconnect.
- Publishes an observable `TunnelState` and drives reconnection with backoff on process exit.

```swift
enum TunnelState: Equatable {
    case disconnected
    case connecting
    case connected(since: Date)            // powers "connected 4m ago"
    case reconnecting(attempt: Int)
    case error(String)
}
```

- **Token rotation hook:** `TunnelController` (via `RemoteManager`) observes app relaunch /
  `runtime.json` change and re-pushes config + restarts the tunnel. This is the single most
  important correctness detail — port+token change every launch.

### Integration point 2 — `RemoteManager` wired into `AppModel`

`Transport/Remote/RemoteManager.swift`, `@MainActor @Observable`, held by `AppModel` next to the
existing `@ObservationIgnored private var server: EventServer?` (`AppModel.swift:46`). Started in
`AppModel.start()` right after `server.start()` (`AppModel.swift:321-329`).

- Loads `RemoteStore` (hosts), reconciles auto-connect hosts, exposes `hosts: [RemoteHost]` and
  their `TunnelState` to the UI.
- Because remote requests already arrive through `EventServer` → `AppModel.handle`, **no change to
  the request path is required** for events to show up. Optional enrichment: give the notch a way
  to know a session is remote (e.g. thread a `host` label through, reusing the `__usage` host
  convention or a new optional `PerchRequest.origin`), so a card/notification can read
  "build-box · Claude" and so `Jump/TerminalJumper.swift` can **disable** local-jump for remote
  sessions (you cannot focus a terminal that is on another machine — see risks). This is additive
  and backward-compatible (older hooks omit it).

### Integration point 3 — `RemoteStore` + `RemoteDeployer` (config model + deploy actions)

- `Transport/Remote/RemoteHost.swift` — `Codable, Identifiable, Sendable` persisted to
  `~/.perch/remotes.json` (the prototype already uses this file; keep the shape compatible):

```swift
struct RemoteHost: Codable, Identifiable, Sendable {
    var id: UUID
    var alias: String                 // "build-box" — also the __usage host label
    var user: String
    var host: String
    var port: Int = 22
    var identityFile: String?
    var proxyCommand: String?
    var extraOptions: [String] = []
    var usesMFA: Bool = false
    var transport: Transport          // .ssh, .dockerOverSSH, .localDocker, .manual
    var platform: Platform            // .shell, .linuxAMD64, .linuxARM64
    var autoConnect: Bool = false
    enum Transport: String, Codable { case ssh, dockerOverSSH, localDocker, manual }
    enum Platform: String, Codable { case shell, linuxAMD64 = "linux/amd64", linuxARM64 = "linux/arm64" }
}
```

- `Transport/Remote/RemoteDeployer.swift` — deploy / wire / push-config / remove. Two viable
  implementations; pick per the app's existing pattern:
  - **Shell out to the vetted scripts** via `PerchApp/RepoScripts.swift` (`RepoScripts.run` /
    `.start`, which already resolves `scripts/` from the bundle or the dev repo). Lowest risk:
    `remote.sh deploy|remove|docker|manual`, `install-hooks.sh` logic already exists and is tested.
  - **Native Swift** driving `Process`/`ssh`/`scp` directly for finer status reporting. More work,
    better UX (per-step progress). Recommend starting with the script-shell approach and only
    porting `connect` natively (it must be a long-lived, observable subprocess — point 1).

Assembling `PerchRequest`/`PerchResponse` bytes needs no new code: `Wire.swift` already renders
the remote hook's stdout (`renderedOutputBase64`) and routes `__usage`.

---

## 5. Minimal UI surface

`PerchApp/UI/SettingsView.swift` currently has tabs `general | sound | filters | integrations |
about` (an enum `Tab` + a `switch` at ~line 44). Add one tab:

- `case remote = "Remote"`, icon `"externaldrive.connected.to.line.below"` (or `network`), and a
  `RemotePane(model:)` in the switch — mirrors the existing `IntegrationsPane` structure (Sections,
  `model` access).

`RemotePane` contents (kept intentionally small):

1. **Hosts list.** One row per `RemoteHost`: alias, `user@host`, a **status dot** driven by
   `TunnelState`, and a relative "connected 4m ago" label (from `.connected(since:)`, formatted
   with `RelativeDateTimeFormatter` on a 1s tick). Row actions: Connect / Disconnect, Deploy,
   Remove.
2. **Add / Edit sheet.** Fields: alias, user, host, port, identity key (file picker),
   proxyCommand, extra ssh options, "requires MFA" toggle, transport picker (SSH / Docker over SSH
   / local Docker / manual), platform picker (shell / linux amd64 / linux arm64), auto-connect
   toggle.
3. **Manual / air-gapped affordance.** A "Show paste command" button that reveals the hook +
   `config` one-liner to copy (reuse `RepoScripts.copyToPasteboard`), for scp-blocked networks.
4. **Tunnel status at a glance.** The section note shows the aggregate ("2 hosts, 1 connected").
   Optionally surface the same dot in the notch/menu for the currently-connected host.

No new notch UI is required for events themselves — remote sessions already render through the
existing card/flash/alert/notify path once bytes arrive.

---

## 6. Open questions

- **Token/port rotation:** confirmed rotates per launch. Auto re-push on `runtime.json` change to
  all connected hosts — needs a watcher. Should a reconnect be silent or surfaced?
- **Fixed remote port `17890`:** collides on a shared host with two Perch users, or with an
  unrelated service. Make it per-host configurable; detect `ExitOnForwardFailure` and surface it.
- **Blocking permission decisions over a flaky tunnel:** a `PermissionRequest` blocks the remote
  agent up to 24h. If the tunnel drops mid-decision the remote hook times out and fails open (the
  agent proceeds as if unhooked). Is fail-open acceptable for a *permission* on a remote? Probably
  yes (matches local semantics) but worth stating explicitly to the user.
- **Jump to a remote terminal:** `Jump/TerminalJumper.swift` focuses a *local* window. A remote
  session has no local window. Decide: disable jump for remote cards, or jump to the local
  terminal that holds the `ssh` session, or offer "open SSH session".
- **MFA UX:** ControlMaster-first is the plan; needs an askpass or an interactive pre-connect step.
  How to represent "master is up, tunnel reuses it" in the status model.
- **Remote Docker over SSH:** exact container networking (host net vs. forward-into-container) is
  under-specified; pick one supported topology for v1.
- **Multiple Macs / one remote:** two laptops both reverse-forwarding `17890` to the same remote
  conflict. Out of scope for v1?

## 7. Risks

- **Security (highest):** the reverse tunnel preserves the loopback-only + token invariant, but a
  bug that binds the listener to `0.0.0.0`, or a leaked/over-broad remote `config` (token is a
  bearer credential that can approve tool calls), breaks the whole security model. Keep `config`
  mode 600; never widen the listener; keep the token echo check on every request.
- **Subprocess lifecycle:** a managed `ssh -N` can wedge (sleeping laptop, half-open TCP).
  Keepalives + `ExitOnForwardFailure` + backoff reconnection are mandatory, not optional. Zombie
  ssh processes on quit must be reaped (mirror `EventServer.stop()`/`AppModel.stop()`).
- **Cross-compiled hook:** shipping `perch-hook-linux-{amd64,arm64}` adds a Linux toolchain to the
  release and a second artifact to keep in step with `Wire.protocolVersion`. Prefer the shell hook;
  the moment the wire schema is reimplemented in two languages it will drift (the codebase already
  learned this — see the `renderedOutput` comment in `Wire.swift`).
- **Prototype divergence:** `scripts/remote.sh` and `perch-remote-hook.sh` are the source of truth
  today. If `RemoteDeployer` reimplements deploy natively instead of shelling out, the two paths
  can drift. Prefer shelling out to the scripts for deploy/remove; only own `connect` in Swift.
- **Silent failure:** the whole chain fails open by design, which is correct but makes a broken
  remote invisible. The tunnel status UI + a "last event received Xs ago" per host are the only way
  a user learns their remote stopped reporting.

---

## Appendix — file map

Existing (reused unchanged):
- `apps/mac/Sources/PerchApp/Transport/EventServer.swift` — loopback listener + token check
- `apps/mac/Sources/PerchApp/AppModel.swift` — `handle(_:)`, `recordRemoteUsage`, `server` field
- `apps/mac/Sources/PerchKit/Wire.swift` — `PerchRequest.rawOutput`, `PerchResponse.outputB64`, `__usage`
- `apps/mac/Sources/PerchKit/Runtime.swift` — `~/.perch/runtime.json` (port/token/pid)
- `apps/mac/Sources/PerchKit/LineClient.swift` — the client shape the shell hook mirrors
- `apps/mac/Sources/perch-hook/main.swift` — local hook (reference for the remote hook)
- `apps/mac/Sources/PerchApp/RepoScripts.swift` — resolves/runs `scripts/`
- `scripts/perch-remote-hook.sh`, `scripts/remote.sh` — the CLI prototype to promote

New (this feature):
- `apps/mac/Sources/PerchApp/Transport/Remote/RemoteHost.swift`
- `apps/mac/Sources/PerchApp/Transport/Remote/RemoteStore.swift` (`~/.perch/remotes.json`)
- `apps/mac/Sources/PerchApp/Transport/Remote/TunnelController.swift` (`TunnelState`)
- `apps/mac/Sources/PerchApp/Transport/Remote/RemoteDeployer.swift`
- `apps/mac/Sources/PerchApp/Transport/Remote/RemoteManager.swift` (wired into `AppModel.start()`)
- `apps/mac/Sources/PerchApp/UI/SettingsView.swift` — new `.remote` tab + `RemotePane`
</content>
</invoke>
