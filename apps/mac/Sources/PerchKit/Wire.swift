import Foundation

public enum Wire {
    public static let protocolVersion = 1

    /// Bytes are framed as one JSON object per line, in both directions.
    public static let delimiter = UInt8(0x0A)  // \n

    /// Reserved event name: asks the running app to describe itself instead of
    /// recording activity. Backs `Perch --status`.
    public static let statusEvent = "__status"

    /// Reserved event name: answers the oldest pending permission from the command line.
    /// Backs `Perch --decide`, which is how approvals are scripted and tested.
    public static let decideEvent = "__decide"

    /// Reserved event name: a remote host reporting its own plan quota.
    ///
    /// It travels down the tunnel that already exists rather than over a second channel —
    /// one thing to connect, one thing to debug when it stops working.
    public static let usageEvent = "__usage"
}

/// Whether a hook event can carry a decision back through that CLI's hook protocol.
///
/// Kimi emits `PermissionRequest`, but documents it as observation-only. Waiting for a
/// decision there would delay Kimi's own approval prompt without giving Perch's answer any
/// effect, so it is forwarded as telemetry and never held open.
public enum HookBehavior {
    public static func resolvedEvent(
        argument: String, payloadEvent: String?, source: String?
    ) -> String {
        switch source?.lowercased() {
        case "cursor", "gemini", "mistralvibe", "deepseek", "antigravity": return argument
        default: return payloadEvent ?? argument
        }
    }

    public static func wantsDecision(event: String, source: String?) -> Bool {
        guard event == "PermissionRequest" else { return false }
        switch source?.lowercased() {
        case "kimi", "kimicode", "copilot": return false
        default: return true
        }
    }

    /// DeepSeek TUI exposes its hook context through documented `DEEPSEEK_*`
    /// variables. Normalize those values into Perch's shared payload without copying
    /// unrelated environment variables or inventing a decision protocol.
    public static func normalizedPayload(
        _ input: ClaudeHookPayload, source: String?, environment: [String: String]
    ) -> ClaudeHookPayload {
        guard source?.lowercased() == "deepseek" else { return input }
        var payload = input
        payload.sessionId = payload.sessionId ?? environment["DEEPSEEK_SESSION_ID"]
        payload.cwd = payload.cwd ?? environment["DEEPSEEK_WORKSPACE"]
        payload.toolName = payload.toolName ?? environment["DEEPSEEK_TOOL_NAME"]
        payload.prompt = payload.prompt ?? environment["DEEPSEEK_MESSAGE"]
        payload.message = payload.message
            ?? environment["DEEPSEEK_TOOL_RESULT"]
            ?? environment["DEEPSEEK_ERROR"]
        if payload.toolInput == nil,
            let arguments = environment["DEEPSEEK_TOOL_ARGS"],
            let data = arguments.data(using: .utf8)
        {
            payload.toolInput = try? JSONDecoder().decode(JSONValue.self, from: data)
        }
        return payload
    }

    public static func normalizedPayload(
        _ input: ClaudeHookPayload, source: String?, json: JSONValue
    ) -> ClaudeHookPayload {
        guard source?.lowercased() == "antigravity" else { return input }
        var payload = input
        payload.sessionId = payload.sessionId ?? json["conversationId"]?.stringValue
        payload.transcriptPath = payload.transcriptPath ?? json["transcriptPath"]?.stringValue
        if payload.cwd == nil, case .array(let paths) = json["workspacePaths"] {
            payload.cwd = paths.first?.stringValue
        }
        payload.toolName = payload.toolName ?? json["toolCall"]?["name"]?.stringValue
        payload.toolInput = payload.toolInput ?? json["toolCall"]?["args"]
        payload.message = payload.message
            ?? json["error"]?.stringValue
            ?? json["terminationReason"]?.stringValue
        return payload
    }
}

/// One piece of work a session carries on with after its turn has ended.
///
/// Claude Code puts the live list on every `Stop`, and it is the only place it says out
/// loud that a finished turn is not finished work. Without reading it, `Stop` is
/// indistinguishable from being done — which it is not, from the moment anything is
/// launched in the background.
///
/// A fan-out agent and a backgrounded command are the same situation seen from the notch:
/// the terminal has gone quiet and something in it is still running.
public struct BackgroundTask: Codable, Sendable, Equatable, Identifiable {
    /// Claude Code's own id — `agent_id` for a subagent, the shell's id for a command.
    public var id: String
    /// `subagent` or `shell`. Kept as a string rather than an enum: a kind Perch has not
    /// seen yet is still work in flight, and it should show as one rather than be dropped.
    public var kind: String
    /// `running` is the one that matters. Anything else has stopped mattering.
    public var status: String
    /// What it is for, in Claude Code's words — "Count lines in sample.txt" says more on a
    /// card than "general-purpose" ever did.
    public var label: String?
    /// Subagents only.
    public var agentType: String?
    /// Shells only.
    public var command: String?

    public var isRunning: Bool { status == "running" }
    public var isSubagent: Bool { kind == "subagent" }

    /// What the card calls it, best first: the description, then the agent's type, then
    /// the command it is running.
    public var displayName: String {
        for candidate in [label, agentType, command] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return isSubagent ? "subagent" : "command"
    }

    enum CodingKeys: String, CodingKey {
        case id, status, command
        case kind = "type"
        case label = "description"
        case agentType = "agent_type"
    }

    public init(
        id: String, kind: String, status: String, label: String? = nil,
        agentType: String? = nil, command: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.label = label
        self.agentType = agentType
        self.command = command
    }
}

/// The subset of the Claude Code hook payload we care about.
///
/// The hook binary forwards the payload verbatim, so unknown fields survive the trip
/// and only the app decides what to surface.
public struct ClaudeHookPayload: Codable, Sendable {
    public var sessionId: String?
    public var transcriptPath: String?
    public var cwd: String?
    public var hookEventName: String?
    public var toolName: String?
    public var toolInput: JSONValue?
    /// Stable identity for one tool request when the client exposes it. Vibe uses this
    /// together with the runtime instance to keep question drafts attached to the exact
    /// card rather than to matching question text.
    public var toolUseId: String?
    public var runtimeInstanceId: String?
    /// `tool_response` is deliberately absent.
    ///
    /// It was modelled here, decoded into a tree, carried across the socket and decoded
    /// again by the app — and never read by anything. On a `PostToolUse` it holds whatever
    /// the tool produced: the whole of a file that was read, the whole of a command's
    /// output. Naming it in `CodingKeys` is what made every one of those a JSON tree built
    /// twice per tool call, in a process the agent is waiting on.
    public var message: String?
    public var prompt: String?
    /// How the session is answering permission prompts: `default`, `acceptEdits`,
    /// `bypassPermissions`, `plan`. Worth surfacing because it is the one property of a
    /// session that changes what an unattended agent is allowed to do to the machine, and
    /// it is invisible from anywhere else once the terminal is off screen.
    public var permissionMode: String?
    /// Which subagent this event belongs to, when it is not the main loop's.
    ///
    /// On `SubagentStart` and `SubagentStop` it is what pairs one with the other. It is
    /// also on the `PreToolUse` and `PostToolUse` of every tool a subagent runs — and
    /// those arrive under the *parent's* session id, so until this was read they were
    /// indistinguishable from the main agent's own work and moved the parent's card.
    public var agentId: String?
    /// The subagent's type, alongside `agentId` and on the same events.
    public var agentType: String?
    /// Everything still running when the turn ended. Only `Stop` and `SubagentStop` carry
    /// it, and on `Stop` it is the difference between a session that is done and one whose
    /// main loop is parked while an agent grinds on.
    public var backgroundTasks: [BackgroundTask]?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case hookEventName = "hook_event_name"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
        case runtimeInstanceId = "runtime_instance_id"
        case message
        case prompt
        case permissionMode = "permission_mode"
        case agentId = "agent_id"
        case agentType = "agent_type"
        case backgroundTasks = "background_tasks"
    }

    public init() {}
}

/// Which CLI a session belongs to.
///
/// Codex 0.144 speaks the same hook vocabulary as Claude Code — same event names, same
/// payload, a different config file — so supporting it is a label and an installer rather
/// than a second event model.
public enum Agent: String, Codable, Sendable, CaseIterable {
    case claude
    case codex
    case gemini
    case opencode
    case cursor
    case droid
    case pi
    case amp
    case kimi
    case deepseek
    case mistralVibe = "mistralvibe"
    case workbuddy
    case codebuddy
    case antigravity
    case copilot
    case unknown

    public init(source: String?) {
        guard let source = source?.lowercased(), !source.isEmpty else {
            self = .claude
            return
        }
        switch source {
        case "kimi", "kimicode": self = .kimi
        case "mistral-vibe", "mistralvibe": self = .mistralVibe
        default: self = Agent(rawValue: source) ?? .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .opencode: return "opencode"
        case .cursor: return "Cursor"
        case .droid: return "Droid"
        case .pi: return "Pi"
        case .amp: return "Amp"
        case .kimi: return "Kimi Code"
        case .deepseek: return "DeepSeek"
        case .mistralVibe: return "Mistral Vibe"
        case .workbuddy: return "WorkBuddy"
        case .codebuddy: return "CodeBuddy"
        case .antigravity: return "Antigravity"
        case .copilot: return "Copilot"
        case .unknown: return "Agent"
        }
    }
}

/// Where the session is running, captured from the hook's own environment.
///
/// The hook is a child of the terminal that runs Claude Code, so its environment is the
/// only place this is knowable — the payload never says which window you are looking at.
/// It is what lets the panel label a session "iTerm" rather than leaving it anonymous, and
/// it is the identity a jump would need.
public struct ClientInfo: Codable, Sendable, Equatable {
    /// `TERM_PROGRAM`: `iTerm.app`, `ghostty`, `WarpTerminal`, `vscode`, `Apple_Terminal`…
    public var terminal: String?
    /// `ITERM_SESSION_ID`, `WEZTERM_PANE`, `KITTY_WINDOW_ID` — whichever the host sets.
    public var session: String?
    /// The second half of a two-part address. Superset needs workspace *and* pane in its
    /// deep link; Wave needs tab *and* block on its CLI. One field, because no host so far
    /// needs three.
    public var workspace: String?
    /// Inside tmux, the pane is what a jump has to target, not the window.
    public var tmuxPane: String?
    /// zellij is tmux's shape with different names: the pane to focus, and the session it
    /// lives in, both stacked on top of whatever terminal hosts them.
    public var zellijPane: String?
    public var zellijSession: String?
    /// GNU screen, same again: `STY` names the session, `WINDOW` the window inside it.
    public var screenSession: String?
    public var screenWindow: String?
    /// The controlling terminal, e.g. `/dev/ttys004`. Terminal.app exposes `tty` on every
    /// tab, which makes this the only reliable way to find the right one there.
    public var tty: String?
    /// The app that launched this process, from `__CFBundleIdentifier`. A background
    /// helper driving an agent without a terminal is invisible to every other signal.
    public var launcher: String?

    public init(
        terminal: String? = nil,
        session: String? = nil,
        workspace: String? = nil,
        tmuxPane: String? = nil,
        zellijPane: String? = nil,
        zellijSession: String? = nil,
        screenSession: String? = nil,
        screenWindow: String? = nil,
        tty: String? = nil,
        launcher: String? = nil
    ) {
        self.terminal = terminal
        self.session = session
        self.workspace = workspace
        self.tmuxPane = tmuxPane
        self.zellijPane = zellijPane
        self.zellijSession = zellijSession
        self.screenSession = screenSession
        self.screenWindow = screenWindow
        self.tty = tty
        self.launcher = launcher
    }

    /// Reads the environment the hook was launched with.
    ///
    /// Vendor variables are checked before `TERM_PROGRAM`, because `TERM_PROGRAM` lies:
    /// cmux embeds libghostty and reports `ghostty`; Superset flatly claims to be `kitty`.
    /// Trusting the label sent every jump to an application the session is not in — and on
    /// most machines, one that is not installed. A host's own variables are the truth.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        tty: String? = nil
    ) -> ClientInfo {
        // The multiplexers stack on top of whichever host is found, so they are read once,
        // here, rather than repeated in every branch below.
        var info = ClientInfo(
            tmuxPane: environment["TMUX_PANE"],
            zellijPane: environment["ZELLIJ_PANE_ID"],
            zellijSession: environment["ZELLIJ_SESSION_NAME"],
            screenSession: environment["STY"],
            screenWindow: environment["WINDOW"],
            tty: tty ?? environment["TTY"],
            launcher: environment["__CFBundleIdentifier"]
        )

        if let panel = environment["CMUX_PANEL_ID"] ?? environment["CMUX_SURFACE_ID"] {
            info.terminal = "cmux"
            info.session = panel
            info.launcher = environment["CMUX_BUNDLE_ID"] ?? info.launcher
        } else if let pane = environment["SUPERSET_PANE_ID"] {
            // Superset's deep link wants the workspace and the pane both.
            info.terminal = "Superset"
            info.session = pane
            info.workspace = environment["SUPERSET_WORKSPACE_ID"]
        } else if environment["CONDUCTOR_WORKSPACE_PATH"] != nil
            || environment["CONDUCTOR_SESSION_ID"] != nil
        {
            // Conductor is a Tauri app whose TERM_PROGRAM is unknown; its own variables
            // are documented. No focus deep link exists, so the label is the whole win.
            info.terminal = "Conductor"
            info.session = environment["CONDUCTOR_SESSION_ID"]
        } else if let block = environment["WAVETERM_BLOCKID"] {
            // Wave's `wsh focusblock` reads the tab from the environment, so both halves
            // are captured: the block as the address, the tab as the context.
            info.terminal = "waveterm"
            info.session = block
            info.workspace = environment["WAVETERM_TABID"]
        } else if let focus = environment["WARP_FOCUS_URL"] {
            // The URL is opaque on purpose — Warp's preview channel emits another scheme,
            // and the variable is the contract, not the string inside it.
            info.terminal = "WarpTerminal"
            info.session = focus
        } else if environment["ZED_TERM"] == "true" {
            // Zed sets no TERM_PROGRAM; ZED_TERM is its documented fingerprint.
            info.terminal = "Zed"
        } else {
            info.terminal = environment["TERM_PROGRAM"]
            info.session = environment["ITERM_SESSION_ID"]
                ?? environment["TERM_SESSION_ID"]
                ?? environment["WEZTERM_PANE"]
                ?? environment["KITTY_WINDOW_ID"]
        }
        return info
    }

    /// The label the panel shows. `iTerm.app` reads badly next to `Ghostty`.
    public var displayName: String? {
        guard let terminal, !terminal.isEmpty else {
            // No terminal does not mean nowhere: an agent manager that is not a terminal
            // (JetBrains, Nimbalyst, the next Electron shell) still names itself in
            // `__CFBundleIdentifier`, and a chip that can say where the click lands should.
            guard let launcher, TerminalJump.isUsableLauncher(launcher) else { return nil }
            return TerminalJump.name(forBundle: launcher)
        }
        switch terminal {
        case "Apple_Terminal": return "Terminal"
        case "iTerm.app": return "iTerm"
        case "WarpTerminal": return "Warp"
        case "vscode": return "VS Code"
        case "ghostty": return "Ghostty"
        case "waveterm": return "Wave"
        // Lowercase, the way it writes its own name.
        case "cmux": return "cmux"
        case "Codex Desktop": return "Codex app"
        default: return terminal.replacingOccurrences(of: ".app", with: "").capitalized
        }
    }
}

/// Sent by `perch-hook` to the app, one per line.
public struct PerchRequest: Codable, Sendable {
    public var v: Int
    public var token: String
    public var event: String
    /// When true the hook blocks until the app answers (permission prompts).
    public var wantsDecision: Bool
    public var payload: ClaudeHookPayload
    /// Raw payload, kept so the app can display fields we do not model yet.
    public var raw: JSONValue?
    public var client: ClientInfo?
    /// Which CLI sent this. Absent means Claude Code, which is what every hook installed
    /// before `--source` existed will send.
    public var agent: Agent?
    /// Alias of the configured SSH host that forwarded this event. Local hooks leave it
    /// nil; the remote bridge reads it from its mode-600 runtime config.
    public var remoteHost: String?
    /// Set by clients that cannot parse JSON — the remote hook is a shell script with no
    /// dependencies. The app then answers with the exact bytes to print on stdout, so the
    /// schema is built once, in Swift, where it is tested.
    public var rawOutput: Bool?

    public init(
        token: String,
        event: String,
        wantsDecision: Bool,
        payload: ClaudeHookPayload,
        raw: JSONValue? = nil,
        client: ClientInfo? = nil,
        agent: Agent? = nil,
        remoteHost: String? = nil,
        rawOutput: Bool? = nil
    ) {
        self.v = Wire.protocolVersion
        self.token = token
        self.event = event
        self.wantsDecision = wantsDecision
        self.payload = payload
        self.raw = raw
        self.client = client
        self.agent = agent
        self.remoteHost = remoteHost
        self.rawOutput = rawOutput
    }
}

extension PerchRequest {
    /// What a `SubagentStart` is about.
    ///
    /// Read from whichever key the CLI happened to use rather than from one that was
    /// verified once: a fan-out `Task` carries the type it was asked for, an Agent Team
    /// member carries a name, and the spelling has moved between releases. Nothing here is
    /// load-bearing — a subagent with no label is still a subagent, and shows as one.
    public var subagentLabel: String? {
        // `agent_type` is modelled now, and it is the one Claude Code actually sends on
        // these events. The hunt below stays as the fallback it always was.
        if let typed = payload.agentType, !typed.isEmpty { return typed }
        let keys = ["subagent_type", "agent_type", "agentType", "agent", "description", "name"]
        for key in keys {
            if let value = payload.toolInput?[key]?.stringValue, !value.isEmpty { return value }
            if let value = raw?[key]?.stringValue, !value.isEmpty { return value }
            // `Task` inputs sit one level down when the payload wraps them.
            if let value = raw?["tool_input"]?[key]?.stringValue, !value.isEmpty { return value }
        }
        return nil
    }
}

public enum PermissionDecision: String, Codable, Sendable {
    case allow
    case deny
    /// Hand the decision back to Claude Code's own prompt.
    case ask
}

/// A rule Claude Code should remember alongside an `allow`, in the shape its
/// `updatedPermissions` contract expects: the tool, and optionally what to match inside it.
///
/// `Bash(npm run:*)` in a settings file is `toolName: "Bash", content: "npm run:*"` here.
public struct RememberedRule: Codable, Sendable, Equatable {
    /// Where Claude Code persists the rule. `localSettings` is the project's own
    /// `.claude/settings.local.json` — personal and un-versioned.
    public enum Destination: String, Codable, Sendable {
        case userSettings, projectSettings, localSettings, session
    }

    public var toolName: String
    public var content: String?
    public var destination: Destination

    public init(toolName: String, content: String?, destination: Destination = .localSettings) {
        self.toolName = toolName
        self.content = content
        self.destination = destination
    }

    /// The settings-file spelling, which is what we show the user before they commit.
    public var display: String {
        content.map { "\(toolName)(\($0))" } ?? toolName
    }
}

/// How the session should carry on once a plan is approved.
///
/// Approving a plan is not a yes/no. Claude Code's own prompt is a choice of mode, and it
/// applies that choice as a `setMode` entry in `updatedPermissions` — an `allow` naming
/// none leaves the session in `plan`, where every edit comes back "Cannot call Edit while
/// in plan mode."
///
/// These are the three its prompt offers for continuing in place. `auto` is deliberately
/// absent: it is gated behind a feature check and a usage-consent prompt the hook cannot
/// see, and Claude Code falls back to `default` when the gate is off — so a notch button
/// promising it would be lying about half the time.
public enum PlanMode: String, Codable, Sendable, CaseIterable {
    case `default`
    case acceptEdits
    case bypassPermissions

    /// Claude Code's own names for the modes, so the button says what the terminal says.
    public var title: String {
        switch self {
        case .default: return "Manual"
        case .acceptEdits: return "Accept edits"
        case .bypassPermissions: return "Bypass"
        }
    }
}

/// The app's answer. A `nil` decision means "stay out of the way".
public struct PerchResponse: Codable, Sendable {
    public var decision: PermissionDecision?
    public var reason: String?
    /// Set when the user picked "Always": Claude Code persists it, so Perch never has to
    /// edit a settings file that Claude Code is also writing to.
    public var rule: RememberedRule?
    /// Replaces the tool's input before it runs. This is how an `AskUserQuestion` answer
    /// gets back: the answers ride inside the input the tool is about to receive.
    public var updatedInput: JSONValue?
    /// Set when the user approved a plan: which mode the session continues in.
    public var planMode: PlanMode?
    /// Echoed back so the hook can prove it is talking to Perch and not to whatever
    /// process happened to grab the port after a crash. Without this, any local process
    /// could answer `allow` and approve tool calls on the user's behalf.
    public var token: String?
    /// Only filled for `Wire.statusEvent`.
    public var status: String?
    /// Filled when the request asked for `rawOutput`: the exact bytes the hook should
    /// print, base64-encoded.
    ///
    /// Base64 because the consumer is a shell script with no JSON parser. The payload is
    /// itself JSON full of quotes and backslashes, and pulling that out of a JSON string
    /// with `sed` is not something to get subtly wrong on someone's build server —
    /// base64's alphabet contains no quote, so the match cannot run past its own field.
    public var outputB64: String?

    public init(
        decision: PermissionDecision? = nil,
        reason: String? = nil,
        token: String? = nil,
        status: String? = nil,
        rule: RememberedRule? = nil,
        updatedInput: JSONValue? = nil,
        planMode: PlanMode? = nil,
        outputB64: String? = nil
    ) {
        self.decision = decision
        self.reason = reason
        self.token = token
        self.status = status
        self.rule = rule
        self.updatedInput = updatedInput
        self.planMode = planMode
        self.outputB64 = outputB64
    }

    /// Renders the stdout a hook should produce for this answer, or nil to stay silent.
    ///
    /// One place builds the schema, so a shell script on a remote host is exactly as
    /// correct as the compiled hook — it just echoes what this produced.
    public func renderedOutput(event: String) -> Data? {
        guard let decision, decision != .ask else { return nil }
        let hookOutput = HookOutput(
            event: event, decision: decision, reason: reason, rule: rule,
            updatedInput: updatedInput, planMode: planMode)
        return try? JSONEncoder().encode(hookOutput)
    }

    /// The same thing, ready to travel to a client that cannot parse JSON.
    public func renderedOutputBase64(event: String) -> String {
        renderedOutput(event: event)?.base64EncodedString() ?? ""
    }
}

/// The JSON shape Claude Code expects on a hook's stdout.
///
/// The two permission events do **not** share a schema, and sending the wrong one is
/// silent: Claude Code rejects the object and prompts as if the hook had said nothing.
/// Verified against the `hookSpecificOutput` schemas in the Claude Code binary:
///
/// - `PermissionRequest` → `decision: {behavior: "allow", updatedInput?, updatedPermissions?}`
///                              or `{behavior: "deny", message?, interrupt?}`
/// - `PreToolUse`        → `permissionDecision` / `permissionDecisionReason`
///
/// `updatedPermissions` is a list of permission updates. Two of the six shapes are used
/// here: `addRules` to persist an "Always", and `setMode` to say which mode a session
/// continues in after a plan is approved.
public struct HookOutput: Encodable, Sendable {
    public var event: String
    public var decision: PermissionDecision
    public var reason: String?
    /// Only meaningful with `allow`: asks Claude Code to persist the rule itself.
    public var rule: RememberedRule?
    /// Only meaningful with `allow`: replaces the tool's input before it runs.
    ///
    /// This is how an `AskUserQuestion` answer travels back — and it is also what makes an
    /// `allow` count at all for `ExitPlanMode`. Both tools declare
    /// `requiresUserInteraction()`, and for those Claude Code drops an `allow` that
    /// carries no `updatedInput` and prompts in the terminal as if the hook had said
    /// nothing: the plan card's Approve button did nothing at all.
    public var updatedInput: JSONValue?
    /// Only meaningful with `allow`: the mode the session continues in.
    public var planMode: PlanMode?

    public init(
        event: String,
        decision: PermissionDecision,
        reason: String?,
        rule: RememberedRule? = nil,
        updatedInput: JSONValue? = nil,
        planMode: PlanMode? = nil
    ) {
        self.event = event
        self.decision = decision
        self.reason = reason
        self.rule = rule
        self.updatedInput = updatedInput
        self.planMode = planMode
    }

    private enum RootKey: String, CodingKey { case hookSpecificOutput }

    private enum Key: String, CodingKey {
        case hookEventName, decision
        case permissionDecision, permissionDecisionReason, updatedInput
    }

    private enum DecisionKey: String, CodingKey {
        case behavior, message, updatedPermissions, updatedInput
    }

    private enum UpdateKey: String, CodingKey {
        case type, rules, behavior, destination, mode
    }

    private enum RuleKey: String, CodingKey { case toolName, ruleContent }

    public func encode(to encoder: any Encoder) throws {
        var root = encoder.container(keyedBy: RootKey.self)
        var specific = root.nestedContainer(keyedBy: Key.self, forKey: .hookSpecificOutput)
        try specific.encode(event, forKey: .hookEventName)

        guard event == "PermissionRequest" else {
            try specific.encode(decision.rawValue, forKey: .permissionDecision)
            try specific.encodeIfPresent(reason, forKey: .permissionDecisionReason)
            try specific.encodeIfPresent(updatedInput, forKey: .updatedInput)
            return
        }

        var body = specific.nestedContainer(keyedBy: DecisionKey.self, forKey: .decision)
        switch decision {
        case .deny, .ask:
            // `ask` never reaches here — the hook stays silent instead — but denying is
            // the safe reading if it ever does.
            try body.encode("deny", forKey: .behavior)
            try body.encodeIfPresent(reason, forKey: .message)
        case .allow:
            try body.encode("allow", forKey: .behavior)
            try body.encodeIfPresent(updatedInput, forKey: .updatedInput)
            // An empty list would be a schema violation, so the container is only opened
            // when there is something to put in it.
            guard rule != nil || planMode != nil else { return }
            var updates = body.nestedUnkeyedContainer(forKey: .updatedPermissions)
            if let planMode {
                var update = updates.nestedContainer(keyedBy: UpdateKey.self)
                try update.encode("setMode", forKey: .type)
                try update.encode(planMode.rawValue, forKey: .mode)
                // Session scope: approving one plan is not a preference to write down.
                try update.encode("session", forKey: .destination)
            }
            if let rule {
                var update = updates.nestedContainer(keyedBy: UpdateKey.self)
                try update.encode("addRules", forKey: .type)
                try update.encode("allow", forKey: .behavior)
                try update.encode(rule.destination.rawValue, forKey: .destination)
                var rules = update.nestedUnkeyedContainer(forKey: .rules)
                var entry = rules.nestedContainer(keyedBy: RuleKey.self)
                try entry.encode(rule.toolName, forKey: .toolName)
                try entry.encodeIfPresent(rule.content, forKey: .ruleContent)
            }
        }
    }
}
