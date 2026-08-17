# 06 — Vibe Island ISO Audit

Audit date: 2026-08-16. Reference: installed Vibe Island `1.0.44` compared with
the locally installed Perch `0.1.0` at `/Applications/Perch.app`.

This is an evidence ledger, not a claim of complete parity. A row is green only
when the behaviour was observed in both apps or covered by a deterministic test.
Visual similarity alone does not prove an integration, and a build does not prove
delivery to a phone, remote host, or signed release channel.

## Evidence flow

```text
Vibe Island.app ──► native UI / AX capture ──┐
                                             ├──► requirement matrix
extracted binary metadata + resources ──────┤          │
                                             │          ▼
Perch source + tests + installed app ───────┘    green / partial / blocked
```

## Status legend

- **Proved** — native observation or deterministic test establishes the result.
- **Partial** — the main path exists, but one reference behaviour or external
  proof is missing.
- **Blocked** — completing or proving the row needs user credentials, security
  consent, a commercial service, a remote host, or a policy-prohibited action.

## Native shell and panel

| Area | Status | Evidence / remaining gate |
|---|---|---|
| Idle notch strip | **Proved** | Installed Perch displayed the pixel status glyphs and the live-session count without the obsolete activity label, matching the current Vibe compact capture. |
| Expanded panel geometry | **Proved** | Native captures use the same 680×580 transparent host and 650 pt visible body as the current Vibe capture, with bounded collar, cards, tasks and footer. |
| Session cards | **Proved** | Project/title/activity/agent/terminal/age/status and expanded transcript were observed in the installed app. |
| Task board | **Proved** | Codex `update_plan` events populate live task rows; parser and ordering are covered by tests. |
| Last exchange / tool output | **Proved** | Full prompt, assistant reply, and tool output were observed for an OpenHermes session. |
| Jump to terminal/editor | **Proved** | Clicking a Perch session brought `com.cmuxterm.app` to the foreground. Unit tests cover exact routes for supported terminals/editors. |
| Jump to Codex desktop thread | **Partial** | The route and unit test exist. Native inspection of `com.openai.codex` was denied by the Computer Use safety boundary, so the final desktop interaction is not claimed. |

## Settings UI

| Pane | Status | Evidence / remaining gate |
|---|---|---|
| General | **Proved** | Same controls and fresh defaults: launch off, hover 0.15 s, smart suppression on, fullscreen hiding on, session hiding off, hover-exit collapse on, completion 5 s, outside-click off, idle cleanup 2 h. Existing user preferences are deliberately not overwritten. |
| Integrations | **Partial** | The same eight always-visible agents are represented: Claude, Codex, OpenCode, Gemini, Cursor, Droid, Pi, Amp. Kimi, Kimi Code, Mistral Vibe, DeepSeek TUI/CodeWhale, WorkBuddy, CodeBuddy, Antigravity CLI, and GitHub Copilot CLI appear when their observed config directories are detected and can be configured with native TOML or JSON hooks. Perch additionally exposes hook/trust diagnostics. |
| Notifications | **Proved** | Completion notification defaults match: enabled; Focus, locked/obscured, and screen-shared suppression off. |
| Bark mobile notifications | **Partial** | Public/self-hosted destination, device key, privacy toggle, QR setup, plain API v2, and AES-256-CBC requests exist and are tested. No device key was entered and no push was sent. |
| Display | **Proved** | Clean/detailed mode, display selection, 11 pt content, 90 pt completion height, 560×640 caps, project/worktree/task/subagent/activity toggles, and notch adjustments are present. |
| Sound | **Proved** | Enable/mute, volume, event mapping, bundled sound playback, and deterministic synthesized jingles are present and tested. Vibe's current local mute value is a saved preference, not a product default. |
| Usage | **Proved** | Direct Anthropic OAuth usage returned live 5 h and 7 d values in the installed app. Unknown model-scoped windows are preserved; only usage responses, never tokens, are cached. |
| Shortcuts | **Proved** | Control modifier, forward/reverse session cycling, enable switch, and panel shortcuts are implemented and tested. |
| SSH remote | **Partial** | Empty-state UI, port `17891`, Docker disclosure, manual-install guidance, and remote protocol exist. No real host/key was supplied, so a remote round trip is not claimed. |
| Labs | **Proved** | Native Perch layout and values match the observed reference: beta off, memory restart off, Claude Auto Mode override off, approval-card ignoring off, Codex Auto Review follows focus, Codex thread opening off, Cursor YOLO automatic. |
| Pass | **Blocked** | The locked visual state matches. Native inspection, without purchase, showed Vibe's expired-trial sheet with one-time tiers for 1/2/3 Macs (`$14.99` / `$24.99` / `$34.99`), one year of updates, a locked launch price, checkout, and existing-key entry. A real trial, session cap, purchase, activation, device-count, and restore flow require a legitimate merchant/product/license backend. No Vibe license or trial was reset or bypassed. |
| About | **Partial** | Updates, release notes, website/creator/community/bug/feedback links, diagnostics, acknowledgements, cleanup, and quit exist. Vibe's purchase row and telemetry toggle depend on services Perch does not have; Perch intentionally does not display fake controls. |

## Integrations and security

| Capability | Status | Evidence / remaining gate |
|---|---|---|
| Claude Code hooks | **Proved** | Install, backup, idempotency, permissions, questions, subagents, failure, stop, compact, and uninstall paths are tested. |
| Codex hooks | **Partial** | 10 of 14 installed Perch hook positions are trusted. The four added error positions require explicit approval through Codex `/hooks`; Perch does not forge trust hashes. |
| OpenCode / Gemini / Cursor / Droid / Pi / Amp | **Partial** | Configuration and source identity exist. Full real-session native exercises were not completed for every CLI on this machine. |
| Claude Cowork / desktop observers | **Partial** | Vibe metadata exposes dedicated Cowork/title observers; Perch currently relies on standard Claude transcript/hook paths. |
| Codex desktop private IPC / approval ownership | **Partial** | Perch reads Codex rollouts and can route to a thread, but does not reproduce Vibe's extracted private-IPC monitor/coordinator classes. Private IPC must not be guessed without a stable, authorized contract. |
| DeepSeek / Antigravity watchers | **Partial** | DeepSeek TUI's legacy `~/.deepseek/config.toml` and CodeWhale's current `~/.codewhale/config.toml` contracts are implemented as observer-only telemetry: nine session, prompt, tool, error, turn, and subagent events plus documented `DEEPSEEK_*` context. Antigravity's documented global named-hook contract is also implemented for pre/post tool and stop telemetry with camelCase normalization. All installers are backed up and reversible, and none fabricates decisions. Real sessions remain required for end-to-end proof. |
| Kimi / Kimi Code hooks | **Partial** | Both official config roots are detected. Perch installs an idempotent, delimited `[[hooks]]` block, preserves foreign TOML and user providers/models, backs up before writes, rejects conflicts or broken markers, and removes only its block during uninstall. Kimi's observation-only permission event never holds the CLI. A real Kimi session is still required for native end-to-end proof. |
| Mistral Vibe hooks | **Partial** | The stable official `pre_tool`, `post_tool`, and `post_agent` contracts are mapped to Perch, installed in a delimited `~/.vibe/hooks.toml` block, backed up, idempotent, and reversible. A real Mistral Vibe session is still required for native end-to-end proof. |
| GitHub Copilot CLI hooks | **Partial** | Vibe's extracted dedicated-file strategy is reproduced at `~/.copilot/hooks/perch.json` using GitHub's version-1 PascalCase compatibility format for thirteen documented events. Existing entries survive reinstall; the owned file is backed up and reversible. Permission events are observation-only, matching Vibe's extracted read-only question surface. A real session remains required. |
| Additional Vibe agent sources | **Partial** | Perch preserves the extracted `kimicode`, `deepseek`, `mistralvibe`, `workbuddy`, and `codebuddy` identities instead of mislabelling their events as Claude; unknown non-empty sources remain explicitly unknown. DeepSeek, WorkBuddy, and CodeBuddy now have native installers. Real sessions are still required for end-to-end proof. |
| Kimi / MiniMax / Z.ai usage | **Partial** | Vibe endpoints and provider names were identified. Perch has no credential-safe adapters for them yet; credentials were not requested or accessed. |

## Distribution and localization

| Area | Status | Evidence / remaining gate |
|---|---|---|
| Local install | **Proved** | Current build is installed at `/Applications/Perch.app` and was exercised through native macOS accessibility and screenshots. |
| Automated validation | **Proved** | `swift test`: 536 tests in 23 Swift Testing suites plus the XCTest run passed with zero failures. Localization plists, app build, strict code-sign verification and `git diff --check` pass. |
| Signed public release | **Blocked** | The installed build is a local development build. Developer ID signing, notarization, update-feed publication, and a release artifact require release credentials and explicit release authority. |
| Languages | **Partial** | Perch ships English and French. Vibe also exposes German, Hebrew, Simplified Chinese, Japanese, Korean, Traditional Chinese, Brazilian Portuguese, and Russian. |
| Creative assets | **Blocked** | Exact extracted competitor artwork/sound may carry copyright and redistribution restrictions. Production parity must use assets with a documented license or original Perch equivalents; pixel similarity is not sufficient authority to redistribute them. |

## Exit criteria for a truthful 100% claim

### Native visual pass — 2026-08-16

- Settings window chrome now uses the same 620×680 native full-size sidebar,
  traffic lights, 188 pt sidebar, 31 pt navigation rows, content width, card
  rhythm, compact 36×16 switches, and overlay scrollbar behavior observed in
  Vibe Island.
- General, Integrations, Notifications, Display, Sound, Usage, Shortcuts, SSH,
  Labs, Pass, and About were recaptured in both installed apps. Integration
  status placement, notification grouping, reminder checkboxes, Bark state,
  shortcut keycaps, SSH empty state, Labs captions, and About hierarchy were
  corrected from those captures.
- Admission settings now expose Vibe's seven observed built-in directory and
  first-prompt filters, with live match previews, launcher-app blocking, and
  separate custom directory/prompt sections. Presets follow Vibe's enabled
  default and preserve their explicit state across metadata migrations.
- The latest local build is installed at `/Applications/Perch.app`; the prior
  bundle is recoverable at `/Applications/Perch.app.backup-20260816-225329`.
- Vibe's main panel can no longer be recaptured because its legitimate UI is
  replaced by the expired-trial purchase sheet. No trial reset, license-state
  modification, checkout, or activation bypass was attempted.

All of the following must be completed before changing the overall status to
complete:

1. Choose and configure a legitimate license/checkout/activation backend, then
   test purchase, restore, trial expiry, and session-cap transitions without
   touching Vibe's license state.
2. Approve the four remaining Codex hook positions through Codex's own `/hooks`
   UI, then observe all 14 as trusted.
3. Supply a Bark device key and explicitly authorize a test push; confirm phone
   receipt in both privacy modes.
4. Supply an SSH test host/key and authorize a connection; verify discovery,
   session launch, event transport, jump, and disconnect.
5. Exercise every advertised CLI with a real session, including permission,
   question, failure, completion, transcript, and jump paths.
6. Either implement the additional observed desktop/provider integrations from
   stable contracts or explicitly remove them from the parity target.
7. Add and visually review the eight missing localizations.
8. Replace any unlicensed extracted creative asset with licensed or original
   material and retain provenance.
9. Produce, notarize, install, and smoke-test the exact release artifact.
