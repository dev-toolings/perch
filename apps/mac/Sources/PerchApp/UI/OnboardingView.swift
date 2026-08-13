import AppKit
import PerchKit
import SwiftUI

/// The first screen.
///
/// It reports rather than interrogates: Perch can see which agents and terminals are on
/// this Mac, so asking you to tick boxes about your own machine would be asking a question
/// it already knows the answer to.
///
/// It appears once — when at least one agent is installed and none of them are wired up —
/// and never again. An app that greets you every launch is an app you learn to dismiss
/// without reading.
struct OnboardingView: View {
    let model: AppModel
    let onDone: () -> Void

    @State private var tools = EnvironmentScan.run()
    @State private var isWorking = false
    @State private var message: String?
    /// Set once, when a run of `configure()` actually wired something up. The screen then
    /// stops being a report and becomes an acknowledgement — the one moment in the app that
    /// is allowed to celebrate, because it happens exactly once per Mac.
    @State private var isSetUp = false

    private var agents: [DetectedTool] { tools.filter { $0.kind == .agent } }
    private var terminals: [DetectedTool] { tools.filter { $0.kind == .terminal } }
    private var editors: [DetectedTool] { tools.filter { $0.kind == .editor } }

    var body: some View {
        Group {
            if isSetUp { celebration } else { report }
        }
        .padding(24)
        .frame(width: 560, height: 460)
        // The first sound the app ever makes. A single blip rather than a fanfare: the
        // fanfare is earned at the bottom of this screen, not at the top of it.
        .onAppear { play("boot") }
    }

    private var report: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                creatures
                Text(t("Approve Claude Code from the notch"))
                    .font(.title2).bold()
                // Says outright that the list is a report. Without this line the rows read
                // as a form, and the first thing anyone does is try to tick one.
                Text(t("Here is what Perch found on this Mac. Nothing below is a choice — one button sets up everything listed."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if agents.isEmpty {
                Text(t("No agent CLI found. Install Claude Code, then reopen Perch."))
                    .foregroundStyle(.orange)
            } else {
                group(t("Agents"), agents)
            }
            if !terminals.isEmpty { group(t("Terminals"), terminals) }
            if !editors.isEmpty { group(t("Editors"), editors) }

            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                Button(t("Set up this Mac")) { configure() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || agents.isEmpty)
                if isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button(t("Not now"), action: onDone)
            }
        }
    }

    /// The three starters, breathing, at the head of the screen.
    ///
    /// They are the first thing anyone sees of Perch, and they say what the rows below say
    /// in words: this app is about your agents. Staggered beats so the row breathes as three
    /// creatures rather than as one animation played three times.
    private var creatures: some View {
        HStack(spacing: 12) {
            ForEach(Array([Agent.claude, .codex, .opencode].enumerated()), id: \.offset) {
                index, agent in
                AgentGlyph(agent: agent, pixel: 4, beat: index)
            }
        }
    }

    /// What is left on screen once the Mac is set up.
    ///
    /// Deliberately not a dismissible banner over the report: the list behind it has just
    /// become untrue — every row now says "ready" — and a screen that celebrates while
    /// still showing the work it did reads as though the work is pending.
    private var celebration: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            PixelArt(rows: Self.trophy, fill: Theme.warning, accent: Theme.warning.opacity(0.55))
            Text(t("This Mac is a Perch"))
                .font(.title2).bold()
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(t("Done"), action: onDone)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
    }

    /// A cup with handles, a stem and a base, on the same ten-square grid the creatures use
    /// — drawn here, from nothing, like everything else pixelled in this app.
    private static let trophy = [
        "..........",
        ".xxxxxxxx.",
        "oxxxxxxxxo",
        "o.xxxxxx.o",
        "o.xxxxxx.o",
        ".oxxxxxxo.",
        "...xxxx...",
        "....xx....",
        "..oooooo..",
        "..........",
    ]

    /// Sound is a setting, and a screen nobody asked for is the last place to ignore it.
    private func play(_ jingle: String) {
        guard model.sounds.enabled else { return }
        SoundPlayer.preview(.synth(jingle), volume: model.sounds.volume)
    }

    private func group(_ title: String, _ items: [DetectedTool]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ForEach(items) { tool in
                HStack(spacing: 8) {
                    Image(systemName: symbol(for: tool))
                        .foregroundStyle(colour(for: tool))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tool.name)
                        Text(tool.evidence).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(status(for: tool))
                        .font(.caption)
                        .foregroundStyle(colour(for: tool))
                }
            }
        }
    }

    /// Deliberately not `circle`.
    ///
    /// An empty circle at the head of a list row is the shape of an unselected radio
    /// button, so that is what people take it for — the first thing anyone did with this
    /// screen was try to click one. These are three *states*, and none of them is a
    /// control: the only control on the screen is the button at the bottom.
    private func symbol(for tool: DetectedTool) -> String {
        switch tool.isConfigured {
        case true: return "checkmark.circle.fill"
        case false: return "arrow.down.circle"
        // Terminals need nothing installed, so anything implying work to do would be a lie.
        case nil: return "checkmark.circle"
        }
    }

    private func status(for tool: DetectedTool) -> String {
        switch tool.isConfigured {
        case true: return t("ready")
        case false: return t("will be set up")
        case nil: return t("nothing to do")
        }
    }

    private func colour(for tool: DetectedTool) -> Color {
        switch tool.isConfigured {
        case true: return .green
        case false: return .accentColor
        case nil: return .secondary
        }
    }

    /// Runs the same scripts the README documents rather than reimplementing them in
    /// Swift: one behaviour, one place to fix it, and what happened is inspectable
    /// afterwards in the files they touched.
    private func configure() {
        isWorking = true
        message = nil

        Task {
            var done: [String] = []

            if RepoScripts.run("install-hooks.sh", ["--global"]) {
                done.append("Claude Code")
            }
            if agents.contains(where: { $0.name == "Codex" }),
                RepoScripts.run("install-hooks.sh", ["--codex"])
            {
                done.append("Codex")
            }
            if !editors.isEmpty, RepoScripts.run("install-extension.sh") {
                done.append("editor extension")
            }

            tools = EnvironmentScan.run()
            isWorking = false
            isSetUp = !done.isEmpty
            if isSetUp { play("welcome") }
            message =
                done.isEmpty
                ? t("Nothing could be set up automatically — see the README.")
                // The part everyone misses, said last so it is the thing left on screen.
                : t(
                    "Set up: %@.\n\nRestart any Claude Code session you already have open — "
                        + "hooks are read once, when a session starts, so a running one "
                        + "ignores them and the notch stays empty.",
                    done.joined(separator: ", "))
        }
    }

}

/// A mark drawn as literal squares, the way the creatures are.
///
/// Same grammar as `AgentGlyph`: `x` is the body, `o` the accent, anything else is nothing.
/// Kept here rather than pushed into `AgentGlyph` because that type is a creature per agent
/// and this is a badge — sharing the row format is enough.
private struct PixelArt: View {
    let rows: [String]
    let fill: Color
    let accent: Color
    var pixel: CGFloat = 6

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Rectangle()
                            .fill(cell == "x" ? fill : cell == "o" ? accent : .clear)
                            .frame(width: pixel, height: pixel)
                    }
                }
            }
        }
    }
}

/// Hosts the first screen. Same shape as the settings window, and for the same reason:
/// an accessory app has nothing that would otherwise bring a window forward.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(model: AppModel) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "Perch"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: OnboardingView(model: model) { [weak window] in window?.close() })

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
