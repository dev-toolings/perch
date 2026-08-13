import AppKit
import Foundation
import PerchKit

/// Executes a `JumpPlan`: brings the terminal forward and, where the host allows it,
/// selects the exact tab or split.
///
/// Everything here is best-effort by design. A jump that misses — the tab was closed, the
/// user never granted Automation — must leave the panel exactly as it was rather than
/// raising anything.
enum TerminalJumper {
    static func jump(to client: ClientInfo?) {
        let plan = TerminalJump.plan(for: client)
        // Every click leaves a line. The whole path below is deliberately silent on
        // failure, which is right for the person clicking and useless for whoever has to
        // find out why nothing happened — this line is for the second reader.
        PerchLog.info("jump: \(plan.summary) target=\(plan.target)")
        guard plan.isPossible else { return }

        // tmux first: the pane has to be current before the terminal is asked to show
        // itself, or you land on the window and watch it switch. The other multiplexers
        // follow the same rule for the same reason.
        if let pane = plan.tmuxPane { selectTmuxPane(pane) }
        for argv in plan.followUps where !argv.isEmpty {
            runTool(argv[0], Array(argv.dropFirst()))
        }

        switch plan.target {
        case .iTerm(let bundleId, _), .appleTerminal(let bundleId, _):
            activate(bundleId)
            if let script = TerminalJump.script(for: plan.target) { run(script) }
        case .editorURI(let bundleId, _, _):
            // Bring the editor forward first: a URI opened at a background app focuses the
            // tab in a window you cannot see.
            activate(bundleId)
            if let url = TerminalJump.editorURL(for: plan.target) {
                NSWorkspace.shared.open(url)
            }
        case .deepLink(let bundleId, var url):
            // Forward first, then the URL: an app that is not running answers the link on
            // launch, and one that is running answers it in a window you can see.
            activate(bundleId)
            // Superset dedupes identical links; a fresh request id makes the second click
            // on the same card focus again instead of being ignored. Added here rather
            // than in the plan, which stays deterministic for the tests.
            if url.hasPrefix("superset://") {
                url += "&focusRequestId=\(UUID().uuidString)"
            }
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
        case .remoteControl(let bundleId, let executable, let arguments):
            activate(bundleId)
            runTool(executable, arguments)
        case .activate(let bundleId):
            activate(bundleId)
        case .unavailable:
            break
        }
    }

    private static func activate(_ bundleId: String) {
        guard
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// AppleScript runs off the main actor: an unresponsive terminal would otherwise
    /// freeze the panel for as long as the event takes to time out.
    private static func run(_ script: String) {
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                PerchLog.error("jump failed: \(error)")
            }
        }
    }

    /// Runs a terminal's own remote-control CLI.
    ///
    /// `/usr/bin/env` rather than an absolute path: these are installed by Homebrew, by
    /// the app bundle, or by hand, and hard-coding one of those is how it works on the
    /// machine it was written on and nowhere else. A missing tool is silent — the window
    /// has already been brought forward, which is most of the jump.
    private static func runTool(_ executable: String, _ arguments: [String]) {
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            // Homebrew's paths are not in a GUI app's inherited PATH.
            var environment = ProcessInfo.processInfo.environment
            // Perch is not a terminal, but it can have been launched from one — `open`
            // propagates the caller's environment, and an app relaunched from a terminal
            // inherits that terminal's whole identity. The remote-control CLIs read it:
            // with a stale `CMUX_WORKSPACE_ID` in the environment, `focus-panel` resolves
            // only inside that one workspace and answers "Surface not found" for every
            // other tab — a jump that fails precisely when it matters. Every host with the
            // same ambient-identity pattern is scrubbed for the same reason; the plan
            // re-injects exactly what a command needs as `NAME=value` argv, which
            // `/usr/bin/env` applies after this. cmux's socket path stays: it says where
            // the server is, not which window we pretend to be.
            let identityPrefixes = [
                "CMUX_", "WAVETERM_", "SUPERSET_", "CONDUCTOR_", "ORCA_", "ZELLIJ",
                "TMUX",
            ]
            for key in environment.keys
            where identityPrefixes.contains(where: key.hasPrefix)
                && key != "CMUX_SOCKET_PATH"
            {
                environment.removeValue(forKey: key)
            }
            let extra = "/opt/homebrew/bin:/usr/local/bin"
                + ":/Applications/kitty.app/Contents/MacOS"
                // cmux and Wave ship their CLIs outside any shell's default PATH — cmux
                // inside the bundle, Wave under the home directory.
                + ":/Applications/cmux.app/Contents/Resources/bin"
                + ":\(NSHomeDirectory())/.waveterm/bin"
            environment["PATH"] = (environment["PATH"] ?? "") + ":" + extra
            process.environment = environment
            do {
                try process.run()
                process.waitUntilExit()
                // A remote-control CLI that runs and still fails (bad pane id, dead
                // socket, auth) is invisible without this: stdout and stderr are nulled.
                if process.terminationStatus != 0 {
                    PerchLog.error(
                        "\(executable) exited \(process.terminationStatus) — jumped to the window only")
                }
            } catch {
                PerchLog.error("\(executable) is not on PATH — jumped to the window only")
            }
        }
    }

    private static func selectTmuxPane(_ pane: String) {
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["tmux", "select-pane", "-t", pane]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }
}
