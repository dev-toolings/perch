import Foundation
import Testing

@testable import PerchKit

private let question = RequestKind.question(
    AskUserQuestionRequest(questions: [AskQuestion(question: "Which?", header: "Pick", multiSelect: false, options: [])]))
private let plan = RequestKind.plan(PlanApprovalRequest(plan: "Do the thing"))

/// This is the shape the bug actually takes: the terminal UI answers `AskUserQuestion`
/// outside Perch, the turn continues, and the very next `PostToolUse` in the same session
/// is the only evidence that reaches the app.
@Test func aQuestionIsKilledByALaterPostToolUseOfTheSameSession() {
    #expect(
        Abandonment.isAbandoned(
            kind: question, queuedAt: .distantPast, sessionId: "s1", agentId: nil,
            duplicateKey: "pending", event: "PostToolUse", eventSessionId: "s1",
            eventAgentId: nil, eventDuplicateKey: "later", eventAt: .now))
}

/// Claude Code fires `Notification` while it is still blocked on the permission prompt, not
/// after — treating it as proof would kill a card that is still waiting on a real answer.
@Test func aQuestionIsNotKilledByANotification() {
    #expect(
        !Abandonment.isAbandoned(
            kind: question, queuedAt: .distantPast, sessionId: "s1", agentId: nil,
            duplicateKey: "pending", event: "Notification", eventSessionId: "s1",
            eventAgentId: nil, eventDuplicateKey: "later", eventAt: .now))
}

/// A `PostToolUse` from an unrelated session proves nothing about this one — two Claude Code
/// windows running side by side must not bleed into each other's queues.
@Test func aQuestionIsNotKilledByAnEventFromADifferentSession() {
    #expect(
        !Abandonment.isAbandoned(
            kind: question, queuedAt: .distantPast, sessionId: "s1", agentId: nil,
            duplicateKey: "pending", event: "PostToolUse", eventSessionId: "s2",
            eventAgentId: nil, eventDuplicateKey: "later", eventAt: .now))
}

/// A plain permission has no parallel terminal UI racing the hook — there is nothing for
/// this policy to notice, so it must never drop one, no matter what arrives afterwards.
@Test func aPlainPermissionIsNeverKilled() {
    #expect(
        !Abandonment.isAbandoned(
            kind: .permission, queuedAt: .distantPast, sessionId: "s1", agentId: nil,
            duplicateKey: "pending", event: "PostToolUse", eventSessionId: "s1",
            eventAgentId: nil, eventDuplicateKey: "later", eventAt: .now))
}

/// A subagent's own events arrive under the parent session's id, so agent id is what tells
/// them apart: the main loop moving on must not kill a subagent's pending request.
@Test func aSubagentsPendingIsNotKilledByAMainLoopEvent() {
    #expect(
        !Abandonment.isAbandoned(
            kind: question, queuedAt: .distantPast, sessionId: "s1", agentId: "agent-1",
            duplicateKey: "pending", event: "PostToolUse", eventSessionId: "s1",
            eventAgentId: nil, eventDuplicateKey: "later", eventAt: .now))
}

/// And the other direction: a subagent moving on must not kill the main loop's own pending
/// request just because they share a session id.
@Test func aMainLoopsPendingIsNotKilledBySubagentEvent() {
    #expect(
        !Abandonment.isAbandoned(
            kind: question, queuedAt: .distantPast, sessionId: "s1", agentId: nil,
            duplicateKey: "pending", event: "PostToolUse", eventSessionId: "s1",
            eventAgentId: "agent-1", eventDuplicateKey: "later", eventAt: .now))
}

/// The event that queues the request itself must never be read as proof it is already
/// dead — only something that arrives strictly after counts.
@Test func anEventOlderThanThePendingDoesNotKillIt() {
    let queuedAt = Date()
    let earlier = queuedAt.addingTimeInterval(-1)
    #expect(
        !Abandonment.isAbandoned(
            kind: question, queuedAt: queuedAt, sessionId: "s1", agentId: nil,
            duplicateKey: "pending", event: "PostToolUse", eventSessionId: "s1",
            eventAgentId: nil, eventDuplicateKey: "later", eventAt: earlier))
}

/// A plan is answered from the same rogue terminal UI as a question, and is abandoned the
/// same way.
@Test func aPlanIsKilledTheSameWayAQuestionIs() {
    #expect(
        Abandonment.isAbandoned(
            kind: plan, queuedAt: .distantPast, sessionId: "s1", agentId: nil,
            duplicateKey: "pending", event: "Stop", eventSessionId: "s1", eventAgentId: nil,
            eventDuplicateKey: "later", eventAt: .now))
}

/// Hooks installed in two scopes both fire `PermissionRequest` for one tool call, and the
/// second copy arrives while the first is already queued and waiting. Every other condition
/// here holds for it, which makes this the one case that would turn the fix into the bug it
/// repairs: a twin killing the card it came to join, and handing its own session back to the
/// terminal prompt.
@Test func aRequestsOwnCopyIsNotProofItWasAbandoned() {
    #expect(
        !Abandonment.isAbandoned(
            kind: question, queuedAt: .distantPast, sessionId: "s1", agentId: nil,
            duplicateKey: "PermissionRequest:abc", event: "PermissionRequest",
            eventSessionId: "s1", eventAgentId: nil,
            eventDuplicateKey: "PermissionRequest:abc", eventAt: .now))
}

/// A *different* request in the same session is still proof, though — the loop cannot have
/// reached a second tool while blocked on the question, so this is not the copy case.
@Test func aDifferentRequestInTheSameSessionStillKillsIt() {
    #expect(
        Abandonment.isAbandoned(
            kind: question, queuedAt: .distantPast, sessionId: "s1", agentId: nil,
            duplicateKey: "PermissionRequest:abc", event: "PermissionRequest",
            eventSessionId: "s1", eventAgentId: nil,
            eventDuplicateKey: "PermissionRequest:def", eventAt: .now))
}
