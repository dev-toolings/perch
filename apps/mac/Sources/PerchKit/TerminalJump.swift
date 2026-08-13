import Foundation

/// Where a click on a session card should take you.
///
/// Deciding this is pure — which terminal, which handle, whether we can be precise — so it
/// is testable without driving a single AppleEvent. Executing it is not, and lives in the
/// app.
public enum JumpTarget: Equatable, Sendable {
    /// iTerm2 addresses sessions by id, so this lands on the exact split pane.
    case iTerm(bundleId: String, session: String)
    /// Terminal.app exposes `tty` on every tab, which is the only handle it shares with
    /// the process running inside it.
    case appleTerminal(bundleId: String, tty: String)
    /// VS Code and its forks answer a URI, which is how an outside app reaches one tab
    /// among a dozen. Needs the Perch extension installed in that editor.
    case editorURI(bundleId: String, scheme: String, tty: String)
    /// An app that answers a URL of its own. Codex Desktop is the case this exists for:
    /// it is not a terminal at all, so there is no tty and no pane — but every thread has
    /// an address, and that is a more precise landing than any terminal gives.
    case deepLink(bundleId: String, url: String)
    /// kitty and WezTerm ship their own remote control. Running their CLI is both more
    /// precise and less fragile than driving them through AppleScript they do not support.
    case remoteControl(bundleId: String, executable: String, arguments: [String])
    /// Everything else: bring the app forward. Honest about being window-level — the
    /// per-app remote-control paths (kitty, wezterm) come later.
    case activate(bundleId: String)
    /// Nothing was captured — a session started before Perch, or a host we do not know.
    case unavailable
}

public struct JumpPlan: Equatable, Sendable {
    public var target: JumpTarget
    /// Run after the terminal is focused: inside tmux the visible pane is tmux's choice,
    /// not the terminal's.
    public var tmuxPane: String?
    /// The other multiplexers, as argv lists for `/usr/bin/env` — zellij and screen do the
    /// same job as tmux with different words, and a list keeps the executor from growing a
    /// case per dialect. Best-effort like everything here: a wrong pane id is a command
    /// that errors into a log line, not a dialog.
    public var followUps: [[String]] = []

    public var isPossible: Bool { target != .unavailable }

    /// What the UI says it will do, so a click never surprises anyone.
    public var summary: String {
        switch target {
        case .iTerm: return "Jump to iTerm"
        case .appleTerminal: return "Jump to Terminal"
        case .editorURI(let bundleId, _, _), .remoteControl(let bundleId, _, _),
            .deepLink(let bundleId, _):
            return "Jump to \(TerminalJump.name(forBundle: bundleId))"
        case .activate(let bundleId): return "Open \(TerminalJump.name(forBundle: bundleId))"
        case .unavailable: return "No terminal recorded"
        }
    }
}

public enum TerminalJump {
    /// `TERM_PROGRAM` values, as their hosts set them, mapped to bundle identifiers.
    public static let bundleIds: [String: String] = [
        "iTerm.app": "com.googlecode.iterm2",
        "Apple_Terminal": "com.apple.Terminal",
        "ghostty": "com.mitchellh.ghostty",
        "Ghostty": "com.mitchellh.ghostty",
        "cmux": "com.cmuxterm.app",
        // Not a terminal, and it never sets `TERM_PROGRAM` — Perch labels its sessions
        // itself, off the `originator` its rollouts carry.
        "Codex Desktop": "com.openai.codex",
        // Agent managers, labelled from their own variables (see `fromEnvironment`).
        // Superset's TERM_PROGRAM says kitty, which is why it must never get this far
        // under that name.
        "Superset": "com.superset.desktop",
        "Conductor": "com.conductor.app",
        "Orca": "com.stablyai.orca",
        "waveterm": "dev.commandline.waveterm",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "WezTerm": "com.github.wez.wezterm",
        "kitty": "net.kovidgoyal.kitty",
        "alacritty": "org.alacritty",
        "Alacritty": "org.alacritty",
        "Hyper": "co.zeit.hyper",
        "tabby": "org.tabby",
        "rio": "com.raphaelamorim.rio",
        "vscode": "com.microsoft.VSCode",
        "cursor": "com.todesktop.230313mzl4w4u92",
        "windsurf": "com.exafunction.windsurf",
        "zed": "dev.zed.Zed",
        "Zed": "dev.zed.Zed",
    ]

    private static let displayNames: [String: String] = [
        "com.googlecode.iterm2": "iTerm",
        "com.apple.Terminal": "Terminal",
        "com.mitchellh.ghostty": "Ghostty",
        "com.cmuxterm.app": "cmux",
        // "Codex app", not "Codex": the card already wears a Codex badge for the agent,
        // and two chips reading the same word say nothing about where the click lands.
        "com.openai.codex": "Codex app",
        "dev.warp.Warp-Stable": "Warp",
        "com.github.wez.wezterm": "WezTerm",
        "net.kovidgoyal.kitty": "kitty",
        "org.alacritty": "Alacritty",
        "com.microsoft.VSCode": "VS Code",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.exafunction.windsurf": "Windsurf",
        "dev.zed.Zed": "Zed",
        "com.superset.desktop": "Superset",
        "com.superset.desktop.canary": "Superset",
        "com.conductor.app": "Conductor",
        "com.stablyai.orca": "Orca",
        "dev.commandline.waveterm": "Wave",
        "com.nimbalyst.electron": "Nimbalyst",
        "com.google.antigravity": "Antigravity",
        "dev.kiro.desktop": "Kiro",
    ]

    /// URL schemes the editors register. Perch's extension answers
    /// `<scheme>://kweli.perch-jump/focus?tty=…` inside whichever one is running.
    static let editorSchemes: [String: String] = [
        "com.microsoft.VSCode": "vscode",
        "com.todesktop.230313mzl4w4u92": "cursor",
        "com.exafunction.windsurf": "windsurf",
    ]

    public static func name(forBundle bundleId: String) -> String {
        if let known = displayNames[bundleId] { return known }
        // "com.jetbrains.WebStorm" reads as "WebStorm" on a chip; the raw id reads as a
        // bug. The last segment is the app's own choice of name often enough to be the
        // right guess, and it is only ever a label — the id itself is what gets activated.
        let tail = bundleId.split(separator: ".").last.map(String.init) ?? bundleId
        return tail.first?.isUppercase == true ? tail : tail.capitalized
    }

    /// Whether `__CFBundleIdentifier` names something worth jumping to.
    ///
    /// Finder, the Dock and loginwindow launch half the processes on a Mac, and none of
    /// them is where an agent's terminal lives — Terminal.app is, and `TERM_PROGRAM`
    /// already covers it. Everything non-Apple that launches an agent is, by that fact
    /// alone, the application to bring forward.
    public static func isUsableLauncher(_ bundleId: String) -> Bool {
        !bundleId.isEmpty && !bundleId.hasPrefix("com.apple.")
    }

    /// The URI that focuses the right tab, once the extension is installed there.
    public static func editorURL(for target: JumpTarget) -> URL? {
        guard case .editorURI(_, let scheme, let tty) = target else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "kweli.perch-jump"
        components.path = "/focus"
        components.queryItems = [URLQueryItem(name: "tty", value: tty)]
        return components.url
    }

    /// Which app hosts this session, when we can tell.
    public static func bundleId(for client: ClientInfo?) -> String? {
        client?.terminal.flatMap { bundleIds[$0] }
    }

    public static func plan(for client: ClientInfo?) -> JumpPlan {
        let followUps = multiplexerFollowUps(for: client)
        guard let client, let terminal = client.terminal,
            let bundleId = bundleIds[terminal]
        else {
            // No terminal, or one Perch has never heard of — but the launcher may still
            // name the application this session lives in. JetBrains sets no TERM_PROGRAM
            // at all; the next Electron agent manager will not either. Activating the
            // launcher is the whole long tail covered by one line, and it costs nothing:
            // a launcher that is not jump-worthy (Finder, loginwindow) is filtered out.
            if let launcher = client?.launcher, isUsableLauncher(launcher) {
                return JumpPlan(
                    target: .activate(bundleId: launcher),
                    tmuxPane: client?.tmuxPane, followUps: followUps)
            }
            return JumpPlan(
                target: .unavailable, tmuxPane: client?.tmuxPane, followUps: followUps)
        }

        switch bundleId {
        case "com.googlecode.iterm2":
            // `w0t1p0:UUID` — iTerm's own session id, which its AppleScript dictionary
            // matches directly.
            if let session = client.session, !session.isEmpty {
                return JumpPlan(target: .iTerm(bundleId: bundleId, session: session),
                                tmuxPane: client.tmuxPane, followUps: followUps)
            }
        case "com.apple.Terminal":
            if let tty = client.tty, !tty.isEmpty {
                return JumpPlan(target: .appleTerminal(bundleId: bundleId, tty: tty),
                                tmuxPane: client.tmuxPane, followUps: followUps)
            }
        case "net.kovidgoyal.kitty":
            // `KITTY_WINDOW_ID` is set in every kitty window's environment, and remote
            // control addresses windows by exactly that id.
            if let id = client.session, !id.isEmpty {
                return JumpPlan(
                    target: .remoteControl(
                        bundleId: bundleId, executable: "kitty",
                        arguments: ["@", "focus-window", "--match", "id:\(id)"]),
                    tmuxPane: client.tmuxPane, followUps: followUps)
            }
        case "com.openai.codex":
            // Every Codex thread has an address the app itself uses — `{{ thread_url }}`
            // in its own share templates — and Perch already keys its Codex cards on the
            // root thread id, which is the one a subagent's rollout points back to. So the
            // click lands on the conversation, not merely on the application.
            if let thread = client.session, !thread.isEmpty {
                return JumpPlan(
                    target: .deepLink(bundleId: bundleId, url: "codex://threads/\(thread)"),
                    tmuxPane: nil)
            }
        case "com.cmuxterm.app":
            // `focus-panel` selects the workspace on its way to the panel, so one call
            // lands on the exact tab even when it is in another workspace entirely.
            if let panel = client.session, !panel.isEmpty {
                return JumpPlan(
                    target: .remoteControl(
                        bundleId: bundleId, executable: "cmux",
                        arguments: ["focus-panel", "--panel", panel]),
                    tmuxPane: client.tmuxPane, followUps: followUps)
            }
        case "com.github.wez.wezterm":
            // WezTerm needs no configuration for this — `wezterm cli` talks to the running
            // instance out of the box.
            if let pane = client.session, !pane.isEmpty {
                return JumpPlan(
                    target: .remoteControl(
                        bundleId: bundleId, executable: "wezterm",
                        arguments: ["cli", "activate-pane", "--pane-id", pane]),
                    tmuxPane: client.tmuxPane, followUps: followUps)
            }
        case "com.superset.desktop":
            // Superset's TERM_PROGRAM says kitty — the label never reaches this switch,
            // `fromEnvironment` renames it off its own variables. Its deep link is
            // pane-precise from a bare `open`, no CLI required.
            if let pane = client.session, !pane.isEmpty,
                let workspace = client.workspace, !workspace.isEmpty
            {
                return JumpPlan(
                    target: .deepLink(
                        bundleId: bundleId,
                        url: "superset://v2-workspace/\(workspace)?terminalId=\(pane)"),
                    tmuxPane: client.tmuxPane, followUps: followUps)
            }
        case "dev.warp.Warp-Stable":
            // `WARP_FOCUS_URL` arrives whole from Warp itself, and is passed on untouched:
            // the preview channel emits a different scheme, and the variable — not the
            // string inside it — is the contract.
            if let url = client.session, url.contains("://") {
                return JumpPlan(
                    target: .deepLink(bundleId: bundleId, url: url),
                    tmuxPane: client.tmuxPane, followUps: followUps)
            }
        case "dev.commandline.waveterm":
            // `wsh focusblock` addresses the block on argv but reads the tab from the
            // environment, so the tab rides in front of the command — `/usr/bin/env`
            // treats a leading NAME=value exactly as intended.
            if let block = client.session, !block.isEmpty,
                let tab = client.workspace, !tab.isEmpty
            {
                return JumpPlan(
                    target: .remoteControl(
                        bundleId: bundleId, executable: "WAVETERM_TABID=\(tab)",
                        arguments: ["wsh", "focusblock", "-b", block]),
                    tmuxPane: client.tmuxPane, followUps: followUps)
            }
        default:
            // VS Code and its forks each register their own scheme, and each needs its own
            // copy of the extension — they do not share an extension host.
            if let scheme = editorSchemes[bundleId], let tty = client.tty, !tty.isEmpty {
                return JumpPlan(
                    target: .editorURI(bundleId: bundleId, scheme: scheme, tty: tty),
                    tmuxPane: client.tmuxPane, followUps: followUps)
            }
        }

        return JumpPlan(
            target: .activate(bundleId: bundleId),
            tmuxPane: client.tmuxPane, followUps: followUps)
    }

    /// What still has to run after the host terminal is forward: the multiplexers, which
    /// choose the visible pane no matter what the terminal shows.
    ///
    /// tmux is not here — it predates this list and keeps its own field. zellij's
    /// cross-session addressing is undocumented, so the session name is injected the way
    /// zellij itself learns it, through the environment; if that guess misses, the command
    /// errors into a log line and the jump has still reached the right terminal.
    static func multiplexerFollowUps(for client: ClientInfo?) -> [[String]] {
        guard let client else { return [] }
        var followUps: [[String]] = []
        if let pane = client.zellijPane, !pane.isEmpty {
            var argv: [String] = []
            if let session = client.zellijSession, !session.isEmpty {
                argv.append("ZELLIJ_SESSION_NAME=\(session)")
            }
            argv.append(contentsOf: ["zellij", "action", "focus-pane-id", pane])
            followUps.append(argv)
        }
        if let session = client.screenSession, !session.isEmpty,
            let window = client.screenWindow, !window.isEmpty
        {
            followUps.append(["screen", "-S", session, "-X", "select", window])
        }
        return followUps
    }

    /// AppleScript that focuses the exact iTerm2 session, or does nothing if it has since
    /// been closed. Written to fail quietly: a jump that misses must not raise a dialog.
    public static func script(for target: JumpTarget) -> String? {
        switch target {
        case .iTerm(_, let session):
            let escaped = escape(session)
            return """
                tell application "iTerm2"
                  repeat with w in windows
                    repeat with t in tabs of w
                      repeat with s in sessions of t
                        if id of s is "\(escaped)" then
                          select w
                          select t
                          select s
                          activate
                          return
                        end if
                      end repeat
                    end repeat
                  end repeat
                  activate
                end tell
                """
        case .appleTerminal(_, let tty):
            let escaped = escape(tty)
            return """
                tell application "Terminal"
                  repeat with w in windows
                    repeat with t in tabs of w
                      if tty of t is "\(escaped)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return
                      end if
                    end repeat
                  end repeat
                  activate
                end tell
                """
        case .editorURI, .remoteControl, .deepLink, .activate, .unavailable:
            return nil
        }
    }

    /// AppleScript string literals only need these two escaped, and doing it by hand keeps
    /// a session id from ever being able to close the quote and inject.
    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
