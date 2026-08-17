import Foundation
import Testing

@testable import PerchKit

private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

@Suite("Featured session selection")
struct FeaturedSessionSelectionTests {
    private func session(_ id: String, status: SessionStatus) -> SessionSnapshot {
        SessionSnapshot(
            id: id, cwd: "/lab/\(id)", lastEvent: epoch, lastDetail: "",
            status: status, subagents: 0, startedAt: epoch)
    }

    @Test func aFocusedSessionWinsEvenWhenItIsNotFirst() throws {
        let sessions = [session("working", status: .working), session("focused", status: .idle)]

        let featured = try #require(
            SessionDisplaySelection.featured(in: sessions, focusedSessionId: "focused"))

        #expect(featured.id == "focused")
        #expect(
            SessionDisplaySelection.shown(
                in: sessions, focusedSessionId: "focused", showsAll: false
            ).map(\.id) == ["focused", "working"])
        #expect(
            SessionDisplaySelection.additionalCount(
                in: sessions, focusedSessionId: "focused", showsAll: false) == 0)
    }

    @Test func aHoverShowsTwoCardsAndCountsTheRest() {
        let sessions = [
            session("a", status: .working), session("b", status: .working),
            session("c", status: .idle), session("d", status: .idle),
        ]

        // The focused one leads, the next in list order follows, the other two fold.
        #expect(
            SessionDisplaySelection.shown(in: sessions, focusedSessionId: "c", showsAll: false)
                .map(\.id) == ["c", "a"])
        #expect(
            SessionDisplaySelection.additionalCount(
                in: sessions, focusedSessionId: "c", showsAll: false) == 2)

        // One session is one card and nothing to fold.
        #expect(
            SessionDisplaySelection.shown(
                in: [sessions[0]], focusedSessionId: nil, showsAll: false
            ).map(\.id) == ["a"])
        #expect(
            SessionDisplaySelection.additionalCount(
                in: [sessions[0]], focusedSessionId: nil, showsAll: false) == 0)
    }

    @Test func aMissingFocusFallsBackToTheFirstWorkingSession() throws {
        let sessions = [session("idle", status: .idle), session("working", status: .working)]

        let featured = try #require(
            SessionDisplaySelection.featured(in: sessions, focusedSessionId: "missing"))

        #expect(featured.id == "working")
    }

    @Test func theStripSpeaksForTheWorkingSessionNotTheOneThatJustFinished() throws {
        // The finished turn is the newer event — `Stop` always is — and it still loses.
        var finished = session("finished", status: .idle)
        finished.lastEvent = epoch.addingTimeInterval(60)
        finished.prompt = "Donc la fait moi le grand résumé"
        // Just started, no tool yet: the strip falls back to the project's name.
        let working = session("working", status: .working)

        let priority = try #require(
            SessionDisplaySelection.priority(in: [finished, working]))

        #expect(priority.id == "working")
        #expect(SessionDisplaySelection.compactSummary(for: priority) == "working")
    }

    @Test func amongWorkingSessionsTheOneThatMovedLastLeads() throws {
        // First in the list, but stuck in a six-minute command; the other one just ran
        // a tool. The strip follows the movement.
        var stuck = session("stuck", status: .runningTool)
        stuck.lastEvent = epoch
        var lively = session("lively", status: .runningTool)
        lively.lastEvent = epoch.addingTimeInterval(300)

        #expect(try #require(SessionDisplaySelection.priority(in: [stuck, lively])).id == "lively")

        // And the lead changes hands the moment the other one moves again.
        stuck.lastEvent = epoch.addingTimeInterval(301)
        #expect(try #require(SessionDisplaySelection.priority(in: [stuck, lively])).id == "stuck")
    }

    @Test func aRequestBlockedOnAPersonOutranksAFinishedTurn() throws {
        let sessions = [session("finished", status: .idle), session("asking", status: .needsApproval)]

        #expect(try #require(SessionDisplaySelection.priority(in: sessions)).id == "asking")
    }

    @Test func aFinishedTurnIsStillNamedWhenNothingElseIsRunning() throws {
        var finished = session("finished", status: .idle)
        finished.lastDetail = "Bash: swift test"
        finished.prompt = "Recopier la vibe Island dans Perch"

        let priority = try #require(SessionDisplaySelection.priority(in: [finished]))

        // Vibe's idle pill shows the session title, never the last tool.
        #expect(
            SessionDisplaySelection.compactSummary(for: priority)
                == "Recopier la vibe Island dans Perch")
    }

    @Test func aWorkingSessionIsNamedByWhatItRuns() {
        var working = session("working", status: .runningTool)
        working.lastTool = "Bash"
        working.lastDetail = "swift test"
        working.prompt = "Recopier la vibe Island dans Perch"

        #expect(SessionDisplaySelection.compactSummary(for: working) == "Bash: swift test")

        // A command with no tool recorded is a line of shell with nothing to introduce
        // it: the title says more.
        working.lastTool = nil
        #expect(
            SessionDisplaySelection.compactSummary(for: working)
                == "Recopier la vibe Island dans Perch")
    }

    @Test func showingAllPreservesTheStableSessionOrder() {
        let sessions = [session("first", status: .working), session("second", status: .idle)]

        #expect(
            SessionDisplaySelection.shown(
                in: sessions, focusedSessionId: "second", showsAll: true
            ).map(\.id) == ["first", "second"])
        #expect(
            SessionDisplaySelection.additionalCount(
                in: sessions, focusedSessionId: "second", showsAll: true) == 0)
    }
}

/// `Stop` does not fire on a user interrupt, so the transcript is the only witness that
/// the turn is over — and without it the card said "Writing…" over a CLI at its prompt.
@Test func anInterruptedTurnReadOffTheTranscriptIsOver() {
    var tracker = SessionTracker()
    tracker.record(id: "s1", kind: "UserPromptSubmit", prompt: "fix the strip", at: epoch)
    tracker.record(id: "s1", kind: "PreToolUse", detail: "swift test", tool: "Bash", at: epoch)
    #expect(tracker.sessions["s1"]?.status == .runningTool)

    tracker.setTurn(TranscriptTurn(prompt: "fix the strip", reply: "", isInterrupted: true), for: "s1")
    #expect(tracker.sessions["s1"]?.status == .idle)

    // A turn that is *not* interrupted leaves the state to the hooks.
    tracker.record(id: "s1", kind: "UserPromptSubmit", prompt: "try again", at: epoch)
    tracker.setTurn(TranscriptTurn(prompt: "try again", reply: "On it."), for: "s1")
    #expect(tracker.sessions["s1"]?.status == .working)
}

/// A notification's message is a state, and it is read as one. It is not what the
/// session is doing, and it must not be left under the next turn as though it were.
@Test func aNotificationDoesNotBecomeTheActivityLine() {
    var tracker = SessionTracker()
    tracker.record(id: "s1", kind: "PreToolUse", detail: "swift test", tool: "Bash", at: epoch)
    tracker.record(id: "s1", kind: "Stop", backgroundTasks: [], at: epoch)
    tracker.record(
        id: "s1", kind: "Notification", detail: "Claude is waiting for your input",
        message: "Claude is waiting for your input", at: epoch)
    #expect(tracker.sessions["s1"]?.status == .idle)
    #expect(tracker.sessions["s1"]?.lastDetail == "swift test")

    // The harness's housekeeping line, submitted as a prompt, is not what the card is
    // called either.
    tracker.record(
        id: "s1", kind: "UserPromptSubmit",
        prompt: "2 background agents were stopped by the user: \"Reply with ok\".", at: epoch)
    #expect(tracker.sessions["s1"]?.prompt == nil)
    #expect(SessionTracker.condense("[Request interrupted by user]") == "")
}

@Test func aSessionIsNotDescribedByTheHookThatCreatedIt() {
    var tracker = SessionTracker()
    tracker.record(id: "s1", kind: "SessionStart", cwd: "/lab/perch", detail: "SessionStart", at: epoch)
    #expect(tracker.sessions["s1"]?.lastDetail == "")

    tracker.record(id: "s1", kind: "PreToolUse", detail: "swift test", tool: "Bash", at: epoch)
    #expect(tracker.sessions["s1"]?.lastDetail == "swift test")
    #expect(tracker.sessions["s1"]?.lastTool == "Bash")
}

@Test func stopMakesASessionIdleWithoutRemovingIt() {
    var tracker = SessionTracker()
    tracker.record(id: "s1", kind: "PreToolUse", cwd: "/lab/perch", at: epoch)
    #expect(tracker.workingCount == 1)

    tracker.record(id: "s1", kind: "Stop", at: epoch)
    #expect(tracker.sessions["s1"]?.status == .idle)
    #expect(tracker.workingCount == 0)
    #expect(tracker.sessions.count == 1)
}

@Suite("Completion read state")
struct CompletionReadStateTests {
    @Test("a completion arriving while closed is unread")
    func closedCompletionIsUnread() {
        var tracker = SessionTracker()
        tracker.record(id: "s1", kind: "UserPromptSubmit", at: epoch)
        tracker.record(id: "s1", kind: "Stop", at: epoch)

        #expect(tracker.sessions["s1"]?.isCompletionUnread == true)
    }

    @Test("opening the panel reads existing completions")
    func openingReadsExistingCompletions() {
        var tracker = SessionTracker()
        tracker.record(id: "s1", kind: "UserPromptSubmit", at: epoch)
        tracker.record(id: "s1", kind: "Stop", at: epoch)

        tracker.hold()

        #expect(tracker.sessions["s1"]?.isCompletionUnread == false)
    }

    @Test("a completion visible as it arrives is already read")
    func visibleCompletionStaysRead() {
        var tracker = SessionTracker()
        tracker.record(id: "s1", kind: "UserPromptSubmit", at: epoch)
        tracker.hold()

        tracker.record(id: "s1", kind: "Stop", at: epoch)

        #expect(tracker.sessions["s1"]?.isCompletionUnread == false)
    }

    @Test("an idle Codex session discovered at launch is not new mail")
    func discoveredIdleSessionStartsRead() {
        var tracker = SessionTracker()

        tracker.observe(id: "s1", status: .idle, at: epoch)

        #expect(tracker.sessions["s1"]?.isCompletionUnread == false)
    }

    @Test("new work clears a previous completion")
    func newWorkClearsCompletion() {
        var tracker = SessionTracker()
        tracker.record(id: "s1", kind: "UserPromptSubmit", at: epoch)
        tracker.record(id: "s1", kind: "Stop", at: epoch)

        tracker.record(id: "s1", kind: "UserPromptSubmit", at: epoch)

        #expect(tracker.sessions["s1"]?.isCompletionUnread == false)
    }
}

/// A turn that ends in failure is still an ended turn. Before `StopFailure` was wired up
/// the notch kept spinning on a session that had already given up.
@Test func stopFailureEndsTheTurnToo() {
    var tracker = SessionTracker()
    tracker.record(id: "s1", kind: "PreToolUse", at: epoch)
    tracker.record(id: "s1", kind: "StopFailure", at: epoch)

    #expect(tracker.sessions["s1"]?.status == .failed)
    #expect(tracker.workingCount == 0)
}

@Test func sessionEndRemovesTheSession() {
    var tracker = SessionTracker()
    tracker.record(id: "s1", kind: "SessionStart", at: epoch)
    tracker.record(id: "s1", kind: "SessionEnd", at: epoch)

    #expect(tracker.sessions.isEmpty)
}

@Test func subagentsAreCountedAndNeverGoNegative() {
    var tracker = SessionTracker()
    tracker.record(id: "s1", kind: "SubagentStart", at: epoch)
    tracker.record(id: "s1", kind: "SubagentStart", at: epoch)
    #expect(tracker.subagentCount == 2)

    tracker.record(id: "s1", kind: "SubagentStop", at: epoch)
    #expect(tracker.subagentCount == 1)

    // Started before Perch was running, stops after: must not underflow.
    tracker.record(id: "s1", kind: "SubagentStop", at: epoch)
    tracker.record(id: "s1", kind: "SubagentStop", at: epoch)
    #expect(tracker.subagentCount == 0)
}

/// Nothing announces the end of compaction, so the next event has to clear it.
@Test func compactionIsClearedByTheNextEvent() {
    var tracker = SessionTracker()
    tracker.record(id: "s1", kind: "PreCompact", at: epoch)
    #expect(tracker.sessions["s1"]?.status == .compacting)
    #expect(tracker.sessions["s1"]?.compactingStartedAt == epoch)
    #expect(tracker.workingCount == 1)

    tracker.record(id: "s1", kind: "PreToolUse", at: epoch)
    #expect(tracker.sessions["s1"]?.status == .runningTool)
    #expect(tracker.sessions["s1"]?.compactingStartedAt == nil)
    #expect(tracker.sessions["s1"]?.isWorking == true)
}

/// The states a hook can actually prove, in the order a turn goes through them.
@Test func aTurnMovesThroughTheStatesItsHooksReport() {
    var tracker = SessionTracker()

    tracker.record(id: "s1", kind: "UserPromptSubmit", prompt: "fix auth", at: epoch)
    #expect(tracker.sessions["s1"]?.status == .working)

    tracker.record(id: "s1", kind: "PermissionRequest", tool: "Bash", at: epoch)
    #expect(tracker.sessions["s1"]?.status == .needsApproval)
    #expect(tracker.sessions["s1"]?.status.needsYou == true)
    // Blocked on a person is not "working", whatever the notch badge counts.
    #expect(tracker.workingCount == 0)

    tracker.record(id: "s1", kind: "PreToolUse", detail: "npm run build", at: epoch)
    #expect(tracker.sessions["s1"]?.status == .runningTool)

    tracker.record(id: "s1", kind: "PostToolUse", at: epoch)
    // The tool is done and the model has the turn again — not idle, nothing was handed back.
    #expect(tracker.sessions["s1"]?.status == .working)

    tracker.record(id: "s1", kind: "Stop", at: epoch)
    #expect(tracker.sessions["s1"]?.status == .idle)
}

/// Approving the *asking* of a question was never the point, and the card says so: one
/// wants a decision, the other wants an answer.
@Test func aQuestionWaitsForAnAnswerRatherThanAnApproval() {
    var tracker = SessionTracker()

    tracker.record(id: "s1", kind: "PermissionRequest", tool: "AskUserQuestion", at: epoch)
    #expect(tracker.sessions["s1"]?.status == .waitingForAnswer)

    tracker.record(id: "s2", kind: "PermissionRequest", tool: "ExitPlanMode", at: epoch)
    #expect(tracker.sessions["s2"]?.status == .waitingForAnswer)

    tracker.record(id: "s3", kind: "PermissionRequest", tool: "request_user_input", at: epoch)
    #expect(tracker.sessions["s3"]?.status == .waitingForAnswer)

    tracker.record(id: "s4", kind: "PermissionRequest", tool: "ask", at: epoch)
    #expect(tracker.sessions["s4"]?.status == .waitingForAnswer)
}

@Test func aQuestionReplyReturnsToWorkThenStopsCleanly() {
    var tracker = SessionTracker()

    tracker.record(
        id: "opencode-s1", kind: "PermissionRequest", tool: "AskUserQuestion", at: epoch)
    #expect(tracker.sessions["opencode-s1"]?.status == .waitingForAnswer)

    tracker.record(
        id: "opencode-s1", kind: "PostToolUse", tool: "AskUserQuestion",
        at: epoch.addingTimeInterval(1))
    #expect(tracker.sessions["opencode-s1"]?.status == .working)

    tracker.record(id: "opencode-s1", kind: "Stop", at: epoch.addingTimeInterval(2))
    #expect(tracker.sessions["opencode-s1"]?.status == .idle)
}

/// A card said "waiting for you" until the *next* hook arrived — and for a request nobody
/// answers through Perch, the next hook never does. Answering in the terminal, a request
/// that expired, a session interrupted at the prompt: the decision was resolved, the panel
/// went back to idle, and the row stayed amber for the rest of the session.
@Suite("A resolved request releases its session")
struct AnsweredTests {
    @Test("answering ends the wait without waiting for another hook")
    func answeringEndsTheWait() {
        var tracker = SessionTracker()
        tracker.record(id: "s1", kind: "PermissionRequest", tool: "AskUserQuestion", at: epoch)
        #expect(tracker.sessions["s1"]?.status == .waitingForAnswer)

        tracker.answered(id: "s1", at: epoch)
        // `working`, not `idle`: the answer went back to the model, which now has the turn.
        #expect(tracker.sessions["s1"]?.status == .working)
    }

    @Test("a plain approval is released the same way")
    func approvalIsReleasedToo() {
        var tracker = SessionTracker()
        tracker.record(id: "s1", kind: "PermissionRequest", tool: "Bash", at: epoch)
        #expect(tracker.sessions["s1"]?.status == .needsApproval)

        tracker.answered(id: "s1", at: epoch)
        #expect(tracker.sessions["s1"]?.status == .working)
    }

    /// A decision can resolve after the session has already moved on — the timeout fires a
    /// day later, and quitting resolves everything at once. Neither may drag a card
    /// backwards into a state its own hooks have left behind.
    @Test("a session that has moved on is left alone")
    func doesNotDragASessionBackwards() {
        var tracker = SessionTracker()
        tracker.record(id: "s1", kind: "PermissionRequest", tool: "Bash", at: epoch)
        tracker.record(id: "s1", kind: "Stop", at: epoch)
        #expect(tracker.sessions["s1"]?.status == .idle)

        tracker.answered(id: "s1", at: epoch)
        #expect(tracker.sessions["s1"]?.status == .idle)
    }

    @Test("a session Perch never saw is not invented")
    func unknownSessionIsIgnored() {
        var tracker = SessionTracker()
        tracker.answered(id: "ghost", at: epoch)
        #expect(tracker.sessions["ghost"] == nil)
    }
}

/// Claude Code raises notifications for several reasons; only one of them means the turn
/// has stopped on a person. The others must not knock the card off what it was showing.
@Test func onlyTheWaitingNotificationChangesTheStatus() {
    var tracker = SessionTracker()
    tracker.record(id: "s1", kind: "PreToolUse", at: epoch)

    tracker.record(
        id: "s1", kind: "Notification", message: "Claude needs your permission to use Bash",
        at: epoch)
    #expect(tracker.sessions["s1"]?.status == .runningTool)

    // The same state `Stop` produces. The notification is Claude Code noticing the fact,
    // not a second fact.
    tracker.record(
        id: "s1", kind: "Notification", message: "Claude is waiting for your input", at: epoch)
    #expect(tracker.sessions["s1"]?.status == .idle)
    // And it is not an alert. Every turn ends; a state that every session passes through
    // several times an hour cannot be the one that earns the amber.
    #expect(tracker.sessions["s1"]?.status.needsYou == false)
}

/// Subagents are children now, not a tally: each carries what it was asked for and when it
/// started, which is the question you have ten minutes into a quiet card.
@Test func subagentsCarryTheirLabelAndTheirAge() {
    var tracker = SessionTracker()

    tracker.record(id: "s1", kind: "SubagentStart", subagentLabel: "code-reviewer", at: epoch)
    tracker.record(
        id: "s1", kind: "SubagentStart", subagentLabel: "  ",
        at: epoch.addingTimeInterval(30))

    let children = tracker.sessions["s1"]?.children ?? []
    #expect(children.count == 2)
    #expect(children.first?.label == "code-reviewer")
    // No label in the payload is not a reason to invent one.
    #expect(children.last?.label == "subagent")
    #expect(children.last?.startedAt == epoch.addingTimeInterval(30))

    // No id in these events, so the old reading stands: one of them finished, and the
    // oldest is the honest guess. The completed row remains as context for this turn.
    tracker.record(id: "s1", kind: "SubagentStop", at: epoch.addingTimeInterval(60))
    #expect(tracker.sessions["s1"]?.children.map(\.label) == ["code-reviewer", "subagent"])
    #expect(tracker.sessions["s1"]?.children.first?.completedAt == epoch.addingTimeInterval(60))
    #expect(tracker.subagentCount == 1)
}

/// The id was in the payload the whole time. Two agents launched together and finishing
/// out of order used to swap names on the card, and the row that vanished belonged to the
/// one still running.
@Test func aSubagentStopClosesTheRowItBelongsTo() {
    var tracker = SessionTracker()
    tracker.record(
        id: "s1", kind: "SubagentStart", subagentLabel: "yoda", agentId: "a1", at: epoch)
    tracker.record(
        id: "s1", kind: "SubagentStart", subagentLabel: "obiwan", agentId: "a2",
        at: epoch.addingTimeInterval(5))

    // The second one finishes first, which is the case that was always wrong.
    tracker.record(
        id: "s1", kind: "SubagentStop", agentId: "a2", at: epoch.addingTimeInterval(60))

    #expect(tracker.sessions["s1"]?.children.map(\.label) == ["yoda", "obiwan"])
    #expect(tracker.sessions["s1"]?.children.first?.startedAt == epoch)
    #expect(tracker.sessions["s1"]?.children.last?.completedAt == epoch.addingTimeInterval(60))
    #expect(tracker.subagentCount == 1)

    // An agent older than Perch stops too, and closes nothing it does not own.
    tracker.record(
        id: "s1", kind: "SubagentStop", agentId: "unknown", at: epoch.addingTimeInterval(70))
    #expect(tracker.sessions["s1"]?.children.map(\.label) == ["yoda", "obiwan"])
}

/// Completed children explain the current result but do not leak into the next request.
@Test func completedSubagentsRemainForTheTurnThenClearOnTheNextPrompt() {
    var tracker = SessionTracker()
    tracker.record(
        id: "s1", kind: "SubagentStart", subagentLabel: "reviewer", agentId: "a1",
        at: epoch)
    tracker.record(
        id: "s1", kind: "SubagentStop", agentId: "a1", at: epoch.addingTimeInterval(30))

    #expect(tracker.sessions["s1"]?.children.count == 1)
    #expect(tracker.sessions["s1"]?.completedSubagents == 1)
    #expect(tracker.sessions["s1"]?.subagents == 0)
    #expect(tracker.sessions["s1"]?.hasLiveWork == false)

    tracker.record(
        id: "s1", kind: "UserPromptSubmit", prompt: "start the next task",
        at: epoch.addingTimeInterval(60))
    #expect(tracker.sessions["s1"]?.children.isEmpty == true)
}

/// The bug this whole state exists for: `Stop` fires when background work is *launched*,
/// so a session that delegated anything reported itself finished — and `visible` hid the
/// card — for exactly as long as there was something to watch.
@Test func aTurnThatEndsWithWorkStillRunningIsNotIdle() {
    var tracker = SessionTracker()
    let agent = BackgroundTask(
        id: "a1", kind: "subagent", status: "running", label: "Lot 2A auth HMAC",
        agentType: "yoda")
    let shell = BackgroundTask(
        id: "b1", kind: "shell", status: "running", label: "Watch the CI",
        command: "gh run watch")

    tracker.record(id: "s1", kind: "UserPromptSubmit", prompt: "split the repo", at: epoch)
    tracker.record(
        id: "s1", kind: "SubagentStart", subagentLabel: "Lot 2A auth HMAC", agentId: "a1",
        at: epoch)
    tracker.record(id: "s1", kind: "Stop", backgroundTasks: [agent, shell], at: epoch)

    #expect(tracker.sessions["s1"]?.status == .background)
    // The card stays on screen, which is the entire point.
    #expect(tracker.visible.count == 1)
    #expect(tracker.sessions["s1"]?.isWorking == true)
    // A backgrounded command has no start or stop event of its own; the `Stop` list is
    // the only place it is ever mentioned.
    #expect(tracker.sessions["s1"]?.background.count == 2)
    #expect(tracker.sessions["s1"]?.children.map(\.label) == ["Lot 2A auth HMAC"])

    // Everything came back: now the turn is over, and its completed card remains readable.
    tracker.record(id: "s1", kind: "Stop", backgroundTasks: [], at: epoch.addingTimeInterval(600))
    #expect(tracker.sessions["s1"]?.status == .idle)
    #expect(tracker.sessions["s1"]?.children.count == 1)
    #expect(tracker.sessions["s1"]?.children.first?.completedAt == epoch.addingTimeInterval(600))
    #expect(tracker.sessions["s1"]?.subagents == 0)
    #expect(tracker.visible.count == 1)
}

/// Claude Code lists a session's team members on `Stop` and does not strike a member off
/// when it finishes: an Explore agent from the morning — from the session before a
/// `/clear`, even — was still reported `running` at midnight, and every turn of the day
/// ended in "still running". A subagent this session never saw start, and never saw
/// work, is a ghost.
@Test func aSubagentTheSessionNeverSawIsNotWorkStillRunning() {
    var tracker = SessionTracker()
    let ghost = BackgroundTask(
        id: "perch-ui-inventory@session-7c86f9b8", kind: "subagent", status: "running",
        label: "Repo: /lab/perch (macOS SwiftUI app)", agentType: "Explore")

    tracker.record(id: "s1", kind: "UserPromptSubmit", prompt: "fix the strip", at: epoch)
    tracker.record(id: "s1", kind: "Stop", backgroundTasks: [ghost], at: epoch)

    #expect(tracker.sessions["s1"]?.status == .idle)
    #expect(tracker.sessions["s1"]?.background.isEmpty == true)
    #expect(tracker.sessions["s1"]?.children.isEmpty == true)
    #expect(tracker.sessions["s1"]?.hasLiveWork == false)

    // A shell in the same list is still believed: nothing else ever mentions it.
    let shell = BackgroundTask(id: "b1", kind: "shell", status: "running", command: "gh run watch")
    tracker.record(id: "s1", kind: "Stop", backgroundTasks: [ghost, shell], at: epoch)
    #expect(tracker.sessions["s1"]?.status == .background)
    #expect(tracker.sessions["s1"]?.background.map(\.id) == ["b1"])
}

/// An agent older than the app, or started while it was not listening, is not a ghost
/// the moment it does something: its tool calls arrive under the parent's session with
/// its own id, and that is proof enough for the next `Stop` to count it.
@Test func aSubagentSeenWorkingIsBelievedEvenWithoutItsStart() {
    var tracker = SessionTracker()
    let agent = BackgroundTask(id: "a1", kind: "subagent", status: "running", label: "yoda")

    tracker.record(id: "s1", kind: "PreToolUse", detail: "bun test", agentId: "a1", at: epoch)
    tracker.record(id: "s1", kind: "Stop", backgroundTasks: [agent], at: epoch)

    #expect(tracker.sessions["s1"]?.status == .background)
    #expect(tracker.sessions["s1"]?.children.map(\.id) == ["a1"])
}

/// A CLI that reports no such list — Codex — must not have its subagents wiped by a `Stop`
/// that says nothing about them.
@Test func aStopWithNoBackgroundListLeavesWhatIsKnownAlone() {
    var tracker = SessionTracker()
    tracker.record(id: "s1", kind: "SubagentStart", subagentLabel: "reviewer", at: epoch)
    tracker.record(id: "s1", kind: "Stop", at: epoch.addingTimeInterval(10))

    #expect(tracker.sessions["s1"]?.children.count == 1)
    #expect(tracker.sessions["s1"]?.status == .background)
}

/// A subagent's tool calls arrive under the *parent's* session id. Acting on them put the
/// agent's command on the parent's card and flipped it out of `background` between two
/// `Stop`s, several times a minute, for the whole run.
@Test func aSubagentsToolCallsDoNotMoveTheParentsCard() {
    var tracker = SessionTracker()
    let agent = BackgroundTask(id: "a1", kind: "subagent", status: "running", label: "yoda")

    tracker.record(id: "s1", kind: "PreToolUse", detail: "src/auth.ts", at: epoch)
    tracker.record(id: "s1", kind: "SubagentStart", subagentLabel: "yoda", agentId: "a1", at: epoch)
    tracker.record(id: "s1", kind: "Stop", backgroundTasks: [agent], at: epoch)
    #expect(tracker.sessions["s1"]?.status == .background)

    // The agent runs a command of its own, ten minutes in.
    let later = epoch.addingTimeInterval(600)
    tracker.record(
        id: "s1", kind: "PreToolUse", detail: "bun test", agentId: "a1", at: later)

    #expect(tracker.sessions["s1"]?.status == .background)
    #expect(tracker.sessions["s1"]?.lastDetail == "src/auth.ts")
    // It still counts as a sign of life, so the session does not age out mid-run.
    #expect(tracker.sessions["s1"]?.lastEvent == later)
}

/// A session whose only sign of life is a long agent emits no hooks of its own. Ageing it
/// out deleted the card, children and all, and the `SubagentStop` that eventually arrived
/// recreated a blank, untitled session at the bottom of the list.
@Test func aSessionIsNotAgedOutWhileItsBackgroundWorkRuns() {
    var tracker = SessionTracker(timeout: 30 * 60)
    let agent = BackgroundTask(id: "a1", kind: "subagent", status: "running", label: "yoda")

    tracker.record(id: "s1", kind: "SubagentStart", subagentLabel: "yoda", agentId: "a1", at: epoch)
    tracker.record(id: "s1", kind: "Stop", backgroundTasks: [agent], at: epoch)
    tracker.prune(now: epoch.addingTimeInterval(3 * 3_600))
    #expect(tracker.sessions["s1"] != nil)

    // Once it has come back, the session ages like any other.
    tracker.record(
        id: "s1", kind: "Stop", backgroundTasks: [], at: epoch.addingTimeInterval(3 * 3_600))
    tracker.prune(now: epoch.addingTimeInterval(6 * 3_600))
    #expect(tracker.sessions["s1"] == nil)
}

@Test func cwdAndDetailSurviveEventsThatDoNotCarryThem() {
    var tracker = SessionTracker()
    tracker.record(id: "s1", kind: "PreToolUse", cwd: "/lab/perch", detail: "npm run build", at: epoch)
    tracker.record(id: "s1", kind: "Stop", at: epoch)

    #expect(tracker.sessions["s1"]?.cwd == "/lab/perch")
    #expect(tracker.sessions["s1"]?.lastDetail == "npm run build")
    #expect(tracker.sessions["s1"]?.projectName == "perch")
}

/// The card's activity line should say what the agent is doing, not name the hook that
/// fired. "SubagentStart" is not something anyone wants to read there.
@Test func lifecycleEventsDoNotOverwriteTheActivityLine() {
    var tracker = SessionTracker()
    tracker.record(id: "s1", kind: "PreToolUse", detail: "src/middleware.ts", at: epoch)
    tracker.record(id: "s1", kind: "SubagentStart", detail: "SubagentStart", at: epoch)

    #expect(tracker.sessions["s1"]?.lastDetail == "src/middleware.ts")
    #expect(tracker.sessions["s1"]?.subagents == 1)
}

@Test func theCardTitleFollowsTheLatestPrompt() {
    var tracker = SessionTracker()
    tracker.record(id: "s1", kind: "UserPromptSubmit", cwd: "/lab/perch", prompt: "fix auth bug", at: epoch)
    #expect(tracker.sessions["s1"]?.prompt == "fix auth bug")

    tracker.record(id: "s1", kind: "UserPromptSubmit", prompt: "now ship it", at: epoch)
    #expect(tracker.sessions["s1"]?.prompt == "now ship it")

    // Events without a prompt must not wipe the one we have.
    tracker.record(id: "s1", kind: "PreToolUse", detail: "npm test", at: epoch)
    #expect(tracker.sessions["s1"]?.prompt == "now ship it")
}

/// Prompts are whole messages; the card has one line.
@Test func promptsAreCondensedToTheirFirstMeaningfulLine() {
    #expect(SessionTracker.condense("\n\n  fix the auth bug  \n\nand then deploy") == "fix the auth bug")
    #expect(SessionTracker.condense(String(repeating: "a", count: 100)).count == 73)
    #expect(SessionTracker.condense(String(repeating: "a", count: 100)).hasSuffix("…"))
}

@Test func injectedTaskNotificationsNeverReplaceTheVisiblePrompt() {
    var tracker = SessionTracker()
    tracker.record(
        id: "s1", kind: "UserPromptSubmit", prompt: "review the ingress plan", at: epoch)
    tracker.record(
        id: "s1", kind: "Notification",
        prompt: "<task-notification><task-id>worker-1</task-id></task-notification>",
        at: epoch)

    #expect(tracker.sessions["s1"]?.prompt == "review the ingress plan")
    #expect(
        SessionTracker.condense(
            "<system-reminder>internal</system-reminder>\nship the release") == "ship the release")
}

@Test func teammateTransportMessagesNeverBecomeTheVisiblePrompt() {
    var tracker = SessionTracker()
    tracker.record(
        id: "s1", kind: "UserPromptSubmit", prompt: "finish the Vibe parity audit", at: epoch)
    tracker.record(
        id: "s1", kind: "Notification",
        prompt: """
            Another Claude session sent a message:
            <teammate-message teammate_id="reviewer" summary="done">
            Internal review transport payload.
            </teammate-message>
            """,
        at: epoch)

    #expect(tracker.sessions["s1"]?.prompt == "finish the Vibe parity audit")
    #expect(
        SessionTracker.condense(
            "Another Claude session sent a message:\n<teammate-message>done</teammate-message>")
            .isEmpty)
}

@Test func terminalIdentityIsRememberedAndPrettyPrinted() {
    var tracker = SessionTracker()
    tracker.record(
        id: "s1", kind: "SessionStart",
        client: ClientInfo(terminal: "iTerm.app", session: "w0t1p0"), at: epoch)

    #expect(tracker.sessions["s1"]?.client?.displayName == "iTerm")

    // An event from a hook with no terminal in its environment must not erase it.
    tracker.record(id: "s1", kind: "PreToolUse", client: ClientInfo(), at: epoch)
    #expect(tracker.sessions["s1"]?.client?.displayName == "iTerm")
}

@Test func terminalNamesAreReadable() {
    #expect(ClientInfo(terminal: "Apple_Terminal").displayName == "Terminal")
    #expect(ClientInfo(terminal: "ghostty").displayName == "Ghostty")
    #expect(ClientInfo(terminal: "WarpTerminal").displayName == "Warp")
    #expect(ClientInfo(terminal: "vscode").displayName == "VS Code")
    #expect(ClientInfo(terminal: nil).displayName == nil)
}

@Test func clientInfoIsReadFromTheHooksEnvironment() {
    let info = ClientInfo.fromEnvironment([
        "TERM_PROGRAM": "ghostty", "ITERM_SESSION_ID": "abc", "TMUX_PANE": "%3",
    ])
    #expect(info.terminal == "ghostty")
    #expect(info.session == "abc")
    #expect(info.tmuxPane == "%3")
}

/// Closed terminals never send `SessionEnd`.
@Test func staleSessionsAgeOut() {
    var tracker = SessionTracker(timeout: 60)
    tracker.record(id: "old", kind: "PreToolUse", at: epoch)
    tracker.record(id: "fresh", kind: "PreToolUse", at: epoch.addingTimeInterval(120))

    #expect(tracker.sessions["old"] == nil)
    #expect(tracker.sessions["fresh"] != nil)
}

// MARK: - Permission mode

/// The chip exists to say what an agent may do while nobody is watching, so the plain
/// default earns nothing and everything else earns something.
@Test func onlyANonDefaultPermissionModeEarnsAChip() {
    func badge(_ mode: String?) -> String? {
        var session = SessionSnapshot(
            id: "s", cwd: nil, lastEvent: .now, lastDetail: "", status: .working,
            subagents: 0, startedAt: .now)
        session.permissionMode = mode
        return session.permissionBadge
    }

    #expect(badge(nil) == nil)
    #expect(badge("") == nil)
    #expect(badge("default") == nil)
    #expect(badge("bypassPermissions") == "BYPASS")
    #expect(badge("acceptEdits") == "EDITS")
    #expect(badge("plan") == "PLAN")
}

/// The documented four are not the whole vocabulary — a session running under cmux
/// reports `auto`. A whitelist would have dropped it, and a mode Perch has never heard of
/// is exactly the one worth showing.
@Test func anUnknownPermissionModeIsShownRatherThanHidden() {
    var session = SessionSnapshot(
        id: "s", cwd: nil, lastEvent: .now, lastDetail: "", status: .working,
        subagents: 0, startedAt: .now)

    session.permissionMode = "auto"
    #expect(session.permissionBadge == "AUTO")
    #expect(session.permissionIsPermissive)

    session.permissionMode = "somethingEntirelyNew"
    #expect(session.permissionBadge == "SOMETHIN")

    // "plan" narrows what an agent may do, so it must not read as a warning.
    session.permissionMode = "plan"
    #expect(!session.permissionIsPermissive)
}

/// Active work must never be buried under completed sessions. Within each state group the
/// start order stays stable, so ordinary tool calls do not reshuffle cards under the cursor.
@Test func workingSessionsStayAboveWaitingAndCompletedSessions() {
    var tracker = SessionTracker()
    tracker.record(id: "completed", kind: "Stop", at: epoch)
    tracker.record(id: "working-first", kind: "PreToolUse", at: epoch.addingTimeInterval(60))
    tracker.record(id: "working-second", kind: "UserPromptSubmit", at: epoch.addingTimeInterval(120))
    tracker.record(
        id: "waiting", kind: "PermissionRequest", tool: "Bash",
        at: epoch.addingTimeInterval(180))

    #expect(
        tracker.active.map(\.id)
            == ["working-first", "working-second", "waiting", "completed"])

    tracker.record(
        id: "working-first", kind: "PostToolUse", at: epoch.addingTimeInterval(300))
    #expect(
        tracker.active.map(\.id)
            == ["working-first", "working-second", "waiting", "completed"])

    tracker.record(id: "working-first", kind: "Stop", at: epoch.addingTimeInterval(360))
    #expect(
        tracker.active.map(\.id)
            == ["working-second", "waiting", "completed", "working-first"])
}

/// Two sessions started in the same instant would otherwise be ordered by whatever the
/// dictionary felt like that frame — the same bug, in miniature.
@Test func sessionsStartedTogetherStillHaveAFixedOrder() {
    var tracker = SessionTracker()
    tracker.record(id: "a", kind: "SessionStart", at: epoch)
    tracker.record(id: "b", kind: "SessionStart", at: epoch)

    let order = tracker.active.map(\.id)
    for _ in 0..<20 {
        #expect(tracker.active.map(\.id) == order)
    }
}

/// A list that loses a row while it is being read is worse than one a few seconds out of
/// date: everything below the gap jumps up, and the card you were reading is now a
/// different card.
@Test func nothingLeavesTheListWhileSomeoneIsReadingIt() {
    var tracker = SessionTracker()
    tracker.timeout = 60
    tracker.record(id: "a", kind: "SessionStart", at: epoch)
    tracker.record(id: "b", kind: "SessionStart", at: epoch)
    tracker.record(id: "c", kind: "SessionStart", at: epoch)

    tracker.hold()
    tracker.record(id: "b", kind: "SessionEnd", at: epoch.addingTimeInterval(10))
    // And one that simply went quiet for longer than the timeout.
    tracker.record(id: "c", kind: "PreToolUse", at: epoch.addingTimeInterval(600))

    #expect(tracker.active.map(\.id) == ["a", "b", "c"])

    // Look away and everything that was withheld happens at once: `b` ended, and `a` has
    // now been silent for ten minutes.
    tracker.release(now: epoch.addingTimeInterval(600))
    #expect(tracker.active.map(\.id) == ["c"])
}

/// An explicit archive is different from an automatic disappearance: the row the person
/// chose must leave immediately even while the rest of the list is held steady.
@Test func archiveRemovesTheChosenSessionDuringAHold() {
    var tracker = SessionTracker()
    tracker.record(id: "a", kind: "Stop", at: epoch)
    tracker.record(id: "b", kind: "Stop", at: epoch.addingTimeInterval(1))
    tracker.hold()

    tracker.archive(id: "a")

    #expect(tracker.sessions["a"] == nil)
    #expect(tracker.visible.map(\.id) == ["b"])
}

// MARK: - What the panel shows

/// A turn ending leaves its answer readable until the session itself ends.
@Test func aFinishedTurnStaysInTheListAndTheTracker() {
    var tracker = SessionTracker()
    tracker.record(id: "a", kind: "PreToolUse", at: epoch)
    tracker.record(id: "b", kind: "PreToolUse", at: epoch.addingTimeInterval(60))
    #expect(tracker.visible.map(\.id) == ["a", "b"])

    tracker.record(id: "a", kind: "Stop", at: epoch.addingTimeInterval(120))
    #expect(tracker.visible.map(\.id) == ["b", "a"])
    #expect(tracker.active.map(\.id) == ["b", "a"])
    #expect(tracker.sessions.count == 2)
}

/// The next prompt reuses the completed row in place rather than appending another card.
@Test func theNextTurnReusesTheRowInItsPlace() {
    var tracker = SessionTracker()
    tracker.record(id: "a", kind: "UserPromptSubmit", prompt: "fix the bridge", at: epoch)
    tracker.record(id: "b", kind: "PreToolUse", at: epoch.addingTimeInterval(60))
    tracker.record(id: "a", kind: "Stop", at: epoch.addingTimeInterval(120))
    #expect(tracker.visible.map(\.id) == ["b", "a"])

    tracker.record(id: "a", kind: "UserPromptSubmit", at: epoch.addingTimeInterval(180))
    #expect(tracker.visible.map(\.id) == ["a", "b"])
    #expect(tracker.sessions["a"]?.startedAt == epoch)
    #expect(tracker.sessions["a"]?.title == "fix the bridge")
}

/// Failures, decisions and clean completed turns all remain readable.
@Test func everyResolvedOrActionableTurnRemainsVisible() {
    var tracker = SessionTracker()
    tracker.record(id: "failed", kind: "StopFailure", at: epoch)
    tracker.record(id: "asks", kind: "PermissionRequest", tool: "Bash", at: epoch)
    tracker.record(id: "answers", kind: "PermissionRequest", tool: "AskUserQuestion", at: epoch)
    tracker.record(
        id: "waiting", kind: "Notification", message: "Claude is waiting for your input",
        at: epoch)

    #expect(tracker.visible.map(\.id).sorted() == ["answers", "asks", "failed", "waiting"])
}

/// A turn ending under the cursor remains available after the hold is released.
@Test func aTurnEndingUnderTheCursorKeepsItsRow() {
    var tracker = SessionTracker()
    tracker.record(id: "a", kind: "PreToolUse", at: epoch)

    tracker.hold()
    tracker.record(id: "a", kind: "Stop", at: epoch.addingTimeInterval(10))
    #expect(tracker.visible.map(\.id) == ["a"])

    tracker.release(now: epoch.addingTimeInterval(20))
    #expect(tracker.visible.map(\.id) == ["a"])
}

/// And one that both starts and finishes while you are reading: it earned its row when it
/// appeared, so it keeps it for the rest of the hold rather than blinking out.
@Test func aSessionThatComesAndGoesDuringAHoldStillHoldsStill() {
    var tracker = SessionTracker()
    tracker.record(id: "a", kind: "PreToolUse", at: epoch)
    tracker.hold()

    tracker.record(id: "b", kind: "PreToolUse", at: epoch.addingTimeInterval(10))
    tracker.record(id: "b", kind: "Stop", at: epoch.addingTimeInterval(20))
    #expect(tracker.visible.map(\.id) == ["a", "b"])

    tracker.release(now: epoch.addingTimeInterval(30))
    #expect(tracker.visible.map(\.id) == ["a", "b"])
}

/// A session starting appends. It must not push the list someone is reading downward.
@Test func aNewSessionArrivesAtTheEnd() {
    var tracker = SessionTracker()
    tracker.record(id: "first", kind: "SessionStart", at: epoch)
    tracker.record(id: "second", kind: "SessionStart", at: epoch.addingTimeInterval(60))
    #expect(tracker.active.map(\.id) == ["first", "second"])

    tracker.record(id: "third", kind: "SessionStart", at: epoch.addingTimeInterval(120))
    #expect(tracker.active.map(\.id) == ["first", "second", "third"])
}

/// Forgetting used to be a side effect of remembering: `prune` ran at the end of `record`,
/// so the clock only ticked when another session spoke. The moment stale rows pile up is
/// the moment everything has gone quiet — exactly when nothing was left to trigger it.
@Test func aSilentSessionIsForgottenWithoutAnotherOneSpeaking() {
    var tracker = SessionTracker()
    tracker.timeout = 30 * 60
    tracker.record(id: "abandoned", kind: "Stop", at: epoch)

    // Nothing else happens. Ever. The sweep is what has to remove it.
    tracker.prune(now: epoch.addingTimeInterval(31 * 60))
    #expect(tracker.active.isEmpty)
}

/// The sweep runs twice a minute for the life of the process, so it must be silent when it
/// has nothing to do — otherwise it republishes the whole roster forever.
@Test func aSweepThatRemovesNothingChangesNothing() {
    var tracker = SessionTracker()
    tracker.timeout = 30 * 60
    tracker.record(id: "busy", kind: "PreToolUse", at: epoch)

    let before = tracker.sessions
    tracker.prune(now: epoch.addingTimeInterval(60))
    #expect(tracker.sessions == before)
}

/// Two sessions in identical silence must be reported identically. They were not: `Stop`
/// gave `idle`, the stall notification gave `waitingForInput`, and only the second counted
/// in the notch's amber — so which one you got depended on whether Claude Code happened to
/// notice.
@Test func aFinishedTurnIsWaitingOnYouWhetherOrNotClaudeSaidSo() {
    var tracker = SessionTracker()
    tracker.record(id: "quiet", kind: "PreToolUse", at: epoch)
    tracker.record(id: "quiet", kind: "Stop", at: epoch)

    tracker.record(id: "nagged", kind: "PreToolUse", at: epoch)
    tracker.record(id: "nagged", kind: "Stop", at: epoch)
    tracker.record(
        id: "nagged", kind: "Notification", message: "Claude is waiting for your input",
        at: epoch)

    #expect(tracker.sessions["quiet"]?.status == tracker.sessions["nagged"]?.status)
    #expect(tracker.sessions["quiet"]?.status.needsYou == false)
    #expect(tracker.workingCount == 0)
}

@Suite("Watched sessions")
struct WatchedSessionTests {

    /// The reason `observe` exists at all.
    ///
    /// A watched session's state was first passed through `record` as an invented event
    /// name, and the two names that mapped to the states needed — `UserPromptSubmit` and
    /// `Stop` — are both lifecycle kinds, whose detail `record` throws away on purpose. A
    /// Codex card would have shown no activity line at all except while running a tool.
    @Test func aWatchedSessionKeepsItsActivityLine() {
        var tracker = SessionTracker()
        tracker.observe(
            id: "codex-1", status: .working, cwd: "/x/iautos-mobile",
            detail: "exec: npm test", agent: .codex, aiTitle: "Revoir les tabs")

        let session = tracker.sessions["codex-1"]
        #expect(session?.lastDetail == "exec: npm test")
        #expect(session?.status == .working)
        #expect(session?.agent == .codex)
        #expect(session?.aiTitle == "Revoir les tabs")
        #expect(session?.projectName == "iautos-mobile")
    }

    /// State comes in as state, so it can go anywhere the reducer could put it.
    @Test func aWatchedSessionCanReachAnyStateDirectly() {
        var tracker = SessionTracker()
        for status: SessionStatus in [.working, .runningTool, .idle] {
            tracker.observe(id: "codex-1", status: status, detail: "x")
            #expect(tracker.sessions["codex-1"]?.status == status)
        }
    }

    /// An empty detail is silence, not an instruction to blank the card — the same rule
    /// the hook path follows, so a card cannot tell where it was fed from.
    @Test func anEmptyDetailLeavesTheLastOneStanding() {
        var tracker = SessionTracker()
        tracker.observe(id: "codex-1", status: .runningTool, detail: "exec: npm test")
        tracker.observe(id: "codex-1", status: .idle, detail: "")
        #expect(tracker.sessions["codex-1"]?.lastDetail == "exec: npm test")
        #expect(tracker.sessions["codex-1"]?.status == .idle)
    }

    /// A watched session ages out on the same clock as a hook-fed one.
    @Test func aWatchedSessionIsPrunedLikeAnyOther() {
        var tracker = SessionTracker(timeout: 60)
        tracker.observe(
            id: "codex-1", status: .working, detail: "x",
            at: Date().addingTimeInterval(-3600))
        tracker.prune(now: Date())
        #expect(tracker.sessions["codex-1"] == nil)
    }
}

/// A hook says what a session is doing; only the rollout knows what it is called and which
/// application it runs in. Naming a card must not make it look alive.
@Test func namingASessionSaysNothingAboutWhetherItIsWorking() {
    var tracker = SessionTracker()
    tracker.observe(id: "s1", status: .idle, cwd: "/lab/kit-cgp", detail: "exec", at: epoch)

    tracker.identify(
        id: "s1", aiTitle: "Refondre la modal configuration",
        client: ClientInfo(terminal: "Codex Desktop", session: "019ff878"),
        model: "gpt-5.6-sol", reasoningEffort: "medium", gitBranch: "main")

    let session = tracker.sessions["s1"]
    #expect(session?.aiTitle == "Refondre la modal configuration")
    #expect(session?.model == "gpt-5.6-sol")
    #expect(session?.reasoningEffort == "medium")
    #expect(session?.gitBranch == "main")
    #expect(session?.client?.session == "019ff878")
    #expect(session?.status == .idle)
    #expect(session?.lastEvent == epoch)
}

/// It names what is on screen; it does not resurrect what has aged out.
@Test func namingAnUnknownSessionCreatesNothing() {
    var tracker = SessionTracker()
    tracker.identify(id: "ghost", aiTitle: "x")
    #expect(tracker.sessions["ghost"] == nil)
}
