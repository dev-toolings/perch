import Foundation

/// Whether a pending request has already been settled somewhere Perch cannot see.
///
/// Claude Code runs its own terminal UI in parallel with the hook for the two tools that
/// require direct interaction — `AskUserQuestion` and `ExitPlanMode` — and when someone
/// answers there instead of on the card, the turn moves on without ever telling the hook it
/// can stop waiting. The hook stays blocked on the socket, the request stays queued, and
/// because the panel only ever draws the head of the queue, that one dead request hides
/// every card that arrives after it. There is nothing to poll and no hangup to detect — the
/// only proof available is that the same session kept talking after the request was queued.
/// This is that proof, expressed as a pure function so every condition it rests on is
/// testable on its own rather than trusted by inspection — because the cost of getting one
/// wrong is a live card resolved out from under someone.
public enum Abandonment {
    /// Events that can only fire once the loop has moved past whatever it was waiting on.
    ///
    /// `Notification` is excluded on evidence rather than on doubt: Claude Code fires it
    /// *while* still blocked on the permission prompt, so reading it as proof of progress
    /// would kill a request that is still perfectly live. Everything else Perch sees —
    /// `SubagentStart`, `SubagentStop`, `SessionStart`, `SessionEnd`, `PreCompact`,
    /// `PermissionDenied` — is excluded on the weaker ground that nothing has been observed
    /// pinning it strictly after a pending request clears. That is a smaller claim, and it
    /// is the safe direction to be wrong in: an event missing from this list costs a ghost
    /// that lives until the next real one, while an event wrongly in it costs a card
    /// somebody was reading.
    public static let provingEvents: Set<String> = [
        "PreToolUse", "PostToolUse", "PostToolUseFailure", "Stop", "StopFailure",
        "UserPromptSubmit", "PermissionRequest",
    ]

    /// - Parameters:
    ///   - kind: Only `.question` and `.plan` have a terminal UI racing the hook. A plain
    ///     `.permission` is never abandoned by this — nothing else is watching it.
    ///   - queuedAt: When the pending request joined the queue.
    ///   - sessionId: The pending request's own session. `nil` matches nothing, on either
    ///     side: a request with no session id to compare against cannot be proven dead.
    ///   - agentId: `nil` for the main loop, set for a subagent. A subagent's pending is
    ///     only killed by that same subagent's own events, and the main loop's only by the
    ///     main loop's — so this is plain equality, nil included.
    ///   - duplicateKey: What identifies the pending request's own event. A request is never
    ///     proof against itself: hooks installed in two scopes both fire `PermissionRequest`
    ///     for one tool call, and the second copy lands while the first is already queued —
    ///     every other condition here holds for it, so without this the twin would kill the
    ///     card it came to join and hand its own session back to the terminal prompt.
    ///   - event: The incoming hook event's name.
    ///   - eventSessionId: The incoming event's session id.
    ///   - eventAgentId: The incoming event's agent id.
    ///   - eventDuplicateKey: What identifies the incoming event, compared against
    ///     `duplicateKey`. Two nils are treated as the same event, which costs nothing: a
    ///     key is only nil when there is no session id either, and that is already refused
    ///     above.
    ///   - eventAt: When the incoming event arrived. A `PreToolUse` for a tool fires before
    ///     that same tool's own `PermissionRequest`, so requiring this strictly after
    ///     `queuedAt` is what keeps a request from ever being killed by the event that
    ///     queued it in the first place.
    public static func isAbandoned(
        kind: RequestKind, queuedAt: Date, sessionId: String?, agentId: String?,
        duplicateKey: String?, event: String, eventSessionId: String?, eventAgentId: String?,
        eventDuplicateKey: String?, eventAt: Date
    ) -> Bool {
        switch kind {
        case .permission: return false
        case .question, .plan: break
        }
        guard let sessionId, let eventSessionId, sessionId == eventSessionId else { return false }
        guard agentId == eventAgentId else { return false }
        guard duplicateKey != eventDuplicateKey else { return false }
        guard provingEvents.contains(event) else { return false }
        return queuedAt < eventAt
    }
}
