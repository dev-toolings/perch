import Foundation
import Testing

@testable import PerchKit

@Test func iTermJumpsToTheExactSession() {
    let plan = TerminalJump.plan(
        for: ClientInfo(terminal: "iTerm.app", session: "w0t1p0:ABC-123"))

    #expect(plan.target == .iTerm(bundleId: "com.googlecode.iterm2", session: "w0t1p0:ABC-123"))
    let script = try! #require(TerminalJump.script(for: plan.target))
    #expect(script.contains("\"w0t1p0:ABC-123\""))
    #expect(script.contains("tell application \"iTerm2\""))
}

/// Terminal.app shares no session id with the process inside it, but every tab exposes its
/// tty — which is why the hook captures one.
@Test func terminalAppJumpsByTty() {
    let plan = TerminalJump.plan(
        for: ClientInfo(terminal: "Apple_Terminal", tty: "/dev/ttys004"))

    #expect(plan.target == .appleTerminal(bundleId: "com.apple.Terminal", tty: "/dev/ttys004"))
    #expect(TerminalJump.script(for: plan.target)?.contains("tty of t is \"/dev/ttys004\"") == true)
}

/// Without the precise handle we can still bring the window forward. Pretending otherwise
/// would mean doing nothing at all.
@Test func fallsBackToActivatingTheApp() {
    #expect(
        TerminalJump.plan(for: ClientInfo(terminal: "ghostty")).target
            == .activate(bundleId: "com.mitchellh.ghostty"))
    #expect(
        TerminalJump.plan(for: ClientInfo(terminal: "iTerm.app")).target
            == .activate(bundleId: "com.googlecode.iterm2"))
    #expect(TerminalJump.script(for: .activate(bundleId: "x")) == nil)
}

/// VS Code and its forks each register their own scheme and each need their own copy of
/// the extension — they do not share an extension host.
@Test func editorsAreReachedThroughTheirOwnURIScheme() throws {
    let code = TerminalJump.plan(
        for: ClientInfo(terminal: "vscode", tty: "/dev/ttys004"))
    #expect(
        code.target
            == .editorURI(
                bundleId: "com.microsoft.VSCode", scheme: "vscode", tty: "/dev/ttys004"))

    let url = try #require(TerminalJump.editorURL(for: code.target))
    #expect(url.absoluteString == "vscode://kweli.perch-jump/focus?tty=/dev/ttys004")
    #expect(code.summary == "Jump to VS Code")

    let cursor = TerminalJump.plan(
        for: ClientInfo(terminal: "cursor", tty: "/dev/ttys001"))
    #expect(TerminalJump.editorURL(for: cursor.target)?.scheme == "cursor")
}

/// Without a tty there is nothing to hand the extension, so it falls back to the window.
@Test func anEditorWithoutATtyFallsBackToActivating() {
    let plan = TerminalJump.plan(for: ClientInfo(terminal: "vscode"))
    #expect(plan.target == .activate(bundleId: "com.microsoft.VSCode"))
    #expect(TerminalJump.editorURL(for: plan.target) == nil)
}

/// kitty and WezTerm ship remote control, which is both more precise and less fragile than
/// driving them through AppleScript they do not implement.
@Test func kittyAndWezTermAreDrivenByTheirOwnCli() {
    #expect(
        TerminalJump.plan(for: ClientInfo(terminal: "kitty", session: "42")).target
            == .remoteControl(
                bundleId: "net.kovidgoyal.kitty", executable: "kitty",
                arguments: ["@", "focus-window", "--match", "id:42"]))

    #expect(
        TerminalJump.plan(for: ClientInfo(terminal: "WezTerm", session: "7")).target
            == .remoteControl(
                bundleId: "com.github.wez.wezterm", executable: "wezterm",
                arguments: ["cli", "activate-pane", "--pane-id", "7"]))
}

/// Without the window or pane id there is nothing to address, so it falls back.
@Test func remoteControlNeedsAnIdToAddress() {
    #expect(
        TerminalJump.plan(for: ClientInfo(terminal: "kitty")).target
            == .activate(bundleId: "net.kovidgoyal.kitty"))
    #expect(TerminalJump.script(for: .remoteControl(bundleId: "x", executable: "y", arguments: [])) == nil)
}

@Test func unknownOrMissingHostsCannotBeJumpedTo() {
    #expect(TerminalJump.plan(for: nil).target == .unavailable)
    #expect(TerminalJump.plan(for: ClientInfo()).target == .unavailable)
    #expect(TerminalJump.plan(for: ClientInfo(terminal: "some-new-terminal")).target == .unavailable)
    #expect(!TerminalJump.plan(for: nil).isPossible)
}

/// The pane survives even when the terminal itself cannot be identified — reaching the
/// right tmux pane is still worth doing.
@Test func tmuxPaneIsCarriedAlongside() {
    let plan = TerminalJump.plan(
        for: ClientInfo(terminal: "ghostty", tmuxPane: "%7"))
    #expect(plan.tmuxPane == "%7")
    #expect(TerminalJump.plan(for: ClientInfo(tmuxPane: "%7")).tmuxPane == "%7")
}

/// A session id ends up inside an AppleScript string literal, so it must not be able to
/// close the quote.
@Test func scriptLiteralsAreEscaped() {
    #expect(TerminalJump.escape(#"a"b"#) == #"a\"b"#)
    #expect(TerminalJump.escape(#"a\b"#) == #"a\\b"#)

    let plan = TerminalJump.plan(
        for: ClientInfo(terminal: "iTerm.app", session: #"x" & do shell script "boom"#))
    let script = try! #require(TerminalJump.script(for: plan.target))
    #expect(!script.contains(#"is "x" & do shell script"#))
}

@Test func summariesSayWhereTheClickGoes() {
    #expect(TerminalJump.plan(for: ClientInfo(terminal: "iTerm.app", session: "s")).summary == "Jump to iTerm")
    #expect(TerminalJump.plan(for: ClientInfo(terminal: "ghostty")).summary == "Open Ghostty")
    #expect(TerminalJump.plan(for: nil).summary == "No terminal recorded")
}

/// cmux embeds libghostty and says so: `TERM_PROGRAM=ghostty` inside it sent every jump to
/// Ghostty.app, which is a different application and usually not even installed. Its own
/// panel id is the handle, and `focus-panel` selects the workspace on the way there.
@Test func cmuxIsRecognisedThroughGhosttyAndJumpsToItsPanel() {
    let client = ClientInfo.fromEnvironment([
        "TERM_PROGRAM": "ghostty",
        "CMUX_PANEL_ID": "E0F14FC6-2455",
        "CMUX_WORKSPACE_ID": "30A257B6-DFBA",
        "CMUX_BUNDLE_ID": "com.cmuxterm.app",
        "__CFBundleIdentifier": "com.cmuxterm.app",
    ])

    #expect(client.terminal == "cmux")
    #expect(client.displayName == "cmux")
    #expect(client.session == "E0F14FC6-2455")

    let plan = TerminalJump.plan(for: client)
    #expect(
        plan.target
            == .remoteControl(
                bundleId: "com.cmuxterm.app", executable: "cmux",
                arguments: ["focus-panel", "--panel", "E0F14FC6-2455"]))
    #expect(plan.summary == "Jump to cmux")
}

/// A cmux old enough to export only the surface id still jumps: it is the same handle
/// under the name it had first.
@Test func cmuxFallsBackToTheSurfaceId() {
    let client = ClientInfo.fromEnvironment([
        "TERM_PROGRAM": "ghostty", "CMUX_SURFACE_ID": "AAA-111",
    ])
    #expect(client.session == "AAA-111")
    #expect(TerminalJump.plan(for: client).isPossible)
}

/// Ghostty on its own is still Ghostty. The cmux branch must not swallow it.
@Test func plainGhosttyIsUntouched() {
    let client = ClientInfo.fromEnvironment(["TERM_PROGRAM": "ghostty"])
    #expect(client.terminal == "ghostty")
    #expect(
        TerminalJump.plan(for: client).target == .activate(bundleId: "com.mitchellh.ghostty"))
}

/// Codex Desktop is not a terminal — there is no tty and no pane to aim at. What there is
/// is a thread id, which the app addresses directly, so the click lands on the
/// conversation rather than on the application.
@Test func codexDesktopJumpsToItsThread() {
    let live = CodexSessions.Live(
        id: "019ff83d-ed8e-7df0-baaa-7b28491263d4",
        cwd: "/Users/kevin/lab/kit-cgp", originator: "Codex Desktop")
    let client = try! #require(live.client)

    #expect(client.displayName == "Codex app")
    let plan = TerminalJump.plan(for: client)
    #expect(
        plan.target
            == .deepLink(
                bundleId: "com.openai.codex",
                url: "codex://threads/019ff83d-ed8e-7df0-baaa-7b28491263d4"))
    #expect(plan.summary == "Jump to Codex app")
}

/// A Codex running in a terminal has no app to open, and guessing one would send the
/// click to a window that is not the session. The terminal's own hook reports that case.
@Test func theCodexCLIIsNotTheDesktopApp() {
    let cli = CodexSessions.Live(id: "abc", originator: "codex_cli_rs")
    #expect(cli.client == nil)
    #expect(CodexSessions.Live(id: "abc", originator: nil).client == nil)
}

/// Superset claims to be kitty — `TERM_PROGRAM=kitty`, version and all — and believing it
/// would run `kitty @` against an app that is not installed. Its own variables win, and
/// its deep link is pane-precise without any CLI.
@Test func supersetIsCaughtBeforeItsKittyDisguise() {
    let client = ClientInfo.fromEnvironment([
        "TERM_PROGRAM": "kitty",
        "SUPERSET_PANE_ID": "pane-42",
        "SUPERSET_WORKSPACE_ID": "ws-7",
    ])
    #expect(client.terminal == "Superset")
    #expect(
        TerminalJump.plan(for: client).target
            == .deepLink(
                bundleId: "com.superset.desktop",
                url: "superset://v2-workspace/ws-7?terminalId=pane-42"))
}

/// Warp hands over its own focus URL and Perch passes it on untouched — the preview
/// channel uses another scheme, so the variable is the contract, not the string.
@Test func warpJumpsThroughItsOwnFocusURL() {
    let client = ClientInfo.fromEnvironment([
        "TERM_PROGRAM": "WarpTerminal",
        "WARP_FOCUS_URL": "warp://session/abc123",
    ])
    #expect(
        TerminalJump.plan(for: client).target
            == .deepLink(bundleId: "dev.warp.Warp-Stable", url: "warp://session/abc123"))

    // Without the URL, Warp is what it was: an app to bring forward.
    let plain = ClientInfo.fromEnvironment(["TERM_PROGRAM": "WarpTerminal"])
    #expect(TerminalJump.plan(for: plain).target == .activate(bundleId: "dev.warp.Warp-Stable"))
}

/// Wave's `wsh focusblock` takes the block on argv and the tab from the environment, so
/// the tab rides in front of the command the way `/usr/bin/env` expects it.
@Test func waveFocusesItsBlockWithTheTabInTheEnvironment() {
    let client = ClientInfo.fromEnvironment([
        "TERM_PROGRAM": "waveterm",
        "WAVETERM_BLOCKID": "block-1",
        "WAVETERM_TABID": "tab-9",
    ])
    #expect(client.displayName == "Wave")
    #expect(
        TerminalJump.plan(for: client).target
            == .remoteControl(
                bundleId: "dev.commandline.waveterm",
                executable: "WAVETERM_TABID=tab-9",
                arguments: ["wsh", "focusblock", "-b", "block-1"]))
}

/// JetBrains sets no TERM_PROGRAM at all — the launcher is the only signal, and it is
/// enough to bring the IDE forward and put a name on the chip.
@Test func aLauncherAloneIsStillSomewhereToLand() {
    let client = ClientInfo.fromEnvironment([
        "TERMINAL_EMULATOR": "JetBrains-JediTerm",
        "__CFBundleIdentifier": "com.jetbrains.WebStorm",
    ])
    #expect(client.displayName == "WebStorm")
    #expect(
        TerminalJump.plan(for: client).target
            == .activate(bundleId: "com.jetbrains.WebStorm"))

    // Finder launches half the processes on a Mac and is never where a session lives.
    let finder = ClientInfo.fromEnvironment(["__CFBundleIdentifier": "com.apple.Finder"])
    #expect(finder.displayName == nil)
    #expect(TerminalJump.plan(for: finder).target == .unavailable)
}

/// zellij and screen stack on the host terminal exactly as tmux does: focus the app, then
/// tell the multiplexer which pane the click meant.
@Test func multiplexersRideAlongAsFollowUps() {
    let zellij = ClientInfo.fromEnvironment([
        "TERM_PROGRAM": "ghostty",
        "ZELLIJ_PANE_ID": "terminal_3",
        "ZELLIJ_SESSION_NAME": "main",
    ])
    #expect(
        TerminalJump.plan(for: zellij).followUps
            == [["ZELLIJ_SESSION_NAME=main", "zellij", "action", "focus-pane-id", "terminal_3"]])

    let screen = ClientInfo.fromEnvironment([
        "TERM_PROGRAM": "iTerm.app",
        "ITERM_SESSION_ID": "w0t0p0:X",
        "STY": "12345.pts-0.host",
        "WINDOW": "2",
    ])
    #expect(
        TerminalJump.plan(for: screen).followUps
            == [["screen", "-S", "12345.pts-0.host", "-X", "select", "2"]])
}

/// Conductor names itself only through its own variables; there is no focus deep link, so
/// activating the app is the honest ceiling.
@Test func conductorIsRecognisedByItsOwnVariables() {
    let client = ClientInfo.fromEnvironment([
        "CONDUCTOR_WORKSPACE_PATH": "/Users/x/repo",
        "CONDUCTOR_SESSION_ID": "sess-1",
    ])
    #expect(client.terminal == "Conductor")
    #expect(TerminalJump.plan(for: client).target == .activate(bundleId: "com.conductor.app"))
}
