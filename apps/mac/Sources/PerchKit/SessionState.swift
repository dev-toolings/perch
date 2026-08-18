import Foundation

/// What a session is doing right now, as far as the hooks can tell.
///
/// Claude Code never says "I am idle" — it says `Stop`, and silence afterwards. Every
/// state here is therefore inferred from the last event, which is why the transitions
/// live in one reducer instead of being spread across the UI.
/// Only states a hook can actually prove are here. "Thinking" is not among them: nothing
/// distinguishes a model composing a reply from a model about to call a tool, and a label
/// that is right half the time is worse than one that is coarse and always true.
public enum SessionStatus: String, Sendable, Codable {
    /// The model has the turn, with no tool in flight.
    case working
    /// Between `PreToolUse` and its result. Almost all visible time is spent here, and it
    /// is the state where the command on the card is the thing to read.
    case runningTool
    /// A tool call is held, waiting for someone to allow or deny it.
    case needsApproval
    /// A question or a plan is on screen, waiting for an answer rather than a decision.
    case waitingForAnswer
    /// The turn is over. Nothing is blocked, nothing is owed — it is done.
    ///
    /// There used to be two of these. `Stop` produced `idle`, and the notification Claude
    /// Code raises when a turn stalls produced `waitingForInput` — the same situation, the
    /// same next move, two states, two sentences, and only one of them counted in the
    /// notch's amber. Which of the two you got depended on whether a notification happened
    /// to fire, so two sessions sitting in identical silence were reported differently.
    case idle
    /// The turn ended on a failure.
    case failed
    /// Context is being compacted, which can take a while and otherwise reads as a hang.
    case compacting
    /// The turn is over and the work it started is not: a background agent, or a command
    /// left running.
    ///
    /// `Stop` fires the moment something is launched in the background — not when it comes
    /// back. Every session that delegated anything therefore reported itself finished
    /// while the work was still going, and `visible` hid the card for exactly as long as
    /// there was something to watch. Twenty minutes of an agent working is the one stretch
    /// this app exists for, and it was the one stretch with nothing on screen.
    ///
    /// Not `working`: the model has handed back and is composing nothing. Not `idle`
    /// either, and that is the whole point.
    case background

    /// Something is blocked on a person, and can be unblocked from here. These are the
    /// states worth crossing the room for, and the ones the panel colours ahead of
    /// everything else.
    ///
    /// A finished turn is deliberately not one of them. `idle` was briefly counted here, on
    /// the reasoning that a turn which has ended is waiting on you — which is true and
    /// useless: every turn ends, so every session would spend most of its life amber, and
    /// an alert that is always on is not an alert. What earns the colour is a request held
    /// against a blocked CLI. Done is done.
    public var needsYou: Bool {
        switch self {
        case .needsApproval, .waitingForAnswer: return true
        case .working, .runningTool, .idle, .failed, .compacting, .background: return false
        }
    }

    /// The turn is over and nothing it started is still running: `idle` or `failed`.
    /// `background` is deliberately not finished — the work it left behind is the thing
    /// the card is there to watch.
    public var isFinished: Bool {
        self == .idle || self == .failed
    }
}

/// One subagent running under a session — a fan-out `Task` call, or a member of an Agent
/// Team.
///
/// A count answered "how many"; it never answered "how long has that one been going",
/// which is the question you actually have when a session has been busy for ten minutes.
public struct SubagentRun: Sendable, Equatable, Identifiable {
    /// Claude Code's own `agent_id`, which is what pairs a stop with its own start.
    ///
    /// This used to be a fresh `UUID`, and it is why stops closed the oldest row rather
    /// than the right one: with nothing to match on, "one of them finished" was the only
    /// honest reading. The id was in the payload the whole time.
    ///
    /// A CLI that sends none still gets a row — it falls back to a generated id, and that
    /// row closes oldest-first exactly as before.
    public let id: String
    public var label: String
    public var startedAt: Date
    /// Kept until the next user turn so the panel can show what just finished instead of
    /// making the row disappear at the exact moment it becomes useful context.
    public var completedAt: Date?
    /// What the agent was asked to do — the `description` of the `Task` call that spawned
    /// it, paired with the `SubagentStart` that followed. Vibe prints it in brackets
    /// after the agent's name; a row that only says `obiwan` says who, not what.
    public var task: String?
    /// What the agent is doing right now: its last tool call, in the strip's `Tool: args`
    /// form. Its tool events arrive under the parent's session with the agent's own id,
    /// and used to be dropped on the floor once they had bumped `lastEvent`.
    public var detail: String = ""

    public init(
        id: String? = nil, label: String, startedAt: Date, completedAt: Date? = nil,
        task: String? = nil
    ) {
        self.id = id ?? UUID().uuidString
        self.label = label
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.task = task
    }

    public var isCompleted: Bool { completedAt != nil }

    /// An Agent Team member carries `name@session-xxxxxxxx` for an id; a fan-out
    /// subagent a bare hex id. Vibe lists the two apart — "Team · session-xxxxxxxx" over
    /// "Subagents" — and so does the card.
    public var teamName: String? {
        guard let at = id.firstIndex(of: "@") else { return nil }
        let team = String(id[id.index(after: at)...])
        return team.isEmpty ? nil : team
    }

    /// `@yoda` for a team member — the name it was spawned with — and nothing for a
    /// fan-out subagent, which has no name of its own beyond its type.
    public var memberName: String? {
        guard let at = id.firstIndex(of: "@") else { return nil }
        let name = String(id[..<at])
        return name.isEmpty ? nil : name
    }
}

/// A `Task` call the main loop has made, waiting for the `SubagentStart` that carries
/// the agent's id. See `SessionSnapshot.pendingSpawns`.
struct PendingSpawn: Sendable, Equatable {
    var type: String?
    var task: String
}

public struct SessionSnapshot: Sendable, Equatable {
    /// Public so the off-screen panel preview can fabricate one per case the card has to
    /// handle. Nothing else outside the module builds these — they come from the tracker.
    public init(
        id: String, cwd: String?, lastEvent: Date, lastDetail: String, status: SessionStatus,
        subagents: Int, startedAt: Date
    ) {
        self.id = id
        self.cwd = cwd
        self.lastEvent = lastEvent
        self.lastDetail = lastDetail
        self.status = status
        // The preview builds snapshots by count rather than by name, which is all a
        // fabricated card needs.
        self.children = (0..<max(0, subagents)).map {
            SubagentRun(label: "subagent \($0 + 1)", startedAt: lastEvent)
        }
        self.startedAt = startedAt
    }

    public var id: String
    public var cwd: String?
    public var lastEvent: Date
    public var lastDetail: String
    /// The tool the detail belongs to — `Bash`, `Read`, `exec`. The detail alone is only
    /// the arguments, which is what the card wants; the compact strip wants both, the way
    /// Vibe's pill says `Bash: sed -n 206,…`.
    public var lastTool: String?
    /// `Task` calls the main loop has made whose `SubagentStart` has not arrived yet:
    /// `(type, description)`. The description lives on the tool call and the id on the
    /// start event; this is how the two meet.
    var pendingSpawns: [PendingSpawn] = []
    public var status: SessionStatus
    /// Subagents observed during the current turn — fan-out `Task` calls and Agent Team
    /// members both report through `SubagentStart` / `SubagentStop`.
    ///
    /// Oldest first, and matched by `agent_id`: a stop closes the row it belongs to, not
    /// whichever one started first. Two agents launched together and finishing out of
    /// order used to swap names on the card, and the one still running was the one whose
    /// row disappeared.
    public var children: [SubagentRun] = []

    /// What is still running now that the turn has ended, straight from the `Stop` payload.
    ///
    /// Includes the backgrounded shell commands, which have no start/stop event of their
    /// own and were invisible: `PostToolUse` fires when the command is *launched*, so a
    /// command that ran for twenty minutes was recorded as finished within a second of
    /// starting.
    public var background: [BackgroundTask] = []

    /// How many are running. Kept as the name every caller already used.
    public var subagents: Int { children.count(where: { !$0.isCompleted }) }
    public var completedSubagents: Int { children.count(where: \.isCompleted) }
    /// What the user last asked. This is what makes a card identifiable at a glance:
    /// "fix auth bug" says more than a session id ever will.
    public var prompt: String?
    /// Where it is running, for the card's chip and for a future jump.
    public var client: ClientInfo?
    /// When the session was first seen, which is what the card's age counts from.
    public var startedAt: Date
    /// Which CLI this is. Two agents in the same project are otherwise indistinguishable.
    public var agent: Agent = .claude
    /// The name Claude Code gave this session, read from its own transcript.
    public var aiTitle: String?
    /// Where that transcript is, so the last turn can be re-read while the session runs
    /// rather than only when a hook happens to fire.
    public var transcriptPath: String?
    /// The last exchange: what was asked, and what came back. `nil` until a transcript has
    /// been read — a card without it is the card Perch shipped before, not a broken one.
    public var turn: TranscriptTurn?
    /// The session's permission mode, as Claude Code reports it on every hook.
    public var permissionMode: String?
    /// Runtime identity read from the session's own telemetry when available.
    public var model: String?
    public var reasoningEffort: String?
    public var gitBranch: String?
    /// Start of the current context-compaction episode, when one is active.
    public var compactingStartedAt: Date?
    /// A completed turn that arrived while the panel was not being read.
    public var isCompletionUnread = false

    /// The short, shouted form for the card — and only when it is worth shouting.
    ///
    /// Anything that is not the plain default earns a chip, because every other mode
    /// changes what an agent may do while nobody is watching, which is the whole reason to
    /// look at a panel instead of a terminal.
    ///
    /// Deliberately not a whitelist. The vocabulary is Claude Code's and it is wider than
    /// the documented four — a session running under cmux reports `auto`, which a
    /// whitelist would have silently dropped. An unrecognised mode is shown as it is
    /// spelled rather than hidden: a mode Perch has never heard of is exactly the one
    /// worth seeing.
    public var permissionBadge: String? {
        guard let mode = permissionMode?.trimmingCharacters(in: .whitespaces), !mode.isEmpty,
            mode != "default"
        else { return nil }

        switch mode {
        case "bypassPermissions": return "BYPASS"
        case "acceptEdits": return "EDITS"
        default: return String(mode.prefix(8)).uppercased()
        }
    }

    /// True for the modes that let an agent act without being asked. The chip is tinted
    /// from this: "plan" is a restriction and reads as information, "bypass" is the
    /// opposite and has to read as a warning.
    public var permissionIsPermissive: Bool {
        switch permissionMode {
        case "bypassPermissions", "acceptEdits", "auto": return true
        default: return false
        }
    }

    /// The repository, not the subdirectory: a session in `openbotsmile/apps/web` is the
    /// `openbotsmile` project to everyone who works on it.
    public var projectName: String? {
        cwd.map(ProjectRoot.name(for:))
    }

    /// Everything that proceeds without you. Compaction counts — it is unattended work —
    /// and so does a tool in flight, which is where a busy session spends most of its time.
    /// The states that are blocked on a person deliberately do not.
    public var isWorking: Bool {
        status == .working || status == .runningTool || status == .compacting
            || status == .background
    }

    /// Working harnesses belong at the top of every session surface. Requests blocked on
    /// a person follow them, and completed or failed turns stay readable at the bottom.
    var listPriority: Int {
        if isWorking { return 0 }
        if status.needsYou { return 1 }
        return 2
    }

    /// Work still going with nothing left to announce it.
    ///
    /// A session whose only sign of life is a twenty-minute agent emits no hooks of its
    /// own, so ageing it out on `lastEvent` deleted the card — children and all — and the
    /// `SubagentStop` that eventually arrived recreated a blank, untitled session at the
    /// bottom of the list. A backgrounded shell command is worse: it never emits anything
    /// at all.
    public var hasLiveWork: Bool { !background.isEmpty || subagents > 0 }

    /// The card's heading: the prompt if we have one, the project otherwise.
    /// What the card calls this session. Claude Code's own name first — it is the one you
    /// will see again in `claude --resume`, so two places agreeing beats Perch inventing
    /// a second name for the same work.
    public var title: String {
        if let aiTitle, !aiTitle.isEmpty { return aiTitle }
        if let prompt, !prompt.isEmpty { return prompt }
        return projectName ?? "session"
    }
}

/// Chooses the session that owns the featured card without reordering the underlying
/// stable list. Vibe keeps the last consulted session through a collapse; if that focus
/// is gone, active work is the only useful fallback.
public enum SessionDisplaySelection {
    public static func featured(
        in sessions: [SessionSnapshot], focusedSessionId: String?
    ) -> SessionSnapshot? {
        if let focusedSessionId,
            let focused = sessions.first(where: { $0.id == focusedSessionId })
        {
            return focused
        }
        return sessions.first(where: \.isWorking) ?? sessions.first
    }

    /// How many cards a hover shows before the rest fold into "+N more sessions". Two:
    /// the one you are reading and the one after it, which is usually the other harness
    /// you are running — one card hid it, and every card is a panel you have to scroll.
    public static let hoverLimit = 2

    /// The featured session first, then the list order, up to `limit`; everything past
    /// that is what "+N more sessions" counts.
    public static func shown(
        in sessions: [SessionSnapshot], focusedSessionId: String?, showsAll: Bool,
        limit: Int = hoverLimit
    ) -> [SessionSnapshot] {
        if showsAll { return sessions }
        guard let first = featured(in: sessions, focusedSessionId: focusedSessionId) else {
            return []
        }
        let rest = sessions.filter { $0.id != first.id }.prefix(max(0, limit - 1))
        return [first] + rest
    }

    public static func additionalCount(
        in sessions: [SessionSnapshot], focusedSessionId: String?, showsAll: Bool
    ) -> Int {
        max(0, sessions.count - shown(
            in: sessions, focusedSessionId: focusedSessionId, showsAll: showsAll
        ).count)
    }

    /// The session the compact strip speaks for — Vibe's priority session.
    ///
    /// This was the most recently touched session, which is the wrong one the moment a
    /// turn ends: `Stop` is the newest event by definition, so the strip named the
    /// session that had just *finished* while another was still working — an animated
    /// mark next to the title of something at rest. Work in flight outranks a request
    /// blocked on a person, which outranks a finished turn.
    ///
    /// Inside the group, though, recency is the point. Two harnesses at work and the
    /// strip pinned to the *first* one — six minutes into a `sleep`-loop — is a label
    /// that never changes while the other session runs a tool a second. The strip
    /// exists to show that something is moving, so it follows the one that moved last.
    public static func priority(in sessions: [SessionSnapshot]) -> SessionSnapshot? {
        let group =
            sessions.filter(\.isWorking).nonEmpty
            ?? sessions.filter(\.status.needsYou).nonEmpty
            ?? sessions
        return group.max { ($0.lastEvent, $0.id) < ($1.lastEvent, $1.id) }
    }

    /// What the strip says about that session. Vibe's `priorityCompactTitle` is the
    /// work in flight — the tool and the start of its arguments, `Bash: sed -n 206,…` —
    /// while a harness works, and the session's own title once the turn is over or when
    /// nothing says what the work is.
    public static func compactSummary(for session: SessionSnapshot) -> String {
        guard session.isWorking else { return session.title }
        return CompactActivityLabel.line(tool: session.lastTool, detail: session.lastDetail)
            ?? session.title
    }
}

/// The session state machine, kept pure so it can be tested without a running app.
public struct SessionTracker: Sendable {
    /// A session with no hook traffic for this long is treated as gone. Terminals that
    /// are closed outright never send `SessionEnd`.
    public var timeout: TimeInterval

    public private(set) var sessions: [String: SessionSnapshot] = [:]

    public init(timeout: TimeInterval = 30 * 60) {
        self.timeout = timeout
    }

    /// Attaches a freshly read turn. Silent when the session is gone: the read that
    /// produced it started while it was still on screen.
    public mutating func setTurn(_ turn: TranscriptTurn, for id: String) {
        guard var session = sessions[id] else { return }
        session.turn = turn
        // A turn the person cut short is over, and no hook says so: `Stop` does not fire
        // on an interrupt. Left alone, the card kept "Writing…" and a green dot, and the
        // strip kept counting a harness at work, for a CLI sitting at its prompt.
        if turn.isInterrupted, session.status == .working || session.status == .runningTool {
            session.status = .idle
        }
        sessions[id] = session
    }

    /// Records a session Perch is *watching* rather than being told about.
    ///
    /// Everything below arrives as a hook: an event name, which the switch at the end turns
    /// into a state. Codex desktop sessions arrive as a file being written — the reader has
    /// already worked out the state, and there is no event to name. Passing one anyway meant
    /// choosing a hook whose side effects happened to be right, and the two that mapped to
    /// the states needed here, `UserPromptSubmit` and `Stop`, are both in `lifecycleKinds`:
    /// their detail is deliberately dropped, because "SubagentStart" is not what a card
    /// should say. A watched session would have lost its activity line to that rule.
    ///
    /// So the state comes in as a state. Everything else — the merge, the hold, the pruning
    /// — is what `record` does, because a card should not be able to tell where it came from.
    public mutating func observe(
        id: String,
        status: SessionStatus,
        cwd: String? = nil,
        detail: String = "",
        prompt: String? = nil,
        agent: Agent? = nil,
        aiTitle: String? = nil,
        client: ClientInfo? = nil,
        model: String? = nil,
        reasoningEffort: String? = nil,
        gitBranch: String? = nil,
        at date: Date = .now
    ) {
        let previousStatus = sessions[id]?.status
        var session =
            sessions[id]
            ?? SessionSnapshot(
                id: id, cwd: cwd, lastEvent: date, lastDetail: detail,
                status: status, subagents: 0, startedAt: date)

        session.cwd = cwd ?? session.cwd
        session.lastEvent = date
        if !detail.isEmpty { session.lastDetail = detail }
        if let prompt, !prompt.isEmpty { session.prompt = prompt }
        if let agent { session.agent = agent }
        if let aiTitle, !aiTitle.isEmpty { session.aiTitle = aiTitle }
        if let model, !model.isEmpty { session.model = model }
        if let reasoningEffort, !reasoningEffort.isEmpty {
            session.reasoningEffort = reasoningEffort
        }
        if let gitBranch, !gitBranch.isEmpty { session.gitBranch = gitBranch }
        // Never cleared by a later observation: where a session runs is fixed for its
        // lifetime, and a read that happens not to carry it must not take the chip away.
        if let client { session.client = client }
        session.status = status
        updateCompletionReadState(
            of: &session, previousStatus: previousStatus, acceptsInitialCompletion: false)

        sessions[id] = session
        if holdsSteady, status != .idle { heldVisible.insert(id) }
        prune(now: date)
    }

    /// Says what a session *is*, without claiming anything about what it is doing.
    ///
    /// Identity and liveness come from different places for Codex: the hook reports the
    /// work, and only the rollout knows the thread's name and the application it runs in.
    /// So this touches neither `status` nor `lastEvent` — a card must not look alive
    /// because something read its name off disk.
    ///
    /// Unknown sessions are ignored: this names what is already on screen, it does not
    /// bring anything back.
    public mutating func identify(
      id: String, aiTitle: String? = nil, client: ClientInfo? = nil,
        model: String? = nil, reasoningEffort: String? = nil, gitBranch: String? = nil,
        prompt: String? = nil
    ) {
        guard var session = sessions[id] else { return }
        if let aiTitle, !aiTitle.isEmpty { session.aiTitle = aiTitle }
        if let client { session.client = client }
        if let model, !model.isEmpty { session.model = model }
        if let reasoningEffort, !reasoningEffort.isEmpty {
            session.reasoningEffort = reasoningEffort
        }
        if let gitBranch, !gitBranch.isEmpty { session.gitBranch = gitBranch }
        // Codex Desktop has the authoritative human prompt in its rollout. A hook can
        // observe the same session, but its payload may be the JavaScript control call
        // that caused the hook to fire. Keep the rollout's clean prompt when it is known.
        if let prompt, !prompt.isEmpty { session.prompt = prompt }
        sessions[id] = session
    }

    /// The request this session was blocked on has been resolved.
    ///
    /// A session enters `needsApproval` or `waitingForAnswer` on a `PermissionRequest` and
    /// used to leave it only on the *next* hook — which normally arrives, because answering
    /// runs the tool. Normally. A question answered in the terminal, a request that expired,
    /// a session interrupted at the prompt, Perch quitting: in all of those the decision is
    /// resolved and no further event ever comes, so the card sat on "waiting for you"
    /// permanently. The panel said a session was blocked when nothing was.
    ///
    /// So the resolution itself says so. `working` rather than `idle`, for the same reason
    /// `PostToolUse` does: the answer went back to the model, and the model has the turn —
    /// nothing has been handed to a person yet.
    ///
    /// Only lifts a wait. Anything else is a later event that already knows better than
    /// this one — a decision resolving while the session has moved on must not drag it
    /// backwards.
    public mutating func answered(id: String, at date: Date = .now) {
        guard var session = sessions[id], session.status.needsYou else { return }
        session.status = .working
        session.lastEvent = date
        sessions[id] = session
    }

    public mutating func record(
        id: String,
        kind: String,
        cwd: String? = nil,
        detail: String = "",
        prompt: String? = nil,
        client: ClientInfo? = nil,
        agent: Agent? = nil,
        aiTitle: String? = nil,
        transcriptPath: String? = nil,
        turn: TranscriptTurn? = nil,
        permissionMode: String? = nil,
        /// The tool the event is about. `PermissionRequest` carries `AskUserQuestion` or
        /// `ExitPlanMode` when what is waiting is an answer rather than a decision, and
        /// those read differently on a card.
        tool: String? = nil,
        /// A `Notification`'s text, which is the only place Claude Code says out loud that
        /// it is stalled on the user rather than working.
        message: String? = nil,
        /// What a subagent is, when the payload says. Fan-out `Task` calls carry the type
        /// they were asked for.
        subagentLabel: String? = nil,
        /// On the `Task` call itself: the `subagent_type` it asks for, so the description
        /// can be paired with the right start when several are spawned at once.
        spawnType: String? = nil,
        /// Which subagent the event is about, when it is not the main loop's.
        agentId: String? = nil,
        /// What is still running, as `Stop` reports it. `nil` means the event does not
        /// carry the list, which is not the same as the list being empty — only `Stop` and
        /// `SubagentStop` say, and everything else must leave what is known alone.
        backgroundTasks: [BackgroundTask]? = nil,
        at date: Date = .now
    ) {
        if kind == "SessionEnd" {
            remove(id: id)
            return
        }

        // A tool call made by a subagent arrives under the *parent's* session id, carrying
        // the agent's own id. It is the subagent's work, not the session's: letting it
        // through put the agent's command on the parent's card and flipped the card back
        // out of `background` between two `Stop`s, several times a minute, for the whole
        // length of the run. The event still counts as a sign of life — it keeps the
        // session from ageing out — but it does not get to say what the session is doing.
        let belongsToSubagent = agentId != nil && !Self.subagentLifecycle.contains(kind)

        let previousStatus = sessions[id]?.status
        // Born blank, and given its detail by the same rule as every later event. The
        // first event of a session is almost always `SessionStart`, and seeding the row
        // with its detail printed the hook's own name — "SessionStart" — as what the
        // session was doing, right up to the first tool call.
        var session =
            sessions[id]
            ?? SessionSnapshot(
                id: id, cwd: cwd, lastEvent: date, lastDetail: "",
                status: .working, subagents: 0, startedAt: date)

        session.cwd = cwd ?? session.cwd
        session.lastEvent = date
        // Lifecycle events carry no detail worth showing — letting them through put
        // "SubagentStart" on the card where the file being edited belongs.
        if !detail.isEmpty, !Self.lifecycleKinds.contains(kind), !belongsToSubagent {
            session.lastDetail = detail
            session.lastTool = tool.flatMap { $0.isEmpty ? nil : $0 }
        }
        // A new prompt replaces the old one: the card should describe the current task,
        // not the one it opened with.
        if let prompt {
            let visiblePrompt = Self.condense(prompt)
            if !visiblePrompt.isEmpty { session.prompt = visiblePrompt }
        }
        if let client, client != ClientInfo() { session.client = client }
        if let agent { session.agent = agent }
        // The title is refined as the session goes, so a later one replaces an earlier.
        if let aiTitle, !aiTitle.isEmpty { session.aiTitle = aiTitle }
        if let transcriptPath, !transcriptPath.isEmpty { session.transcriptPath = transcriptPath }
        // A turn is only ever replaced by a newer reading of the same file, never blanked:
        // a hook that fires between two reads would otherwise clear the panel for a frame.
        if let turn { session.turn = turn }
        // Toggled mid-session with shift+tab, so the latest event is the truth.
        if let permissionMode, !permissionMode.isEmpty { session.permissionMode = permissionMode }
        if kind != "PreCompact", session.status == .compacting {
            session.compactingStartedAt = nil
        }
        // A child summary belongs to one user turn. Completed rows stay long enough to
        // explain the result, then the next prompt starts with a clean delegation list.
        if kind == "UserPromptSubmit" {
            session.children.removeAll(where: \.isCompleted)
            session.pendingSpawns.removeAll()
        }

        switch kind {
        case _ where belongsToSubagent:
            // The event has already done its one job above: it moved `lastEvent`, so the
            // session does not age out while its agent works. One more thing, for an
            // agent Perch never saw start — older than the app, or started while it was
            // not listening: a tool call is proof of life, and it earns the row that
            // `SubagentStart` would have given it, so the next `Stop` believes it.
            if let agentId, !session.children.contains(where: { $0.id == agentId }) {
                session.children.append(
                    SubagentRun(id: agentId, label: Self.subagentName(nil), startedAt: date))
            }
            // And what it is doing, for the row: the last tool it called, the way the
            // strip would say it. Only calls; a `PostToolUse` says nothing new.
            if let agentId, kind == "PreToolUse",
                let index = session.children.firstIndex(where: { $0.id == agentId }),
                let line = CompactActivityLabel.line(tool: tool, detail: detail)
            {
                session.children[index].detail = line
            }
        case "SubagentStart":
            // Keyed by the agent's own id, so a start seen twice — a reconnect, a replayed
            // event — does not put the same agent on the card twice.
            if agentId == nil || !session.children.contains(where: { $0.id == agentId }) {
                // The `Task` call that asked for this agent said what for; the start
                // event says which id it got. Pair by type when the type is known —
                // several agents of one type spawned together pair in order — and by
                // order alone otherwise.
                let spawnIndex =
                    session.pendingSpawns.firstIndex { $0.type == nil || $0.type == subagentLabel }
                    ?? (session.pendingSpawns.isEmpty ? nil : 0)
                let task = spawnIndex.map { session.pendingSpawns.remove(at: $0).task }
                session.children.append(
                    SubagentRun(
                        id: agentId, label: Self.subagentName(subagentLabel), startedAt: date,
                        task: task))
            }
            session.status = .working
        case "SubagentStop":
            // By id, so the row that closes is the one that finished. An id Perch never saw
            // start — an agent older than the app — closes nothing here, and the `Stop`
            // that follows reconciles the list against what is actually running.
            if let agentId {
                if let index = session.children.firstIndex(where: { $0.id == agentId }) {
                    session.children[index].completedAt = date
                }
            } else if let index = session.children.firstIndex(where: { !$0.isCompleted }) {
                // Oldest first, for a CLI that sends no id. This is what it always did.
                session.children[index].completedAt = date
            }
        case "PreCompact":
            session.status = .compacting
            session.compactingStartedAt = date
        case "Stop":
            // The turn ending is not the work ending. `Stop` fires when something is
            // launched in the background, not when it comes back, and the payload carries
            // the list of what is still going — so this is read, not guessed.
            if let backgroundTasks {
                session.background = Self.credible(
                    backgroundTasks.filter(\.isRunning), children: session.children, session: id)
                session.children = Self.reconcile(session.children, with: session.background, at: date)
                // An agent still out is the turn not being over: it will come back with
                // work, and the card is the only place that says so. A shell left in the
                // background is not: a `Monitor` waits an hour for a log line, a build
                // grinds on, and the terminal is at its prompt the whole time — five of
                // them kept a finished session "working", green dot and all, while the
                // person could see nothing running. Shells are kept (they hold the row
                // and are listed) but they do not make the turn a working one.
                session.status = session.background.contains(where: \.isSubagent) ? .background : .idle
            } else {
                // A CLI that reports no such list — Codex — leaves only what the subagent
                // events already said.
                session.status = session.subagents == 0 ? .idle : .background
            }
        case "StopFailure":
            session.status = .failed
        case "PermissionRequest":
            // The tool being asked about decides which kind of waiting this is: a command
            // wants a decision, a question wants an answer, and they are not the same
            // interruption.
            session.status = Self.answerTools.contains(tool ?? "") ? .waitingForAnswer : .needsApproval
        case "Notification":
            // Claude Code raises these for several reasons; only one of them means the
            // turn has stopped and is waiting on a person — and it says nothing `Stop` did
            // not already say, so it lands on the same state.
            //
            // Unless something is still running: "waiting for your input" and "an agent is
            // working" are both true at once, and the one worth showing is the one you
            // cannot see from the terminal.
            let stalled = Self.saysWaitingForInput(message ?? detail)
            session.status =
                stalled ? (session.background.isEmpty ? .idle : .background) : session.status
        case "PreToolUse":
            session.status = .runningTool
            // A fan-out call: remember what it asked for until its agent announces itself.
            if let tool, Self.spawnTools.contains(tool), !detail.isEmpty {
                session.pendingSpawns.append(PendingSpawn(type: spawnType, task: detail))
            }
        case "PostToolUse", "PostToolUseFailure", "PermissionDenied":
            // The tool is done; the model has the turn again. Not `idle` — nothing has
            // been handed back yet.
            session.status = .working
        default:
            // Anything else is the session doing something, which also ends compaction —
            // there is no event announcing that compaction finished.
            session.status = .working
        }

        updateCompletionReadState(
            of: &session, previousStatus: previousStatus, acceptsInitialCompletion: true)

        sessions[id] = session
        // A session that turns up while the list is held earns its row for the rest of the
        // hold: one that starts and finishes under the cursor should not blink out of it.
        if holdsSteady, session.status != .idle { heldVisible.insert(id) }
        prune(now: date)
    }

    static let lifecycleKinds: Set<String> = [
        "SessionStart", "Stop", "StopFailure", "SubagentStart", "SubagentStop", "PreCompact",
        "UserPromptSubmit",
        // Its message is a state — "waiting for your input", "needs your permission" —
        // and it is read as one above. Kept as the activity line, it outlived the state
        // it described: the next prompt put the card back to work with "Claude is
        // waiting for your input" still written under it.
        "Notification",
    ]

    /// The two tools whose permission prompt is really a question. Approving the *asking*
    /// of a question was never the point — the answer is.
    static let answerTools: Set<String> = [
        "AskUserQuestion", "ask", "request_user_input", "functions.request_user_input",
        "ExitPlanMode",
    ]

    /// Matched on substance rather than on the exact sentence: the wording of this
    /// notification has changed between Claude Code releases, and a card that silently
    /// stops reporting "waiting for you" is worse than one that occasionally does not.
    static func saysWaitingForInput(_ message: String) -> Bool {
        let text = message.lowercased()
        return text.contains("waiting for your input") || text.contains("is waiting for")
    }

    /// The events that are *about* a subagent rather than *from* one. Both carry an
    /// `agent_id`, and only these two are the session's business to act on.
    static let subagentLifecycle: Set<String> = ["SubagentStart", "SubagentStop"]

    /// The tools that spawn an agent. `Task` is Claude Code's name; `Agent` its newer one.
    static let spawnTools: Set<String> = ["Task", "Agent"]

    /// Brings the child rows in line with what `Stop` says is actually running.
    ///
    /// The rows Perch built from `SubagentStart` are kept where they match, because they
    /// know when the agent started and the `Stop` list does not say. Anything running with
    /// no row yet gets one: an agent launched before Perch was — or before its hooks were
    /// installed — is otherwise invisible for the whole of its run.
    /// The part of a `Stop` payload's live list that is worth believing.
    ///
    /// Claude Code lists a session's team members there, and a member is not struck off
    /// when it finishes: an Explore agent spawned in the morning, in the session before a
    /// `/clear`, was still reported `running` at midnight — so every turn of the day ended
    /// in "still running", the card never went to Done, the strip kept counting a harness
    /// at work, and the row could never age out. The list is the only word there is on
    /// backgrounded shells, which emit no hook of their own, so those are taken as they
    /// come. A subagent, though, announces itself: `SubagentStart` arrives before it does
    /// anything, and one this session never saw start — and has not seen stop — is a
    /// ghost, not work.
    static func credible(
        _ running: [BackgroundTask], children: [SubagentRun], session: String
    ) -> [BackgroundTask] {
        running.filter { task in
            guard task.isSubagent else { return true }
            let known = children.contains { $0.id == task.id && !$0.isCompleted }
            if !known {
                PerchLog.info(
                    "ignoring background subagent \(task.id) (\(task.agentType ?? "?")) "
                        + "the session \(session.prefix(8)) never saw start")
            }
            return known
        }
    }

    static func reconcile(
        _ children: [SubagentRun], with running: [BackgroundTask], at date: Date
    ) -> [SubagentRun] {
        let subagents = running.filter(\.isSubagent)
        let live = Set(subagents.map(\.id))
        var rows = children
        for index in rows.indices where !rows[index].isCompleted {
            if live.contains(rows[index].id) {
                rows[index].completedAt = nil
            } else {
                rows[index].completedAt = date
            }
        }
        let known = Set(rows.map(\.id))
        for task in subagents where !known.contains(task.id) {
            rows.append(
                SubagentRun(id: task.id, label: subagentName(task.displayName), startedAt: date))
        }
        return rows
    }

    /// A fan-out `Task` says what it asked for; an Agent Team member says who it is. When
    /// the payload says neither, the count is still the useful part.
    static func subagentName(_ label: String?) -> String {
        guard let label = label?.trimmingCharacters(in: .whitespaces), !label.isEmpty else {
            return "subagent"
        }
        return condense(label, limit: 32)
    }

    /// Prompts arrive as whole messages — paragraphs, pasted logs, command output. The
    /// card has one line, so take the first meaningful one and stop.
    public static func condense(_ prompt: String, limit: Int = 72) -> String {
        let wrappers =
            "command-name|command-message|command-args|local-command-stdout|"
            + "system-reminder|task-notification|teammate-message|user-prompt-submit-hook"
        var visible = prompt.replacingOccurrences(
            of: "<(\(wrappers))(?: [^>]*)?>[\\s\\S]*?</\\1>", with: "",
            options: .regularExpression)
        visible = visible.replacingOccurrences(
            of: "(?m)^Another Claude session sent a message:\\s*$", with: "",
            options: .regularExpression)
        let firstLine =
            visible
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(String.init) ?? visible

        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        // Written by the harness in the user's voice, and submitted as a prompt all the
        // same. Not what anyone asked, so not what the card is called.
        if Transcript.isHarnessNotice(trimmed) || Transcript.isInterruptMarker(trimmed) {
            return ""
        }
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    public mutating func drop(id: String) {
        remove(id: id)
    }

    /// Removes a row immediately because the person reading it explicitly asked to.
    /// Automatic removals wait while the panel is held steady; an archive button must not.
    public mutating func archive(id: String) {
        sessions.removeValue(forKey: id)
        heldVisible.remove(id)
        withheld.remove(id)
    }

    public mutating func prune(now: Date = .now) {
        // Zero means never. Claude Code always sends `SessionEnd`, so a user who only runs
        // it can turn ageing off entirely and never lose a long-running session.
        guard !holdsSteady, timeout > 0 else { return }
        let cutoff = now.addingTimeInterval(-timeout)
        let survivors = sessions.filter { $0.value.lastEvent > cutoff || $0.value.hasLiveWork }
        // Assigning unconditionally would publish a change every time this is called, and
        // it is now called on a timer — two pointless redraws a minute, forever.
        guard survivors.count != sessions.count else { return }
        sessions = survivors
    }

    // MARK: - Holding still

    /// True while someone is looking at the panel.
    ///
    /// A list that removes a row while it is being read is worse than one that is a few
    /// seconds out of date: everything below the gap jumps up, and the card you were
    /// reading is now a different card. So while the panel is open nothing leaves the
    /// list — a session that ends keeps its row, marked as ended, until you look away.
    ///
    /// Only the roster is held. What each row *says* stays live, which is the entire
    /// reason to have the panel open.
    public private(set) var holdsSteady = false

    /// Removals that arrived while the list was held.
    private var withheld: Set<String> = []

    /// Rows that must stay on screen for as long as the list is held, because they were on
    /// it when someone started reading. A turn finishing is a removal like any other: it
    /// waits until you look away.
    private var heldVisible: Set<String> = []

    public mutating func hold() {
        holdsSteady = true
        markAllCompletionsRead()
        heldVisible = Set(visible.map(\.id))
    }

    /// Opening the panel reads every completion currently displayed.
    public mutating func markAllCompletionsRead() {
        for id in sessions.keys where sessions[id]?.isCompletionUnread == true {
            sessions[id]?.isCompletionUnread = false
        }
    }

    /// Lets go, and applies everything that was withheld.
    public mutating func release(now: Date = .now) {
        holdsSteady = false
        heldVisible = []
        for id in withheld { sessions.removeValue(forKey: id) }
        withheld = []
        prune(now: now)
    }

    private mutating func remove(id: String) {
        guard holdsSteady else {
            sessions.removeValue(forKey: id)
            return
        }
        withheld.insert(id)
    }

    private func updateCompletionReadState(
        of session: inout SessionSnapshot,
        previousStatus: SessionStatus?,
        acceptsInitialCompletion: Bool
    ) {
        let isCompleted = session.status.isFinished
        guard isCompleted else {
            session.isCompletionUnread = false
            return
        }
        guard previousStatus != session.status else { return }
        guard previousStatus != nil || acceptsInitialCompletion else { return }
        session.isCompletionUnread = !holdsSteady
    }

    /// Every live session, grouped by what deserves attention now.
    ///
    /// This was `lastEvent` descending — most recently active first — which sounds right
    /// and is unusable the moment more than one agent is running. Every tool call in any
    /// session promotes that card to the top and pushes the others down, so with six
    /// agents the list reshuffles several times a second: the card you are reading slides
    /// away, the one you were about to click moves out from under the cursor, and ⌃⌥P
    /// cycles in a different order on every press because the switcher indexes into this
    /// array.
    ///
    /// Working sessions come first, then sessions waiting on a person, then finished
    /// sessions. Inside each group the start time never changes, so ordinary hook traffic
    /// cannot reshuffle peers under the cursor.
    ///
    /// The id breaks ties: two sessions started in the same instant would otherwise be
    /// ordered by whatever the dictionary felt like, which is the same bug in miniature.
    public var active: [SessionSnapshot] {
        sessions.values.sorted {
            if $0.listPriority != $1.listPriority {
                return $0.listPriority < $1.listPriority
            }
            return ($0.startedAt, $0.id) < ($1.startedAt, $1.id)
        }
    }

    /// What the panel shows. Vibe keeps a completed turn visible until the session itself
    /// ends, so its answer can be read from the completion card. `SessionEnd` and timeout
    /// pruning still remove stale sessions; `Stop` only ends one turn.
    public var visible: [SessionSnapshot] {
        active
    }

    public var workingCount: Int {
        sessions.values.filter(\.isWorking).count
    }

    /// Subagents running across every session, which is what the notch summarises.
    public var subagentCount: Int {
        sessions.values.reduce(0) { $0 + $1.subagents }
    }
}

extension Array {
    /// Nil rather than empty, so a chain of fallbacks can be written as one expression.
    fileprivate var nonEmpty: [Element]? { isEmpty ? nil : self }
}
