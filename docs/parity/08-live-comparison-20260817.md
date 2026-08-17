# 08 — Live Vibe / Perch Comparison, 2026-08-17

This is the current native evidence ledger. It does not assert complete product
parity.

## Evidence

- Fresh Vibe 1.0.44 extraction:
  `.artifacts/vibe-island-reaudit-20260817-r3/vibe_island_extract/2026_08_17`.
- Vibe expanded panel:
  `.artifacts/vibe-island-captures/fresh/expanded-live-r78.jpeg`.
- Perch expanded panel:
  `.artifacts/perch-captures/fresh/expanded-live-r101.jpeg`.
- Perch exact-local live compact/rest and expanded/clean captures:
  `.artifacts/perch-local-reaudit-20260817-r2/current/rest-live.jpeg` and
  `.artifacts/perch-local-reaudit-20260817-r2/current/expanded-clean-live.jpeg`.
- Vibe onboarding configuration replay:
  `.artifacts/vibe-island-captures/fresh/onboarding-config-r105.png`.
- Perch onboarding configuration:
  `.artifacts/perch-captures/fresh/onboarding-config-r106.png`.
- Vibe onboarding license step:
  `.artifacts/vibe-island-captures/fresh/onboarding-license-r107.png`.
- Perch full-screen welcome:
  `.artifacts/perch-captures/fresh/onboarding-welcome-r108.png`.
- Vibe / Perch Display settings:
  `.artifacts/vibe-island-reaudit-20260817-r1/display.jpeg` and
  `.artifacts/perch-local-reaudit-20260817-r2/display-hstack.jpeg`.
- Vibe / Perch Sound settings:
  `.artifacts/vibe-island-reaudit-20260817-r1/sound.jpeg` and
  `.artifacts/perch-local-reaudit-20260817-r2/sound.jpeg`.
- Fresh native Vibe settings:
  `.artifacts/vibe-island-reaudit-20260817-r3/display-native-20260817-1012.jpeg`,
  `.artifacts/vibe-island-reaudit-20260817-r3/general-native-20260817-1013.jpeg`,
  `.artifacts/vibe-island-reaudit-20260817-r3/notifications-native-20260817-1014.jpeg`.
- Fresh native Perch states from the exact local build:
  `.artifacts/perch-local-reaudit-20260817-r2/current/native-rest-20260817-1008.jpeg`,
  `.artifacts/perch-local-reaudit-20260817-r2/current/native-detailed-20260817-1009.jpeg`,
  `.artifacts/perch-local-reaudit-20260817-r2/current/native-clean-restored-20260817-1011.jpeg`.
- Post-correction local build captures:
  `.artifacts/perch-local-reaudit-20260817-r2/current/display-native-20260817-1015.jpeg`,
  `.artifacts/perch-local-reaudit-20260817-r2/current/native-final-rest-20260817-1017.jpeg` and
  `.artifacts/perch-local-reaudit-20260817-r2/current/native-final-expanded-20260817-1018.jpeg`.
- Final preview/morph captures after the last UI correction:
  `.artifacts/perch-local-reaudit-20260817-r2/current/display-final-native-20260817-1022.jpeg`,
  `.artifacts/perch-local-reaudit-20260817-r2/current/native-final-rest-20260817-1023.jpeg`,
  `.artifacts/perch-local-reaudit-20260817-r2/current/native-final-expanded-20260817-1024.jpeg`.

- Perch settings re-audit used the exact local binary
  `apps/mac/build.noindex/Perch.app`; the separately installed
  `/Applications/Perch.app` is an older binary and is not valid evidence for the
  current source tree.

The second extraction was performed from the installed Vibe bundle without changing
either application. It confirms a native AppKit/SwiftUI island with
`NotchViewModel`, `NotchWindowController`, `ContentHeightPreferenceKey`, and explicit
collapsed/expanded status symbols. The static inventory also contains the interaction
preferences behind hover delay, mouse-leave collapse, completion dwell, usage-threshold
peeks, and child-agent attention reminders. Those are runtime comparison targets;
commercial pass/licence surfaces remain intentionally out of scope.

All captures were made through native macOS accessibility and Computer Use.

## Main island

| Contract | Vibe 1.0.44 | Perch | Status |
|---|---|---|---|
| Host canvas | 680×580 | 680×580 | Matched |
| Visible body width | 650 pt | 650 pt | Matched |
| Compact content | pixel glyphs, short activity/title, count | pixel glyphs, short activity/title, count | Matched on the local build |
| Session heading | project and user task | project and user task | Matched |
| Provider pills | provider, client, age | provider, client, age | Matched |
| Plan preview | three rows and overflow | three rows and overflow | Matched |
| Hook trust | trusted on reference install | explicit actionable warning until user trusts hooks | Real state difference |
| Extra sessions | hidden behind expired-trial cap | visible without commercial cap | Product-model difference |
| Commercial CTA | expired-trial unlock row | absent | Missing legitimate licensing backend |

## Onboarding environment

The flow now changes presentation in the same place as Vibe: full-screen welcome
and demo, followed by a rounded 460×580 configuration window. The card has the
same six agent switches, terminal/IDE pills, launch-at-login option, fixed Next
button and pagination. Agent switches were exercised through native accessibility
and alter the installer selection that is submitted by Next.

The next live Vibe step is the commercial license card: three device tiers,
purchase, trial and existing-key actions. Perch has no legitimate merchant or
license service, so this remains documented rather than represented by a fake
working checkout.

The Display settings comparison also confirms the same sidebar, compact/detailed
previews, screen picker, font/height/width controls and session-card switches.
The local build no longer exposes NavigationSplitView's extra toolbar button. Its
expanded height now follows painted content: clean mode does not reserve hidden
transcript/task rows, while detailed mode remains scrollable and capped on-screen.
Vibe's extracted strings identify Clean as the narrow default; Perch now uses the same
default for fresh and legacy preference files that have no explicit layout choice.

The Sound comparison is now also native-equivalent: both panes expose the same
single `Activer les effets sonores` switch, with the current profile left off.
Perch no longer exposes NavigationSplitView's automatic sidebar-toolbar button,
which Vibe does not show.

The fresh native Accessibility tree confirms the same Display defaults: Clean selected,
11pt content, 90pt completion card, 560pt maximum height, 640pt maximum width,
project/worktree on, model/reasoning off, tasks/subagents/activity on. The local
settings tree and screenshot now show the same selection and controls.
The settings cadence was then adjusted against the native screenshots: each sizing row
now keeps Vibe's 73pt rhythm instead of pulling the following “Session Card” section
into the viewport early.

## Resource contract

Vibe bundles a Departure Mono resource alongside the onboarding wallpaper and
ceremony sound, six platform hook binaries, provider artwork, ten localizations
and commercial pricing/configuration data. Binary inspection shows that the
Island Bar itself resolves SwiftUI's system monospaced/default/rounded designs;
Perch now follows that runtime typography while keeping its own hook/runtime
assets and no commercial licensing subsystem.

The onboarding report now uses a dedicated `VibeIslandReference.icns` resource for
the small black/silver reference badge; Perch's actual `AppIcon.icns` remains unchanged.

## Remaining proof gates

- approve Perch through Codex's own trust UI;
- exercise a real SSH host and every advertised CLI end to end;
- verify Bark delivery on a real device with explicit authorization;
- implement or consciously exclude the commercial Pass/licensing contract;
- add and visually review the eight missing Vibe localizations;
- use only distributable creative assets with documented provenance;
- sign, notarize and smoke-test an authorized release artifact.

The latest native Computer Use pass also verified the compact-to-expanded click
transition and return to the resting pill on the exact local build. The source
animation remains centralized in `UI/Motion.swift`; no claim is made here that
every Vibe animation curve is byte-identical.

The follow-up Vibe main-island capture is gated behind its commercial onboarding card;
the card was only observed and then the app was quit. No licence or purchase control
was activated.

## 2026-08-17 re-audit: focused detailed card

The local debug bundle was rebuilt and relaunched through native Computer Use after the
second `workflow-rev` extraction. The expanded panel now follows Vibe's visible order:
usage header, one focused session, live activity line, bounded task board (three rows plus
overflow), then secondary trust status. Additional sessions remain behind an explicit
show-all action instead of competing with the focused card. The trust action remains
available but is compact so it does not displace the work surface.

The task board no longer uses the former 33pt spacer/negative offset, and the expanded
height is calculated from the painted detailed card rather than reserving hidden content.
The native capture stayed inside the 680pt canvas with no spill beyond the rounded panel.
Codex rollout prompts and activity are filtered when they are Computer Use orchestration
code, preventing internal control text from appearing as user-facing Island content.

The native comparison intentionally leaves Vibe's purchase/licence unlock card untouched,
as requested; no checkout, trial, key, or commercial bypass was used.
