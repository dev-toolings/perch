# Vibe Island — static extraction

- **Date**: 2026-08-17
- **Path**: `/Applications/Vibe Island.app`
- **Detected kind**: `macos-native` — macOS bundle without app.asar (native binary)
- **Bundle size**: `84M`

## Code signature & entitlements

```
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>com.apple.security.automation.apple-events</key><true/></dict></plist>

```

## Linked libraries (otool -L)

```
/Applications/Vibe Island.app/Contents/MacOS/vibe-island (architecture x86_64):
	/usr/lib/libc++.1.dylib (compatibility version 1.0.0, current version 2000.63.0)
	@rpath/Sparkle.framework/Versions/B/Sparkle (compatibility version 1.6.0, current version 2.8.1)
	/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation (compatibility version 300.0.0, current version 4109.1.255)
	/usr/lib/libobjc.A.dylib (compatibility version 1.0.0, current version 228.0.0)
	/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1356.0.0)
	/System/Library/Frameworks/AVFAudio.framework/Versions/A/AVFAudio (compatibility version 1.0.0, current version 1.0.0)
	/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit (compatibility version 45.0.0, current version 2685.20.119)
	/System/Library/Frameworks/ApplicationServices.framework/Versions/A/ApplicationServices (compatibility version 1.0.0, current version 66.0.0)
	/System/Library/Frameworks/Carbon.framework/Versions/A/Carbon (compatibility version 2.0.0, current version 170.0.0)
	/System/Library/Frameworks/ColorSync.framework/Versions/A/ColorSync (compatibility version 1.0.0, current version 3813.1.2)
	/System/Library/Frameworks/Combine.framework/Versions/A/Combine (compatibility version 1.0.0, current version 3023.0.0)
	/System/Library/Frameworks/CoreAudio.framework/Versions/A/CoreAudio (compatibility version 1.0.0, current version 1.0.0)
	/System/Library/Frameworks/CoreData.framework/Versions/A/CoreData (compatibility version 1.0.0, current version 1522.1.0)
	/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation (compatibility version 150.0.0, current version 4109.1.255)
	/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics (compatibility version 64.0.0, current version 1965.1.4)
	/System/Library/Frameworks/CoreImage.framework/Versions/A/CoreImage (compatibility version 1.0.1, current version 7.0.0)
	/System/Library/Frameworks/CoreServices.framework/Versions/A/CoreServices (compatibility version 1.0.0, current version 1226.0.0)
	/System/Library/Frameworks/CryptoKit.framework/Versions/A/CryptoKit (compatibility version 1.0.0, current version 1.0.0)
	/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit (compatibility version 1.0.0, current version 275.0.0)
	/System/Library/Frameworks/MetricKit.framework/Versions/A/MetricKit (compatibility version 1.0.0, current version 1.0.0, weak)
	/System/Library/Frameworks/Network.framework/Versions/A/Network (compatibility version 1.0.0, current version 5569.41.1)
	/System/Library/Frameworks/QuartzCore.framework/Versions/A/QuartzCore (compatibility version 1.2.0, current version 1193.39.8)
	/System/Library/Frameworks/Security.framework/Versions/A/Security (compatibility version 1.0.0, current version 61901.40.77)
	/System/Library/Frameworks/ServiceManagement.framework/Versions/A/ServiceManagement (compatibility version 1.0.0, current version 3089.41.2)
	/System/Library/Frameworks/SwiftUI.frame
…(truncated)…
```

## Mach-O header (otool -hv)

```
/Applications/Vibe Island.app/Contents/MacOS/vibe-island (architecture x86_64):
Mach header
      magic  cputype cpusubtype  caps    filetype ncmds sizeofcmds      flags
MH_MAGIC_64   X86_64        ALL  0x00     EXECUTE    74       9056   NOUNDEFS DYLDLINK TWOLEVEL WEAK_DEFINES BINDS_TO_WEAK PIE
/Applications/Vibe Island.app/Contents/MacOS/vibe-island (architecture arm64):
Mach header
      magic  cputype cpusubtype  caps    filetype ncmds sizeofcmds      flags
MH_MAGIC_64    ARM64        ALL  0x00     EXECUTE    74       9056   NOUNDEFS DYLDLINK TWOLEVEL WEAK_DEFINES BINDS_TO_WEAK PIE

```

## Architecture slices (lipo -info)

```
Architectures in the fat file: /Applications/Vibe Island.app/Contents/MacOS/vibe-island are: x86_64 arm64
```

## URLs & hosts found in binary

```
admission.app
ai.opencode.desktop
analytics.app
analytics.co
antigravity.app/contents/
api.minimaxi.com
app.hang.event
app.supabit.supacode
app.vibeisland.audio
app.vibeisland.audio-output-observer
app.vibeisland.ceremony-audio
app.vibeisland.cursor-conversation-jump
app.vibeisland.focus
app.vibeisland.macos
app.vibeisland.terminal-title-preference
approval.co
approval.detail.moreLines
approval.detail.newFile
arrow.co
arrow.down.circle
arrow.triangle.2
arrow.triangle.branch
arrow.up.circle
arrow.up.right
aseo.app
ath.co
auto.app.start
auto.db.core_data
auto.file.ns_data
auto.http.ns_url_session
auto.ui.event_tracker
auto.ui.time_to_display
auto.ui.view_controller
bubble.left.and
bubble.right.fill
bypass.active.label
chatgpt.com/codex/settings/usage
checkmark.circle.fill
checkmark.seal.fill
checkmark.sh
checkmark.square.fill
child.stdin.end
child.stdin.on
clock.arrow.circlepath
clock.badge.exclamationmark
cn.qwenwork.desktop
codex.approval.allowForAllSites
codex.approval.allowThisConversation
codex.approval.bypassThisTurn
com.aliyun.lingma
com.anthropic.claudefordesktop
com.apple.Terminal
com.apple.donotdisturb
com.apple.focus
com.apple.malware
com.apple.preference
com.apple.quarantine
com.apple.screenIsLocked
com.apple.screenIsUnlocked
com.apple.screensaver
com.apple.sleep
com.apple.symbolichotkeys
com.cmuxterm.app
com.codepilot.app
com.conductor.app
com.exafunction.windsurf
com.github.wez
com.google.android
com.google.antigravity
com.google.gemini
com.googlecode.iterm2
com.grluo.vibe-island
com.jetbrains.CLion
com.jetbrains.DataSpell
com.jetbrains.PhpStorm
com.jetbrains.WebStorm
com.jetbrains.aqua
com.jetbrains.datagrip
com.jetbrains.goland
com.jetbrains.intellij
com.jetbrains.pycharm
com.jetbrains.rider
com.jetbrains.rubymine
com.jetbrains.rustrover
com.lukilabs.craft-agent
com.microsoft.VSCode
com.microsoft.VSCodeInsiders
com.mitchellh.ghostty
com.openai.codex
com.qoder.ide
com.qoder.work
com.stablyai.orca
com.steipete.codexbar
com.superfluous.vibe-island
com.superset.desktop
com.todesktop.230313mzl4w4u92
com.vibeisland.claude-desktop-code-jump
com.vibeisland.codex-approval-owner-monitor
com.vibeisland.codex-approval-owner-transaction
com.vibeisland.codex-approval-transport
com.vibeisland.codex-question-transport
com.vibeisland.codex-thread-jump
com.vibeisland.terminal-jump
command.app
composer.com
config.json.backup
config.json.lock
config.toml.backup
context.app
context.subscriptions.push
cowork.option.count
cursorarrow.click.2
db.sql.query
db.sql.transaction
description.co
design.desktop.beta
design.desktop.betas
design.desktop.prerelease
design.desktop.preview
dev.kiro.desktop
dev.warp.Warp-Preview
dev.warp.Warp-Stable
dev.zcode.app
device.co
edition.title.explorer
edition.title.founder
edition.title.islander
edition.title.pioneer
edition.title.voyager
eminder.com
emote.co
emote.com
emote.disclosure.docker
emote.disclosure.manual
emote.docker.intro
emote.docker.local
emote.docker.location
emote.docker.pasteInContainer
emote.docker.platform
emote.docker.remote
emote.docker.rerun
emote.field.alias
emote.field.host
emote.field.hostPlaceholder
emote.field.sshOptions
emote.field.user
emote.field.userPlaceholder
emote.manual.airgapFallback
emote.manual.airgapIntro
emote.manual.clickDeploy
emote.manual.pickPlatform
emote.manual.runOnRemote
emote.manual.scpBlocked
emote.manual.thenOnRemote
emote.manual.transport
emote.option.jump
emote.option.key
emote.option.mfa
emote.option.port
emote.option.proxyCommand
emote.qoder.upgradeRequired
emote.qoder.versionUnverified
emote.tunnel.connected
emote.tunnel.connectedAgo
emote.tunnel.connecting
emote.tunnel.disconnected
emote.tunnel.error
emote.tunnel.reconnecting
emote.usage.claude
emote.usage.codex
emote.usage.hint
emote.usage.status
emote.usage.title
erm.app
erminal.app
event.app
evin.app
exclamationmark.circle.fill
exclamationmark.octagon.fill
exclamationmark.shield.fill
exclamationmark.triangle.fill
extra.co
file.co
file.play.failed
file.play.started
folder.badge.plus
folder.uri.fsP
…(truncated)…
```

## Inventory & strings

- `inventory/tree_d3.txt`
- `inventory/extensions_top30.txt`
- `strings/urls.txt`
- `strings/vibe-island.strings.txt`

---
_Generated by `workflow-rev decompile`._
