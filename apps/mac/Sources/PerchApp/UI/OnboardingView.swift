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
    let onStepChanged: (Int) -> Void
    let onDone: () -> Void

    @State private var tools = EnvironmentScan.run()
    @State private var isWorking = false
    @State private var message: String?
    @State private var step = 0
    @State private var demoScene = 0
    @State private var enabledAgentNames: Set<String> = []
    @State private var launchAtLogin = false
    /// Set once, when a run of `configure()` actually wired something up. The screen then
    /// stops being a report and becomes an acknowledgement — the one moment in the app that
    /// is allowed to celebrate, because it happens exactly once per Mac.
    @State private var isSetUp = false

    private var agents: [DetectedTool] { tools.filter { $0.kind == .agent } }
    private var terminals: [DetectedTool] { tools.filter { $0.kind == .terminal } }
    private var editors: [DetectedTool] { tools.filter { $0.kind == .editor } }
    private var onboardingAgents: [DetectedTool] {
        let order = ["Claude Code", "Codex", "Gemini CLI", "Droid", "Cursor Agent", "OpenCode"]
        return order.compactMap { name in agents.first { $0.name == name } }
    }

    init(
        model: AppModel,
        onStepChanged: @escaping (Int) -> Void = { _ in },
        onDone: @escaping () -> Void
    ) {
        self.model = model
        self.onStepChanged = onStepChanged
        self.onDone = onDone
    }

    var body: some View {
        ZStack {
            if step >= 2 {
                Color(white: 0.50)
            } else {
                OnboardingBackdrop(softened: step != 1, muted: step == 0)
                Color.black.opacity(step == 1 ? 0.10 : 0.20)
            }

            Group {
                switch step {
                case 0: welcome
                case 1: demo
                case 2: report
                case 3: vibe
                default: celebration
                }
            }
            .padding(.horizontal, step >= 2 ? 24 : 32)
            .padding(.vertical, step >= 2 ? 16 : 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: step >= 2 ? 28 : 0, style: .continuous))
        .preferredColorScheme(.dark)
        // The first sound the app ever makes. A single blip rather than a fanfare: the
        // fanfare is earned at the bottom of this screen, not at the top of it.
        .onAppear {
            enabledAgentNames = Set(onboardingAgents.map(\.name))
            launchAtLogin = model.preferences.launchAtLogin
            onStepChanged(step)
            play("boot")
        }
        .onChange(of: step) { _, next in onStepChanged(next) }
        .task(id: step) {
            guard step == 1 else { return }
            demoScene = 0
            for next in 1...3 {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, step == 1 else { return }
                withAnimation(.easeInOut(duration: 0.45)) { demoScene = next }
            }
        }
    }

    private var welcome: some View {
        GeometryReader { geometry in
            VStack(spacing: 20) {
                HStack(spacing: 8) {
                    VibeIslandBadge()
                        .frame(width: 32, height: 32)
                    Text("Perch")
                        .font(Theme.mono(28).weight(.bold))
                }
                .frame(width: 340, height: 70)
                .background(Capsule().fill(.black.opacity(0.82)))
                .overlay(
                    Capsule().stroke(
                        LinearGradient(
                            colors: [Color(hex: 0x9B5DE5), Color(hex: 0xF15BB5), Color(hex: 0xFEE440)],
                            startPoint: .leading, endPoint: .trailing),
                        lineWidth: 1.4))
                .shadow(color: Color(hex: 0xF15BB5).opacity(0.35), radius: 9)
                Text(t("A Dynamic Island for your AI coding tools"))
                    .font(Theme.mono(16))
                    .foregroundStyle(Color.white.opacity(0.78))
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height * 0.41)

            Button(t("Get Started")) {
                withAnimation(.easeInOut(duration: 0.22)) { step = 1 }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .position(x: geometry.size.width / 2, y: geometry.size.height * 0.595)

            stepDots
                .position(x: geometry.size.width / 2, y: geometry.size.height - 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stepDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(index == step ? Color.white : Color.white.opacity(0.24))
                    .frame(width: index == step ? 5 : 3, height: index == step ? 5 : 3)
            }
        }
        .frame(height: 7)
    }

    private var demo: some View {
        GeometryReader { geometry in
            VStack(spacing: 7) {
                Text("\(demoScene + 1) / 4")
                    .font(Theme.mono(11))
                    .foregroundStyle(Color.white.opacity(0.42))
                Text(demoTitle)
                    .font(.system(size: 34, weight: .bold))
                Text(demoSubtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            .multilineTextAlignment(.center)
            .position(x: geometry.size.width / 2, y: geometry.size.height * 0.29)

            demoMockup
                .frame(width: 980, height: 430)
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.57)

            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index == demoScene ? Color.white : Color.white.opacity(0.28))
                        .frame(width: index == demoScene ? 9 : 5, height: index == demoScene ? 9 : 5)
                }
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height - 32)

            if demoScene == 3 {
                VStack(spacing: 8) {
                    Text(
                        t(
                            "Perch can jump to the right window without Accessibility access. "
                                + "No system permission prompt is required."))
                        .font(Theme.mono(10))
                        .foregroundStyle(Color.white.opacity(0.52))
                        .multilineTextAlignment(.center)
                        .frame(width: 520)
                    Button(t("Next")) {
                        withAnimation(.easeInOut(duration: 0.3)) { step = 2 }
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height - 224)
            } else {
                Button(t("Skip")) {
                    withAnimation(.easeInOut(duration: 0.3)) { step = 2 }
                }
                .buttonStyle(.plain)
                .font(Theme.mono(12))
                .foregroundStyle(Color.white.opacity(0.55))
                .position(x: geometry.size.width - 62, y: geometry.size.height - 32)
            }
        }
    }

    private var demoTitle: String {
        [
            t("All your AI agents, one Dynamic Island."),
            t("Approve without switching windows."),
            t("Know the moment it's done."),
            t("Click to jump back."),
        ][demoScene]
    }

    private var demoSubtitle: String {
        [
            t("Terminals, desktop apps, IDEs — every running session lives in the notch."),
            t("When an agent needs permission, it pops up right here. No context switching."),
            t("Finished tasks surface automatically — no hunting through terminal tabs."),
            t("Land in the exact window, tab, or split — across 13+ terminals and IDEs."),
        ][demoScene]
    }

    @ViewBuilder private var demoMockup: some View {
        switch demoScene {
        case 0:
            ZStack {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .shadow(color: Color.cyan.opacity(0.48), radius: 12)
                    .offset(y: -118)
                demoIDEWindow.offset(y: 55)
            }
        case 1:
            demoNotchCard(
                symbol: "checkmark.shield.fill", title: "Bash wants permission",
                detail: "npm run build", action: t("Approve"))
        case 2:
            demoNotchCard(
                symbol: "checkmark.circle.fill", title: t("Task complete"),
                detail: t("Added dark mode support."), action: t("Open"))
        default:
            demoTerminalWindow.offset(y: 8)
        }
    }

    private var demoIDEWindow: some View {
        VStack(spacing: 0) {
            demoIDETitleBar

            HStack(spacing: 0) {
                demoIDESidebar

                Divider().overlay(Color.white.opacity(0.08))

                demoIDEEditor

                Divider().overlay(Color.white.opacity(0.08))

                demoIDEChat
            }

            demoIDEStatusBar
        }
        .frame(width: 640, height: 384)
        .background(Color.black.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.44), radius: 22, y: 12)
    }

    private var demoIDETitleBar: some View {
        ZStack {
            HStack(spacing: 6) {
                Circle().fill(Color.red.opacity(0.88)).frame(width: 10, height: 10)
                Circle().fill(Color.yellow.opacity(0.88)).frame(width: 10, height: 10)
                Circle().fill(Color.green.opacity(0.88)).frame(width: 10, height: 10)
                Spacer()
            }
            Text("Package.swift — Cursor")
                .font(Theme.mono(10))
                .foregroundStyle(Color.white.opacity(0.54))
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Color.white.opacity(0.035))
    }

    private var demoIDESidebar: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("VIBE-ISLAND")
                .font(Theme.mono(9).weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.72))
            Text("▾ Sources/")
            Text("    App/")
            Text("    Core/")
            Text("    Services/")
            Text("    UI/")
            Text("    Utilities/")
            Text("▸ Resources/")
            Text("Package.swift").foregroundStyle(.white)
            Text("CLAUDE.md")
            Text("Package.resolved")
            Spacer()
        }
        .font(Theme.mono(9))
        .foregroundStyle(Color.white.opacity(0.48))
        .padding(12)
        .frame(width: 142)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.22))
    }

    private var demoIDEEditor: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Package.swift")
                .font(Theme.mono(10).weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.74))
                .padding(.bottom, 5)
            codeLine(1, "// swift-tools-version: 6.0", .pink)
            codeLine(2, "// ============================", .secondary)
            codeLine(3, "//  Perch — Swift Package", .secondary)
            codeLine(4, "// ============================", .secondary)
            codeLine(5, "", .secondary)
            codeLine(6, "import PackageDescription", .purple)
            codeLine(7, "", .secondary)
            codeLine(8, "let package = Package(", .white)
            codeLine(9, "    name: \"perch\",", .green)
            codeLine(10, "    platforms: [.macOS(.v14)],", .white)
            codeLine(11, "    products: [", .white)
            codeLine(12, "        .executable(name: \"Perch\", …)", .green)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var demoIDEChat: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Chat")
                .font(Theme.mono(10).weight(.semibold))
            Text("General  ▾")
                .font(Theme.mono(9))
                .foregroundStyle(Color.white.opacity(0.52))
            Spacer()
            Text("Plan, @ for context, / for commands")
                .font(Theme.mono(8))
                .foregroundStyle(Color.white.opacity(0.38))
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))
            Text("∞  GPT-5.4  ▾")
                .font(Theme.mono(9))
                .foregroundStyle(Color.white.opacity(0.48))
        }
        .padding(12)
        .frame(width: 190)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.16))
    }

    private var demoIDEStatusBar: some View {
        HStack {
            Text("main*")
            Spacer()
            Text("Swift    UTF-8")
        }
        .font(Theme.mono(8))
        .foregroundStyle(Color.white.opacity(0.38))
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(Color.white.opacity(0.03))
    }

    private func codeLine(_ number: Int, _ text: String, _ colour: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(String(number))
                .foregroundStyle(Color.white.opacity(0.22))
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .foregroundStyle(colour.opacity(0.78))
                .lineLimit(1)
        }
        .font(Theme.mono(9))
    }

    private var demoTerminalWindow: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 6) {
                    Circle().fill(Color.red.opacity(0.88)).frame(width: 10, height: 10)
                    Circle().fill(Color.yellow.opacity(0.88)).frame(width: 10, height: 10)
                    Circle().fill(Color.green.opacity(0.88)).frame(width: 10, height: 10)
                    Spacer()
                }
                Text("perch · Claude Code")
                    .font(Theme.mono(10))
                    .foregroundStyle(Color.white.opacity(0.52))
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.white.opacity(0.035))

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 10) {
                    AgentGlyph(agent: .claude, pixel: 4, beat: 0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude Code  v2.1.83")
                            .font(Theme.mono(11).weight(.semibold))
                        Text("Opus 4.6 (1M Context) · Claude Max")
                            .font(Theme.mono(9))
                            .foregroundStyle(Color.white.opacity(0.58))
                        Text("~/Documents/my-app")
                            .font(Theme.mono(9))
                            .foregroundStyle(Color.white.opacity(0.42))
                    }
                }

                Text("> add dark mode to the app")
                    .foregroundStyle(Color.white.opacity(0.88))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06))
                Text("●  I'll add dark mode support to the app.")
                Text("●  Read(src/styles/theme.css)")
                Text("    └ Done (2 files · 840 tokens)")
                    .foregroundStyle(Color.white.opacity(0.50))
                Text("●  Edit(src/styles/theme.css)")
                Text("    └ Done (+24 -3 lines)")
                    .foregroundStyle(Color.white.opacity(0.50))
                Text("●  Working…  (esc to interrupt)")
                    .foregroundStyle(Color.orange.opacity(0.72))
                Text("> ▮")
            }
            .font(Theme.mono(10))
            .foregroundStyle(Color.white.opacity(0.74))
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 586, height: 346)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }

    private func demoNotchCard(symbol: String, title: String, detail: String, action: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(Theme.active)
            Text(title).font(.system(size: 20, weight: .bold))
            Text(detail).font(Theme.mono(13)).foregroundStyle(Color.white.opacity(0.68))
            Text(action)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 22).frame(height: 36)
                .background(Capsule().fill(Color.white)).foregroundStyle(.black)
        }
        .frame(width: 500, height: 245)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.black.opacity(0.90)))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.12)))
    }

    private var report: some View {
        VStack(spacing: 0) {
            VibeIslandBadge()
                .frame(width: 48, height: 48)
                .padding(.top, 0)

            Text(t("All Set"))
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 16)
            Text(t("Perch automatically detected and configured your tools."))
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.52))
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 0) {
                onboardingSectionTitle(t("AI Agents"))
                    .padding(.top, 20)
                VStack(spacing: 0) {
                    ForEach(onboardingAgents) { tool in onboardingAgentRow(tool) }
                }
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.055)))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.08)))

                onboardingSectionTitle(t("Terminals & IDEs"))
                    .padding(.top, 9)
                HStack(spacing: 6) {
                    ForEach(terminals + editors) { tool in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.active)
                            Text(tool.name == "Terminal" ? "Terminal.app" : tool.name)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    }
                }

                Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 9)

                HStack(spacing: 17) {
                    Image(systemName: "power")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Open at login"))
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(t("Start automatically when you log in"))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.48))
                    }
                    Spacer()
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(OnboardingLoginToggleStyle())
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.055)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06)))
            }

            Spacer(minLength: 12)

            if isWorking { ProgressView().controlSize(.small).padding(.bottom, 8) }
            Button(t("Next")) { configure() }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || onboardingAgents.isEmpty)
                .buttonStyle(OnboardingPrimaryButtonStyle(width: 412, height: 42))

            HStack(spacing: 7) {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(index == 2 ? Color.white : Color.white.opacity(0.22))
                        .frame(width: index == 2 ? 7 : 5, height: index == 2 ? 7 : 5)
                }
            }
            .frame(height: 18)
            .padding(.top, 17)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func onboardingSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.white.opacity(0.34))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.bottom, 5)
    }

    private func onboardingAgentRow(_ tool: DetectedTool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.active)
            Text(tool.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
            Spacer()
            Toggle(
                "",
                isOn: Binding(
                    get: { enabledAgentNames.contains(tool.name) },
                    set: { enabled in
                        if enabled { enabledAgentNames.insert(tool.name) }
                        else { enabledAgentNames.remove(tool.name) }
                    }))
                .labelsHidden()
                .toggleStyle(OnboardingToggleStyle())
        }
        .padding(.horizontal, 10)
        .frame(height: 27)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.white.opacity(0.07))
        }
    }

    private var vibe: some View {
        VStack(spacing: 22) {
            Spacer()
            Text(t("Choose your vibe"))
                .font(.system(size: 28, weight: .bold))
            Text(t("Everything. One glance."))
                .font(Theme.mono(12))
                .foregroundStyle(Color.white.opacity(0.62))
            HStack(spacing: 12) {
                vibeChoice("speaker.slash.fill", t("Silent"), selected: !model.sounds.enabled) {
                    var next = model.sounds
                    next.enabled = false
                    model.updateSounds(next)
                }
                vibeChoice("waveform", "8-bit", selected: model.sounds.enabled) {
                    var next = model.sounds
                    next.enabled = true
                    model.updateSounds(next)
                    play("query")
                }
            }
            .frame(maxWidth: 430)
            Spacer()
            Button(t("Next")) {
                playCeremony()
                withAnimation(.easeInOut(duration: 0.22)) { step = 4 }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(OnboardingPrimaryButtonStyle())
            Color.clear.frame(height: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func vibeChoice(
        _ symbol: String, _ title: String, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 24, weight: .medium))
                Text(title).font(Theme.mono(12))
            }
            .frame(width: 170, height: 105)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.42)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selected ? Color.white : Color.white.opacity(0.12), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
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
        VStack(spacing: 18) {
            Color.clear.frame(height: 18)
            ZStack {
                Circle().fill(Color.white.opacity(0.10)).frame(width: 96, height: 96)
                PixelArt(
                    rows: Self.trophy, fill: Theme.warning,
                    accent: Theme.warning.opacity(0.55), pixel: 6)
            }
            Text(t("All Set"))
                .font(.system(size: 28, weight: .bold))
            Text(t("Perch automatically detected and configured your tools."))
                .foregroundStyle(Color.white.opacity(0.66))
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(t("Restart any running sessions, or start a new one."))
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.52))
            Color.clear.frame(height: 10)
            Button(t("Start Vibing"), action: onDone)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(OnboardingPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func playCeremony() {
        guard model.sounds.enabled,
            let path = Bundle.main.path(forResource: "onboarding-ceremony", ofType: "wav", inDirectory: "Sounds")
        else { return }
        SoundPlayer.preview(.file(path), volume: model.sounds.volume)
    }

    private func group(_ title: String, _ items: [DetectedTool]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(t("%lld detected", items.count))
                    .font(Theme.mono(9))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, tool in
                    HStack(spacing: 8) {
                        Image(systemName: symbol(for: tool))
                            .foregroundStyle(colour(for: tool))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tool.name).font(.system(size: 12, weight: .medium))
                            Text(tool.evidence).font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.45))
                        }
                        Spacer()
                        Text(status(for: tool))
                            .font(Theme.mono(9))
                            .foregroundStyle(colour(for: tool))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    if index < items.count - 1 {
                        Divider().overlay(Color.white.opacity(0.07)).padding(.leading, 34)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.30)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.07)))
        }
    }

    private func onboardingFeature(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.10)))
            Text(t(title))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .frame(width: 145)
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
            let pending = agents.filter {
                $0.isConfigured == false && enabledAgentNames.contains($0.name)
            }.map(\.name)
            let failures = AgentConfigurator.configureDetected(names: enabledAgentNames)
            var done = pending.filter { failures[$0] == nil }
            if !editors.isEmpty, RepoScripts.run("install-extension.sh") {
                done.append("editor extension")
            }

            tools = EnvironmentScan.run()
            if launchAtLogin != model.preferences.launchAtLogin {
                var next = model.preferences
                next.launchAtLogin = launchAtLogin
                model.updatePreferences(next)
            }
            isWorking = false
            isSetUp = failures.isEmpty
            if isSetUp { step = 3 }
            message =
                !failures.isEmpty
                ? failures.keys.sorted().map { "\($0): \(failures[$0]!.localizedDescription)" }
                    .joined(separator: "\n")
                // The part everyone misses, said last so it is the thing left on screen.
                : t(
                    "Set up: %@.\n\nRestart any Claude Code session you already have open — "
                        + "hooks are read once, when a session starts, so a running one "
                        + "ignores them and the notch stays empty.",
                    done.joined(separator: ", "))
        }
    }

}

private struct OnboardingBackdrop: View {
    let softened: Bool
    let muted: Bool

    var body: some View {
        Group {
            if muted {
                LinearGradient(
                    colors: [Color(white: 0.49), Color(white: 0.045)],
                    startPoint: .top, endPoint: .bottom)
            } else if let path = Bundle.main.path(forResource: "onboarding-wallpaper", ofType: "jpg"),
                let image = NSImage(contentsOfFile: path)
            {
                if softened {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(1.1)
                        .saturation(0.08)
                        .blur(radius: 34)
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }
            } else {
                Color.black
            }
            if softened && !muted {
                LinearGradient(
                    colors: [Color.black.opacity(0.08), Color.black.opacity(0.72)],
                    startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    var width: CGFloat = 220
    var height: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.black)
            .frame(width: width, height: height)
            .background(
                Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.76 : 0.96)))
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

/// Vibe keeps the compact agent switches neutral even when selected; the knob position
/// carries the state without adding another accent colour to the setup card.
private struct OnboardingToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                configuration.label
                Spacer(minLength: 8)
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(0.11))
                    Circle()
                        .fill(Color.white.opacity(0.94))
                        .frame(width: 13, height: 13)
                        .offset(x: configuration.isOn ? 9 : -9)
                }
                .frame(width: 36, height: 16)
            }
            .frame(minHeight: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: configuration.isOn)
    }
}

private struct OnboardingLoginToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                Capsule()
                    .fill(Color.white.opacity(0.11))
                Capsule()
                    .fill(Color.white.opacity(0.94))
                    .frame(width: 30, height: 20)
                    .offset(x: configuration.isOn ? 10 : -10)
            }
            .frame(width: 52, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: configuration.isOn)
    }
}

/// The small black-and-silver pixel badge Vibe uses above its setup report.
///
/// It is deliberately drawn rather than loading another application's icon: the
/// onboarding keeps Perch's own bundle identity while matching the reference's visual
/// language. The lower silver shell and the dark glass cap are the parts that remain
/// legible at the 32pt welcome size.
private struct VibeIslandBadge: View {
    private let rows = [
        "..xxx..x..",
        ".x.x.xxxx.",
        "xx..xxx...",
        ".x..x.x...",
        "..x...x...",
    ]

    var body: some View {
        Group {
            if let image = Self.referenceImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .scaleEffect(1.22)
            } else {
                fallback
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        .accessibilityHidden(true)
    }

    private static let referenceImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "VibeIslandReference", withExtension: "icns")
        else { return nil }
        return NSImage(contentsOf: url)
    }()

    private var fallback: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.92), Color(white: 0.68)],
                        startPoint: .top,
                        endPoint: .bottom))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.02))
                .frame(height: 30)
                .padding(2)
            PixelArt(rows: rows, fill: .white.opacity(0.94), accent: .white, pixel: 2)
                .padding(.top, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = OnboardingWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.title = "Perch"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        window.setFrame(frame, display: true)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hostingView = NSHostingView(
            rootView: OnboardingView(
                model: model,
                onStepChanged: { [weak self, weak window] step in
                    guard let window else { return }
                    self?.applyPresentation(step: step, to: window)
                },
                onDone: { [weak window] in window?.close() }))
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func applyPresentation(step: Int, to window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let target: NSRect
        if step < 2 {
            target = screen.frame
            window.hasShadow = false
        } else {
            let size = NSSize(width: 460, height: 580)
            target = NSRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2,
                width: size.width,
                height: size.height)
            window.hasShadow = true
        }
        guard window.frame != target else { return }
        window.setFrame(target, display: true, animate: true)
    }
}

private final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
