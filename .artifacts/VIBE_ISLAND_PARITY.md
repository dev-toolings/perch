# Vibe Island → Perch parity audit

Reference build: Vibe Island 1.0.44 (`44eb7db9bcfb`)

Evidence:

- Static extraction: `.artifacts/vibe-island-rev/vibe_island_extract/2026_08_16/`
- Vibe settings captures: `.artifacts/vibe-island-captures/settings/`
- Perch settings captures: `.artifacts/perch-captures/settings/`
- User idle reference: `.artifacts/reference-crops/vibe-idle-user.png`

Legend: `DONE` is implemented and observed in the installed Perch app. `PARTIAL` still
has a concrete delta. `MISSING` has no equivalent yet.

## Always-visible island

| Requirement | Status | Evidence / remaining delta |
| --- | --- | --- |
| One continuous black compact island | DONE | Installed Perch observed with the same glyph / spacer / count structure as Vibe on 2026-08-17 |
| Departure Mono | DONE | Vibe and Perch font SHA-256 both `4d53f663…` |
| No compact activity label | DONE | The current Vibe capture contains glyphs and count only; Perch now follows it |
| Plain active-session count | DONE | Installed compact island shows `2` |
| Compact blue pixel status glyph | PARTIAL | Structure matches; Perch sprite silhouette still differs |
| Hover expansion switch | DONE | Persisted preference and live controller behavior |
| Configurable hover delay (default 0.15s) | DONE | Persisted, clamped to 0…1s and applied before expansion |
| Smart suppression for frontmost agent terminal | DONE | Compares frontmost bundle with visible session hosts |
| Click to expand/collapse | DONE | Existing tested interaction state machine |
| Morph timings and silhouette | PARTIAL | Perch uses a spring/collar but exact Vibe timings remain unmeasured |

## General

| Requirement | Status |
| --- | --- |
| Launch at login | DONE |
| App language menu | DONE |
| Expand on hover | DONE |
| Hover delay | DONE |
| Smart suppression | DONE |
| Hide in fullscreen | DONE |
| Hide when no active session | DONE |
| Collapse on mouse exit | DONE |
| Auto-display duration | DONE |
| Close auto-display on outside click | DONE |
| Inactive-session cleanup | DONE |
| Disable click-to-jump | DONE |

## Display

| Requirement | Status |
| --- | --- |
| Wallpaper + live notch preview | PARTIAL (matching composition; static Perch gradient) |
| Compact / detailed layouts | DONE |
| Target screen picker | DONE |
| Content font size | DONE |
| Completion-card height | PARTIAL (wired to flash height; Vibe completion payload still to compare) |
| Maximum panel height and width | DONE |
| Show project / worktree / model / reasoning toggles | PARTIAL (project/model live; worktree/reasoning specimen only) |
| Show tasks / subagents / activity toggles | DONE |
| Live session-card specimen | DONE |
| Notch width / height tuning | DONE |

## Integrations

| Requirement | Status |
| --- | --- |
| Claude Code | DONE |
| Codex CLI and Codex desktop watcher | DONE |
| OpenCode | PARTIAL |
| Gemini CLI | PARTIAL |
| Cursor Agent, Droid, Pi, Amp | MISSING |
| Add custom CLI branch | MISSING |
| Automatically configure newly detected agents | PARTIAL (preference and detection UI; automatic installer pending) |
| Cursor IDE extension install | DONE |
| Custom jump rules | PARTIAL (runtime renderer and sheet installed; no third-party scheme exercised) |

## Notifications and filtering

| Requirement | Status |
| --- | --- |
| Completion notification policy | DONE |
| Child-agent / Agent Teams timing | PARTIAL (runtime policy wired; live child event still to exercise) |
| Follow-up reminder | PARTIAL (runtime timers wired; delayed live reminder still to exercise) |
| Mobile notification delivery | PARTIAL (ntfy instead of Bark) |
| Focus / lock / screen-share quiet scenes | DONE |
| Blocked launcher apps | PARTIAL |
| Directory filters | DONE |
| First-prompt filters | DONE |
| Built-in filter details and live match preview | PARTIAL |

## Sound

| Requirement | Status |
| --- | --- |
| Master sound switch | DONE |
| Per-event sounds and volume | DONE |
| Built-in chiptunes | DONE |
| Imported sound packs | PARTIAL |

## Usage

| Requirement | Status |
| --- | --- |
| Subscription limits in panel header | DONE |
| Used / remaining mode | DONE |
| Preferred provider | PARTIAL (fixed/automatic routing wired; live cross-agent switch still to exercise) |
| Codex reset cards | PARTIAL (header reset display toggle; exact Vibe reset-card model pending) |
| Claude statusline bridge | DONE |

## Shortcuts

| Requirement | Status |
| --- | --- |
| Global switcher | DONE |
| Enable/disable all shortcuts | DONE |
| Configurable modifier only | DONE |
| Reverse switcher | DONE |
| Panel approve / deny / always / bypass / jump keys | DONE |
| Question option and multi-select shortcuts | DONE |

## SSH Remote

| Requirement | Status |
| --- | --- |
| Copyable remote scripts | PARTIAL |
| Managed host list and add/edit sheets | PARTIAL (add sheet observed; edit requires a configured host) |
| TCP port setting | DONE |
| Automatic deployment, tunnel and reconnect | PARTIAL (deploy/connect actions present; reconnect pending) |
| Remote Claude/Codex usage probes | PARTIAL (Codex roots, quota parsing and trust probe implemented and tested; no real SSH host exercised) |
| Docker/Podman sidecar flow | PARTIAL |
| Air-gapped manual flow | PARTIAL |

## Labs

| Requirement | Status |
| --- | --- |
| Beta updates | DONE |
| Idle-only memory safety restart | PARTIAL (sustained-footprint guard wired; threshold path not induced live) |
| Claude Auto Mode override | PARTIAL (preference/UI; hook-mode rewrite pending) |
| Ignore Claude approvals | DONE |
| Codex Auto Review focus policy | PARTIAL (preference/UI; event classification pending) |
| Open app-server threads in Codex app | PARTIAL (preference/UI present; routing gate pending) |
| Cursor YOLO detection policy | MISSING |

## About and lifecycle

| Requirement | Status |
| --- | --- |
| App identity and version | DONE |
| Sparkle check/install | DONE |
| Release notes | DONE |
| Automatic update toggles | DONE |
| Website, creator, community, bug and feedback links | DONE |
| Diagnostic export | DONE |
| Telemetry opt-in | MISSING |
| Acknowledgements | DONE |
| Remove automated configuration | DONE (uninstaller) |
| Quit from settings | DONE |

The Pass/licensing pane is Vibe Island commerce, not an agent-workflow capability. It is
recorded in the reference captures but is not considered a Perch product requirement unless
Perch gets a commercial licensing model.
