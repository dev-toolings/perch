import Foundation

/// One push per session per waiting episode.
///
/// A session that stays blocked does not get buzzed again just because a second hook
/// call reached the same still-pending request — that is the same wait, not a new one.
/// An episode ends the moment the session stops waiting (answered, denied, or gone), so
/// the next time it blocks is a fresh reason to buzz.
public struct PushDedupState: Sendable, Equatable {
  private var pushedSessions: Set<String> = []

  public init() {}

  public func hasPushed(for sessionId: String) -> Bool {
    pushedSessions.contains(sessionId)
  }

  public mutating func markPushed(for sessionId: String) {
    pushedSessions.insert(sessionId)
  }

  /// The session stopped waiting — the next block on it starts a new episode.
  public mutating func endEpisode(for sessionId: String) {
    pushedSessions.remove(sessionId)
  }
}

/// Whether an event should reach a phone. Pure, and deliberately ignorant of the network:
/// everything it needs — settings, what happened, whether anyone is at the machine, and
/// what already went out — is handed in, so the whole policy is testable without sending
/// a single request.
public enum PushDecision {
  /// "Away" is the same test `SceneMonitor` and `CGEventSource` already make possible —
  /// this just names the combination: the screen is not something to look at, or nobody
  /// has touched the machine in a while.
  public static func isAway(
    isScreenObscured: Bool,
    idleSeconds: TimeInterval,
    thresholdMinutes: Int
  ) -> Bool {
    isScreenObscured || idleSeconds >= TimeInterval(thresholdMinutes * 60)
  }

  /// Whether this event should fire a push right now.
  ///
  /// Nothing here is ever true while `isAway` is false — that is the one rule this
  /// function exists to enforce, and every other check is secondary to it.
  public static func shouldPush(
    settings: PushSettings,
    hasCredentials: Bool,
    kind: InterruptionKind,
    isAway: Bool,
    sessionId: String,
    dedup: PushDedupState
  ) -> Bool {
    guard settings.enabled else { return false }
    guard hasCredentials else { return false }
    guard settings.pushedKinds.contains(kind) else { return false }
    guard isAway else { return false }
    guard !dedup.hasPushed(for: sessionId) else { return false }
    return true
  }
}
