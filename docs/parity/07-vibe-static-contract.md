# 07 — Vibe Island 1.0.44 Static Contract

Audit date: 2026-08-17. This document supersedes any broad visual-parity claim
in the previous audit. A matching settings screenshot is not 100% product
parity.

## Evidence chain

```text
/Applications/Vibe Island.app (1.0.44)
        |
        +-- workflow-rev fresh extraction
        |      +-- Swift reflection names and stored properties
        |      +-- localizations, resources, entitlements and URLs
        |
        +-- native captures made before trial expiry
               +-- idle / working island states
               +-- settings panes
                       |
                       v
              verified contract below
                       |
                       v
                 Perch gaps
```

Fresh extraction root:
`.artifacts/vibe-island-rev-20260816-r5/vibe_island_extract/2026_08_16`.
The installed bundle was extracted again without reusing that snapshot at
`.artifacts/vibe-island-rev-20260817-r6/vibe_island_extract/2026_08_17`; it
still identifies Vibe Island 1.0.44 and build commit `44eb7db9bcfb`.
The source application is a universal native SwiftUI/AppKit application. Its
bundle identifier is `app.vibeisland.macos`, its minimum system is macOS 14,
and its extracted version is `1.0.44`.

## Main island contract

The binary exposes these separate Swift views; they are not interchangeable
skins over a generic card:

- `NotchContentView`, `NotchPanel`, `NotchWindowController`, `NotchShape`
- `PixelStatusIcon`, `PixelStatusIconCompact`, `PixelSessionIcon`
- `SessionsListView`, `SessionCardView`, `SessionCardTitleParts`
- `CompletionCardView`, `StatusWarningCardView`
- `TaskListView`, `TaskRowView`, `ChildAgentAttentionView`
- `CompactingProgressLabel`, `JumpToTerminalPill`, `BypassActivePill`
- `StateIndicator`, `ArchiveButton`, `CompletionUnreadDot`, `TagPill`
- `LockedSessionsSummaryRow`, `FreeModeCallToActionRow`,
  `ShowAllSessionsButton`
- `KittyConfigBannerView`, `IDEExtensionBannerView`,
  `IntegrityReinstallBannerView`, `RestartSessionsBannerView`,
  `CodexHookTrustBannerView`

The reflected session-card inputs include `projectName`,
`worktreeDisplayLabel`, `hostWorkspaceDisplayName`, `sessionContent`,
`isActive`, `isFocused`, `isCollapsed`, `showModelInPanel`,
`showReasoningEffortInPanel`, `showWorktreeChip`, `showProjectName`,
`hideTaskList`, and `hideTaskSubagents`.

The `__swift5_fieldmd` section was parsed directly from the arm64 slice after
the initial string audit. It establishes the following stored-property
contract and removes the ambiguity caused by adjacent strings:

The parser now also resolves the relative pointers in `__swift5_types` back to
their nominal descriptors. The named output is stored in
`.artifacts/vibe-island-rev-20260816-r5/fieldmd-named.json`; it names 1,435 of
1,455 field descriptors instead of inferring view ownership from string
proximity.

| Vibe type | Stored properties recovered from 1.0.44 |
|---|---|
| `PixelStatusIcon` | `status`, `_phase`, `timer` |
| `PixelStatusIconCompact` | `status` |
| `PixelSessionIcon` | `status`, `_phase`, `timer` |
| `SessionCardTitleParts` | `projectName`, `worktreeDisplayLabel`, `hostWorkspaceDisplayName`, `sessionContent` |
| `SessionsListView` | `viewModel` |
| `SessionCardView` | `session`, `isActive`, `isFocused`, `isCollapsed`, hover state and the six display preferences |
| `TaskListView` | `tasks` |
| `CompactingProgressLabel` | `startedAt` |
| `JumpToTerminalPill` | `session`, `_isHovered` |
| `BypassActivePill` | `sessionId`, `runtimeInstanceId`, exit-button metadata and `exitAction` |
| `StateIndicator` | `status`, `isActive` |
| `ArchiveButton` | `action`, `_isHovered` |
| `TagPill` | text, foreground/background opacity, brand color, minimum width, trailing icon and tap action |
| `CompletionCardView` | `session`, `viewModel` |
| `StatusWarningCardView` | `message`, `viewModel` |
| `ChildAgentAttentionView` | `teamMembers`, `onButtonAreaHover` |
| `ShowAllSessionsButton` | `count`, `action`, hover state |

The same named metadata proves Vibe's display controller is not a simple
open/closed toggle. `NotchViewModel` stores `displayState`, manual/deferred
session sets, auto-collapse generations, hover-zone state, transient reveal
timing, completion-read state and team grouping. Its extracted policy types are
`DisplayIntent`, `DisplayDecision`, `DisplayExpansion`, `DisplayTimerPolicy`,
`DisplayHoverPolicy`, `DisplayFocusMutation`, `DisplaySessionEligibility` and
`FocusedSnapshot`. Perch now implements those named contracts in a dedicated
`DisplayPolicy`: one decision carries focus, expansion, timer and hover policy;
blocking requests reject incidental events; completion, compaction, warning,
hover, promotion, pin and focused-session disappearance have independent
routes. `NotchController` and `ExpandedView` consume the policy's session focus
instead of opening an arbitrary completed row.

`DisplaySessionEligibility` is now an executable gate rather than reflected
metadata only. It distinguishes visible, hidden, missing and event-shell
sessions from the authoritative activity store. Completion and failure events
cannot play sounds, post notifications or transiently reveal a session that
the user archived or filtered out. A synthetic event shell is eligible only
when no stored session exists, matching the separate Vibe policy branch.

Perch now uses one `PixelSessionIcon` per session card rather than duplicating
the two collapsed-island icons. `StateIndicator` is shared by Codex and terminal
sessions, and completed sessions expose an explicit archive action that cannot
be undone by the next rollout polling cycle. A new prompt in that same session
makes it visible again.

The generic metadata capsules on session cards have now been replaced by the
reflected `TagPill` contract. Terminal navigation is an explicit
`JumpToTerminalPill`, and permissive Claude sessions use a distinct
`BypassActivePill` with the optional exit-action shape preserved. Completed
and failed activity lines now route through dedicated `CompletionCardView` and
`StatusWarningCardView` presentations instead of indistinguishable text.

Per-session completion read state is now part of the reducer rather than a
view-only badge. A completion received while the panel is closed sets the
reconstructed `CompletionUnreadDot`; opening the panel clears every visible
completion, and a completion that arrives while the panel is already open is
born read. An idle Codex rollout discovered at launch is not misclassified as
a new completion. Five reducer tests cover those transitions.

The expanded list now also implements Vibe's `ShowAllSessionsButton`: the
glance view renders the first three stable session rows, exposes the total in a
single explicit expansion button, and automatically expands if the keyboard
switcher selects a later session.

Native capture establishes the collapsed colour rule:

- completed/idle session: green primary pixel icon;
- working session: blue primary icon;
- two working sessions: blue primary plus blue compact icon;
- the centre label is a single truncated title or current tool summary;
- the trailing value is the visible session count.

Perch now follows that colour transition. The old implementation kept the
icon blue while idle and therefore did not match the reference.

The collapsed layout also now follows the captured ordering: icons, label,
flexible space, count. The former layout centered the label between two
flexible spaces and left a gap not present in Vibe.

The fixed transparent host canvas and every visible panel state are now capped
against the selected screen before AppKit positions them. Alert prose,
preferences copied from a larger monitor and compact external displays cannot
push the island past the horizontal or bottom screen edge. A manual panel open
also expands the focused session, otherwise the first working session, matching
the reference rather than presenting a closed list first. Native evidence is
archived as `.artifacts/perch-captures/fresh/working-compact-r34.jpeg` and
`.artifacts/perch-captures/fresh/expanded-bounded-r35.jpeg`.

Claude teammate transport wrappers, including attributed `teammate-message`
payloads, are filtered both when events arrive and when an older persisted card
is rendered. They no longer replace the user prompt or transcript; Vibe's
separate child-agent presentation remains the visible destination for that
state.

## Onboarding contract

The fresh type metadata distinguishes `OnboardingFullscreenWindow`,
`OnboardingCardWindow` and `OnboardingReadyWindow`. A forced replay passed as a
temporary NSArgumentDomain value then exposed the live contract without
changing Vibe's stored preferences or license: welcome and demo are full-screen,
then configuration moves to a separate rounded 460×580 card window. Perch now
performs the same window transition. The configuration card matches Vibe's six
switchable agents, terminal/IDE pills, launch-at-login row, fixed primary action
and five-step pagination. Its switches feed the actual selected installer set;
they are not decorative. Native evidence is archived as
`.artifacts/vibe-island-captures/fresh/onboarding-config-r105.png` and
`.artifacts/perch-captures/fresh/onboarding-config-r106.png`.

## Approval and question contract

Vibe has dedicated presentations for different requests:

- `PermissionApprovalView`
- `ExitPlanModeApprovalView`
- `QuestionApprovalView`
- `WizardQuestionView`
- `SingleQuestionView`
- `CopilotQuestionReadOnlyView`
- `CodexDesktopMCPApprovalButtons`
- `NativeApprovalHandoffButton`
- `QuestionSubmissionOverlay`
- `SingleSelectOptionButton` and `MultiSelectOptionButton`

Tool previews are also specialized: apply-patch diff, edit diff, file read,
file write, shell command, web fetch, web search, and a generic fallback.
Perch implements several corresponding behaviours, but it does not yet prove
the same presentation and routing for every combination. This area remains
partial.

Single-question and multi-question requests now route through distinct
`SingleQuestionView` and `WizardQuestionView` surfaces while sharing one answer
and submission engine. Single- and multi-select option buttons have separate
selection behaviour, hover state, accessibility identifiers and the observed
Control-number shortcuts. Permission, question and plan decisions share an
`ApprovalButton` contract rather than three unrelated button styles. Copilot
questions now route through a read-only `CopilotQuestionReadOnlyView`: their
options remain visible, but the only decision returns to the owning client
instead of pretending Perch can submit an unsupported answer payload.

The extracted `QuestionDraftID`, `QuestionAnswerDraft` and `QuestionDraftStore`
contracts are now implemented as well. Picked options, typed answers and the
current wizard page survive SwiftUI reconstruction and panel collapse, keyed by
session/runtime/request identity, then are purged when that request resolves.
The store remains process-local so unanswered conversation text is never
persisted to disk.

## Session and display state contract

Extracted model names establish a policy layer around the UI:
`NotchDisplayState`, `DisplayCollapseReason`, `DisplayDecision`,
`DisplayIntent`, `DisplaySessionEligibility`, `DisplayBlockingKind`,
`DisplayHoverPolicy`, `DisplayTimerPolicy`, `DisplayExpansion`,
`DisplayFocusMutation`, and `FocusedSnapshot`.

Vibe also models active compaction, child-agent attention, transient automatic
reveal, Codex desktop bypass/approvals/read state, pill snapshots and team
grouping. Perch now tests the blocking priority, compact warning, transient
completion, hover promotion, manual-panel stability and hidden-session collapse
paths, plus hidden/missing/event-shell eligibility. Native validation is archived as
`.artifacts/perch-captures/fresh/panel-r29-display-policy.jpeg`. The unobservable
branches of Vibe's complete transition table still block a truthful 100% UX
claim.

The former inline `└ child age` treatment has been replaced by the dedicated
bounded child-agent card reflected by `ChildAgentsSection` and `ChildAgentRow`.
It keeps running and completed children in one surface, reports live/done state
and duration, caps the visible list at three rows, and summarizes overflow so a
large fan-out cannot widen or vertically consume the island. A completed child
remains readable for the rest of its user turn but no longer counts as live work;
the next prompt clears that completed history. Out-of-order completion remains
matched by the child agent's own id. The rendered specimen is
`.artifacts/perch-captures/fresh/subagent-card-r57.png`; the live build was also
exercised with real `UserPromptSubmit` and `SubagentStart` hook payloads and
inspected through Computer Use.

Perch now surfaces populated-session health banners instead of reserving hook
diagnostics for an empty panel. Native validation showed the extracted
`CodexHookTrustBannerView` equivalent above a live Codex session when only part
of its hooks were trusted.

## Settings and services contract

The 940 English localization keys and reflected properties confirm these
product surfaces beyond basic pane geometry:

| Surface | Vibe 1.0.44 evidence | Current Perch status |
|---|---|---|
| Integrations | terminal-title management, trust repair, accessibility state, custom paths, Kiro/Hermes setup | Partial |
| Labs | Cursor and Codex approval modes, native approval deferral, Kiro delay, memory restart, AI naming/writeback | Partial |
| Sound | source/custom stores, pack import, search, quiet hours, pack enablement | Partial |
| Usage | account store, provider adapters, pricing sync, reset signals, model buckets, cache | Partial |
| SSH | discovery, deployment, edit/remove, tunnels, cleanup, Codex roots, remote usage probes | Partial |
| License | trial, activation, device selection/deactivation, tiers, checkout and restore | Intentionally unavailable without a legitimate backend |
| Updates | Sparkle state machine, download progress, release notes and install replies | Partial |
| Localization | en, zh-Hans, ja, ko, fr, pt-BR, ru, zh-Hant, de, he | Perch ships only en/fr |

The Display toggles for model, reasoning effort and worktree previously changed
only preferences. They now read the latest Codex `turn_context` (`model` and
`effort`) plus `session_meta.git.branch`, propagate those values through the
session tracker, and render them as independent tags. Native validation on the
active thread showed `gpt-5.6-sol`, `medium`, and `main`; disabling either toggle
still removes only its corresponding tag.

The settings shell now uses the same native `NavigationSplitView` structure as
the reference while retaining the reconstructed Vibe rows. Native accessibility
inspection places the divider at exactly 188 points, reports an empty window
title, exposes the standard sidebar toggle, and shows the system-language value
as `Langue du système`. The General detail starts at the measured 208-point x
coordinate and keeps the observed System, Deployment, Visibility and Closing
order.

Fresh native recaptures after the settings reconstruction are stored as
`.artifacts/perch-captures/settings/display-r13.jpeg`, `labs-r13.jpeg`, and
`about-r15.jpeg`. Display now uses the bundled wallpaper, blue active toggles,
the observed slider domains and session-strip density miniatures. Labs uses the
captured Codex labels and helper copy. About now follows the five-row icon,
divider, trailing-value and external-link structure. The locked Pass screen is
also reconstructed as a product-local activation surface; it does not read,
reset, or imitate Vibe's commercial license state.

The later Display calibration is captured in
`.artifacts/perch-captures/settings/display-r21.jpeg`. Its panel-size card now
uses the measured 73-point slider-row cadence, blue active tracks and the same
flat value-plus-circular-chevron menu primitive visible in Vibe. That menu
primitive is shared by General, Display, Shortcuts, Labs, Usage and
Notifications rather than leaving AppKit's large rounded capsules on some
panes.

The native comparison was refreshed after those changes rather than relying on
the earlier captures. General, Integrations, Notifications, Sound-off, Usage,
Labs, Pass and the empty SSH pane now follow the same card order, widths and
conditional visibility as the Vibe captures. The former Perch screenshots that
showed quiet scenes first in Notifications, hooks first in Integrations and the
entire disabled sound catalog are obsolete states. The expanded Vibe session
and locked-row evidence recovered from the Computer Use cache is archived as
`.artifacts/vibe-island-captures/fresh/expanded-session-with-pass.jpeg` and
`collapsed-session-with-pass.jpeg`.

SSH is no longer only a set of copied shell commands. `RemoteHost` now persists
the reflected Vibe form contract: SSH options, manual-only connection,
automatic hook updates, Claude usage relay and Codex usage probing. Existing
two-field records migrate with explicit defaults. Perch owns each tunnel
process it launches, reports disconnected/connecting/connected/failure,
auto-connects only hosts that opted into it, disconnects the exact owned
process and confirms remote cleanup before removal. Configure runs the real
deploy script and, when selected, wires the remote Claude usage relay. The
advanced form capture is
`.artifacts/perch-captures/settings/remote-add-host-r28.jpeg`. Perch now also
persists Vibe's deployment metadata (`deployed`, `lastDeployedAt`,
`lastDeployError`, `deployedHookVersion` and additional Codex roots). An
auto-connected host whose managed hook is missing or on a different
`Wire.protocolVersion` is redeployed before its tunnel opens; failures remain
visible on the host row instead of connecting incompatible endpoints.

The root-discovery half is now wired into the host UI rather than existing only
as persisted fields and a shell command. Each saved host exposes a bounded
Codex-roots sheet with the always-on `~/.codex` root, saved/manual absolute
paths, Paperclip discovery, selection persistence and the host's remote trust
state. Configuring a host now installs Perch's ten Codex hook events in every
selected root, preserves foreign hooks, creates a one-time backup and remains
idempotent on reinstall. Perch then starts `codex app-server --listen stdio://`
through the owned SSH process, sends `initialize` and `hooks/list`, and maps the
reported `managed`, `trusted`, `untrusted` and `modified` states to the persisted
host trust snapshot. The roots sheet exposes the same manual `Check Again`
recovery path and guidance observed in Vibe. Host editing preserves those roots,
trust and deployment metadata instead of silently rebuilding the record with
defaults. Host actions moved into a compact menu so the added route does not
overflow the settings card.

The hook merge was exercised twice against an isolated filesystem fixture: all
ten managed hooks were present, a foreign hook survived, the reinstall was
idempotent and the backup remained available. The exact Codex app-server JSON-RPC
exchange was also exercised against the locally installed Codex binary and
returned 26 trusted hooks. The empty-host shell was rechecked natively through
Computer Use and captured as
`.artifacts/perch-captures/settings/remote-empty-r59.jpeg`. No real SSH host,
remote scan or remote trust check was contacted during validation, so those
claims remain implementation-level rather than remote end-to-end proof.

Remote Codex activity now carries the configured host alias through the managed
hook. When that host has usage probing enabled, Perch debounces events for one
minute, starts at most one owned SSH/app-server probe at a time, calls
`account/rateLimits/read` for every selected Codex root, and displays the decoded
account windows only under the Codex usage tab. Existing Claude remote limits
remain isolated under Claude. The multi-bucket and historical response shapes
have parser coverage, and the exact request was exercised against the locally
installed Codex app-server. The managed remote hook is now replaced atomically
on deploy through SSH itself, so this metadata change is not stranded behind an
older already-present script. A real remote event-to-card round trip remains
unproved without a reachable test host.

The expanded usage header now renders dynamic windows from their human title
(`7d`) rather than leaking internal provider identifiers such as
`codex_primary`. This directly fixes the mismatch visible in Vibe's native
expanded capture while preserving the canonical `5h`/`7d` Claude labels.
Session prompts and `ai-title` records now also discard Claude's injected
`task-notification`, `system-reminder` and command wrappers. A machine-generated
marker can no longer replace the real session subject in the expanded card.

## Exact bundled resources

The Vibe bundle includes `DepartureMono-Regular.otf`, an onboarding wallpaper,
an onboarding ceremony sound, provider icons, pricing/community configuration,
and six platform hook binaries. Hash comparison shows that Perch currently
contains byte-identical copies of the font, wallpaper and ceremony sound.
Technical equality does not establish redistribution rights; provenance must
be resolved before a public release.

## Current conclusion

Perch is not yet an ISO 100% clone of Vibe Island 1.0.44. The settings shell,
collapsed island and child-agent card now have direct visual evidence, and many
integrations exist, but some dedicated routes, the unobserved display branches,
remote end-to-end behavior, sound catalog, usage providers, license backend and
eight additional localizations remain incomplete or unproved.

No Vibe trial, license file, device registration, receipt, checkout or
commercial state was reset or bypassed during this audit.
