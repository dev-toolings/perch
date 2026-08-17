import Foundation

/// Display contract recovered from Vibe Island 1.0.44's Swift metadata. The render state
/// alone is not a decision: focus, expansion, timer and hover cooldown travel together so
/// one event cannot update half the notch and leave the rest behind.
public enum NotchDisplayState: Sendable, Equatable {
  case peek
  case blocking(DisplayBlockingKind)
  case transient
  case closed
  case manualExpanded
}

public enum DisplayBlockingKind: Sendable, Equatable {
  case permission
  case question
}

public enum DisplayCollapseReason: Sendable, Equatable {
  case manual
  case autoTransient
  case system
}

public enum DisplayIntent: Sendable, Equatable {
  case collapse(DisplayCollapseReason)
  case attentionReminder(sessionId: String?)
  case taskComplete(sessionId: String?)
  case compactionComplete(sessionId: String?)
  case statusWarning(sessionId: String?)
  case permission(sessionId: String?)
  case question(sessionId: String?)
  case deferredReveal(sessionId: String?)
  case tabMismatch(sessionId: String?)
  case peek(sessionId: String?)
  case snapshotChanged(FocusedSnapshot)
  case manualExpand(sessionId: String?)
  case hoverExpand
  case promotePeek(sessionId: String?)
  case pin(sessionId: String?)
}

public enum DisplayFocusMutation: Sendable, Equatable {
  case set(String?)
  case unchanged
}

public enum DisplayExpansion: Sendable, Equatable {
  case collapse
  case none
  case expand
  case peek
}

public enum DisplayTimerPolicy: Sendable, Equatable {
  case transient(milliseconds: Int)
  case unchanged
  case cancel
}

public enum DisplayHoverPolicy: Sendable, Equatable {
  case unchanged
  case shortCooldown
}

public struct FocusedSnapshot: Sendable, Equatable {
  public let focusedSessionId: String?
  public let sessionExists: Bool
  public let isHidden: Bool
  public let status: SessionStatus?

  public init(
    focusedSessionId: String?, sessionExists: Bool, isHidden: Bool,
    status: SessionStatus?
  ) {
    self.focusedSessionId = focusedSessionId
    self.sessionExists = sessionExists
    self.isHidden = isHidden
    self.status = status
  }
}

public enum DisplaySessionPolicy: Sendable, Equatable {
  case visible
  case hidden
  case missing
  case eventShell
}

public struct DisplaySessionEligibility: Sendable, Equatable {
  public let session: SessionSnapshot?
  public let policy: DisplaySessionPolicy
  public let usedEventShell: Bool

  public init(
    session: SessionSnapshot?, policy: DisplaySessionPolicy, usedEventShell: Bool
  ) {
    self.session = session
    self.policy = policy
    self.usedEventShell = usedEventShell
  }

  public var allowsDisplay: Bool {
    policy == .visible || policy == .eventShell
  }

  public static func resolve(
    storedSession: SessionSnapshot?, isHidden: Bool, eventShell: SessionSnapshot?
  ) -> DisplaySessionEligibility {
    if isHidden {
      return DisplaySessionEligibility(
        session: storedSession, policy: .hidden, usedEventShell: false)
    }
    if let storedSession {
      return DisplaySessionEligibility(
        session: storedSession, policy: .visible, usedEventShell: false)
    }
    if let eventShell {
      return DisplaySessionEligibility(
        session: eventShell, policy: .eventShell, usedEventShell: true)
    }
    return DisplaySessionEligibility(session: nil, policy: .missing, usedEventShell: false)
  }
}

public struct DisplayDecision: Sendable, Equatable {
  public let accepted: Bool
  public let reason: String
  public let nextState: NotchDisplayState
  public let focus: DisplayFocusMutation
  public let activeSessionId: String?
  public let expansion: DisplayExpansion
  public let timerPolicy: DisplayTimerPolicy
  public let hoverPolicy: DisplayHoverPolicy
}

public struct DisplayPolicy: Sendable, Equatable {
  public private(set) var state: NotchDisplayState
  public private(set) var activeSessionId: String?
  public var transientMilliseconds: Int

  public init(
    state: NotchDisplayState = .closed, activeSessionId: String? = nil,
    transientMilliseconds: Int = 5_000
  ) {
    self.state = state
    self.activeSessionId = activeSessionId
    self.transientMilliseconds = transientMilliseconds
  }

  public mutating func decide(_ intent: DisplayIntent) -> DisplayDecision {
    if case .blocking = state {
      switch intent {
      case .permission(let sessionId):
        return accept(
          .blocking(.permission), sessionId: sessionId, expansion: .expand,
          timer: .cancel, reason: "blocking permission refreshed")
      case .question(let sessionId):
        return accept(
          .blocking(.question), sessionId: sessionId, expansion: .expand,
          timer: .cancel, reason: "blocking question refreshed")
      case .collapse(.system):
        return accept(
          .closed, sessionId: nil, expansion: .collapse, timer: .cancel,
          reason: "blocking request resolved")
      default:
        return reject("blocking request owns the display")
      }
    }

    switch intent {
    case .permission(let sessionId):
      return accept(
        .blocking(.permission), sessionId: sessionId, expansion: .expand,
        timer: .cancel, reason: "permission requires a response")

    case .question(let sessionId):
      return accept(
        .blocking(.question), sessionId: sessionId, expansion: .expand,
        timer: .cancel, reason: "question requires a response")

    case .collapse:
      guard state != .closed else { return reject("display already closed") }
      return accept(
        .closed, sessionId: nil, expansion: .collapse, timer: .cancel,
        reason: "collapse accepted")

    case .manualExpand(let sessionId):
      return accept(
        .manualExpanded, sessionId: sessionId ?? activeSessionId,
        expansion: .expand, timer: .cancel, hover: .shortCooldown,
        reason: "manual expansion")

    case .promotePeek(let sessionId):
      guard state == .peek || state == .transient else {
        return reject("nothing to promote")
      }
      return accept(
        .manualExpanded, sessionId: sessionId ?? activeSessionId,
        expansion: .expand, timer: .cancel, hover: .shortCooldown,
        reason: "peek promoted")

    case .hoverExpand:
      guard state == .closed else { return reject("display already visible") }
      return accept(
        .peek, sessionId: activeSessionId, expansion: .peek, timer: .cancel,
        reason: "hover expansion")

    case .peek(let sessionId), .tabMismatch(let sessionId):
      guard state == .closed || state == .transient else {
        return reject("visible display outranks peek")
      }
      return accept(
        .peek, sessionId: sessionId ?? activeSessionId, expansion: .peek,
        timer: .cancel, reason: "peek requested")

    case .deferredReveal(let sessionId):
      guard state == .closed else { return reject("visible display outranks reveal") }
      return acceptTransient(
        sessionId: sessionId, expansion: .peek, reason: "deferred reveal")

    case .attentionReminder(let sessionId), .taskComplete(let sessionId),
      .compactionComplete(let sessionId):
      guard state == .closed else { return reject("visible display outranks completion") }
      return acceptTransient(
        sessionId: sessionId, expansion: .expand, reason: "transient session reveal")

    case .statusWarning(let sessionId):
      guard state == .closed else { return reject("visible display outranks warning") }
      return acceptTransient(
        sessionId: sessionId, expansion: .none, reason: "transient status warning")

    case .pin(let sessionId):
      guard state != .closed else { return reject("closed display cannot be pinned") }
      return accept(
        state, sessionId: sessionId ?? activeSessionId, expansion: .none,
        timer: .cancel, reason: "visible display pinned")

    case .snapshotChanged(let snapshot):
      guard let focused = snapshot.focusedSessionId else {
        return reject("snapshot carries no focus")
      }
      if !snapshot.sessionExists || snapshot.isHidden {
        guard activeSessionId == focused, state != .closed else {
          return reject("snapshot does not affect active display")
        }
        return accept(
          .closed, sessionId: nil, expansion: .collapse, timer: .cancel,
          reason: "focused session disappeared")
      }
      return accept(
        state, sessionId: focused, expansion: .none, timer: .unchanged,
        reason: "focused snapshot refreshed")
    }
  }

  private mutating func acceptTransient(
    sessionId: String?, expansion: DisplayExpansion, reason: String
  ) -> DisplayDecision {
    accept(
      .transient, sessionId: sessionId, expansion: expansion,
      timer: .transient(milliseconds: transientMilliseconds), reason: reason)
  }

  private mutating func accept(
    _ next: NotchDisplayState, sessionId: String?, expansion: DisplayExpansion,
    timer: DisplayTimerPolicy, hover: DisplayHoverPolicy = .unchanged,
    reason: String
  ) -> DisplayDecision {
    state = next
    activeSessionId = sessionId
    return DisplayDecision(
      accepted: true, reason: reason, nextState: next,
      focus: .set(sessionId), activeSessionId: sessionId, expansion: expansion,
      timerPolicy: timer, hoverPolicy: hover)
  }

  private func reject(_ reason: String) -> DisplayDecision {
    DisplayDecision(
      accepted: false, reason: reason, nextState: state, focus: .unchanged,
      activeSessionId: activeSessionId, expansion: .none,
      timerPolicy: .unchanged, hoverPolicy: .unchanged)
  }
}
