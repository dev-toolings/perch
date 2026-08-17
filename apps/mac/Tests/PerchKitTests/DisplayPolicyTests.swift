import Testing

@testable import PerchKit

@Suite("Vibe display policy")
struct DisplayPolicyTests {
  @Test func aHiddenSessionCannotReenterThroughACompletionEvent() {
    let session = SessionSnapshot(
      id: "session-1", cwd: "/tmp", lastEvent: .now, lastDetail: "done",
      status: .idle, subagents: 0, startedAt: .now)

    let hidden = DisplaySessionEligibility.resolve(
      storedSession: session, isHidden: true, eventShell: nil)
    #expect(hidden.policy == .hidden)
    #expect(!hidden.allowsDisplay)
    #expect(!hidden.usedEventShell)

    let visible = DisplaySessionEligibility.resolve(
      storedSession: session, isHidden: false, eventShell: nil)
    #expect(visible.policy == .visible)
    #expect(visible.allowsDisplay)
    #expect(visible.session?.id == "session-1")
  }

  @Test func anEventShellIsOnlyUsedWhenNoStoredSessionExists() {
    let shell = SessionSnapshot(
      id: "event", cwd: nil, lastEvent: .now, lastDetail: "warning",
      status: .failed, subagents: 0, startedAt: .now)
    let eligibility = DisplaySessionEligibility.resolve(
      storedSession: nil, isHidden: false, eventShell: shell)

    #expect(eligibility.policy == .eventShell)
    #expect(eligibility.usedEventShell)
    #expect(eligibility.session == shell)
    #expect(eligibility.allowsDisplay)
  }

  @Test func aTaskCompletionCarriesTheWholeTransientDecision() {
    var policy = DisplayPolicy(transientMilliseconds: 7_000)
    let decision = policy.decide(.taskComplete(sessionId: "session-1"))

    #expect(decision.accepted)
    #expect(decision.nextState == .transient)
    #expect(decision.focus == .set("session-1"))
    #expect(decision.activeSessionId == "session-1")
    #expect(decision.expansion == .expand)
    #expect(decision.timerPolicy == .transient(milliseconds: 7_000))
    #expect(decision.hoverPolicy == .unchanged)
  }

  @Test func aWarningUsesTheCompactTransientPresentation() {
    var policy = DisplayPolicy()
    let decision = policy.decide(.statusWarning(sessionId: "session-1"))

    #expect(decision.nextState == .transient)
    #expect(decision.expansion == .none)
    #expect(decision.timerPolicy == .transient(milliseconds: 5_000))
  }

  @Test func hoverPeekCanBePromotedWithoutLosingFocus() {
    var policy = DisplayPolicy(activeSessionId: "session-1")
    let hover = policy.decide(.hoverExpand)
    let promoted = policy.decide(.promotePeek(sessionId: nil))

    #expect(hover.nextState == .peek)
    #expect(hover.expansion == .peek)
    #expect(promoted.nextState == .manualExpanded)
    #expect(promoted.activeSessionId == "session-1")
    #expect(promoted.timerPolicy == .cancel)
    #expect(promoted.hoverPolicy == .shortCooldown)
  }

  @Test func blockingRequestsRejectEveryIncidentalIntent() {
    var policy = DisplayPolicy()
    _ = policy.decide(.question(sessionId: "session-1"))

    for intent in [
      DisplayIntent.hoverExpand,
      .taskComplete(sessionId: "session-2"),
      .statusWarning(sessionId: "session-2"),
      .collapse(.manual),
    ] {
      let decision = policy.decide(intent)
      #expect(!decision.accepted)
      #expect(decision.nextState == .blocking(.question))
      #expect(decision.activeSessionId == "session-1")
    }

    let resolved = policy.decide(.collapse(.system))
    #expect(resolved.accepted)
    #expect(resolved.nextState == .closed)
  }

  @Test func aHiddenFocusedSessionCollapsesItsDisplay() {
    var policy = DisplayPolicy()
    _ = policy.decide(.manualExpand(sessionId: "session-1"))

    let decision = policy.decide(
      .snapshotChanged(
        FocusedSnapshot(
          focusedSessionId: "session-1", sessionExists: true,
          isHidden: true, status: .idle)))

    #expect(decision.accepted)
    #expect(decision.nextState == .closed)
    #expect(decision.focus == .set(nil))
    #expect(decision.expansion == .collapse)
  }

  @Test func informationalEventsNeverReplaceAVisibleManualPanel() {
    var policy = DisplayPolicy()
    _ = policy.decide(.manualExpand(sessionId: "session-1"))

    for intent in [
      DisplayIntent.attentionReminder(sessionId: "session-2"),
      .taskComplete(sessionId: "session-2"),
      .compactionComplete(sessionId: "session-2"),
      .statusWarning(sessionId: "session-2"),
      .deferredReveal(sessionId: "session-2"),
    ] {
      #expect(!policy.decide(intent).accepted)
      #expect(policy.state == .manualExpanded)
      #expect(policy.activeSessionId == "session-1")
    }
  }
}
