import Foundation

/// The notch's interaction rules, as a pure state machine.
///
/// Extracted from the view layer so the behaviour can be tested without a display or
/// synthetic mouse events — the two bugs this replaced (a panel that never closed on
/// hover-out, and a click anywhere inside it collapsing it) were both invisible to unit
/// tests while the rules lived inside SwiftUI modifiers.
public struct NotchInteraction: Sendable, Equatable {
    public enum Event: Sendable, Equatable {
        case hoverEntered
        case hoverExited
        /// A click on the cutout strip: toggles the full panel from any state.
        case tappedNotch
        /// A click on the panel body. Only meaningful while peeking — the peek has no
        /// controls of its own, so its whole surface opens the panel. Once expanded the
        /// body belongs to its controls and a stray click must do nothing.
        case tappedBody
        case escapePressed
        case permissionArrived
        case permissionsCleared
        /// Perch has something worth a glance but not an answer — a quota window crossing
        /// the line you set. Shows the peek and takes it away again on its own.
        case revealRequested
        /// A completed turn is worth the full session and transcript, not a one-line
        /// flash. It still dismisses itself because nobody explicitly opened it.
        case expandedRevealRequested
        /// One line of news: a turn ended, a session failed, a quota window crossed.
        /// Shows the flash and takes it back on its own.
        case flashRequested
        /// The grace period after hover-out elapsed.
        case collapseTimerFired
    }

    /// What the controller must do after a transition, beyond changing state.
    public enum Effect: Sendable, Equatable {
        case scheduleCollapse(milliseconds: Int)
        case cancelCollapse
    }

    public private(set) var state: NotchState = .idle
    public var autoDisplayMilliseconds: Int
    private var policy: DisplayPolicy

    public init(
        state: NotchState = .idle,
        autoDisplayMilliseconds: Int = NotchInteraction.revealGrace
    ) {
        self.state = state
        self.autoDisplayMilliseconds = autoDisplayMilliseconds
        self.policy = DisplayPolicy(
            state: Self.displayState(for: state),
            transientMilliseconds: autoDisplayMilliseconds)
    }

    /// Grace periods: crossing the edge of a panel should not make it flicker, and a
    /// bigger panel needs longer because there is more empty space to cross.
    public static let peekGrace = 220
    /// Mouse leaves the expanded panel → it collapses a second later. Long enough not to
    /// close on a hand crossing the edge, short enough to be gone by the time you have
    /// looked away.
    public static let expandedGrace = 1_000
    /// A peek nobody asked for has to last long enough to read and short enough to forgive.
    public static let revealGrace = 5_000
    /// Long enough to read six words, short enough that it is gone before it is in the
    /// way. It is also the ceiling on how wrong this can be: nothing waits on a flash.
    public static let flashGrace = 5_000

    public var activeSessionId: String? { policy.activeSessionId }

    /// True while the panel is up on its own initiative — a finished turn revealed, a
    /// warning flashed — and will take itself down again. A panel someone opened is not.
    public var isTransient: Bool { policy.state == .transient }

    @discardableResult
    public mutating func handle(_ event: Event) -> [Effect] {
        if event == .hoverExited {
            switch state {
            case .peek:
                return [.scheduleCollapse(milliseconds: Self.peekGrace)]
            case .expanded:
                return [.scheduleCollapse(milliseconds: Self.expandedGrace)]
            case .idle, .flash, .alert:
                return []
            }
        }

        guard let intent = displayIntent(for: event) else { return [] }
        return handle(intent)
    }

    /// The full Vibe display contract entry point. The event adapter above remains for
    /// cursor and keyboard callers; session-aware model events use this so focus is not
    /// discarded on the way to the controller.
    @discardableResult
    public mutating func handle(_ intent: DisplayIntent) -> [Effect] {
        policy.transientMilliseconds = autoDisplayMilliseconds
        let decision = policy.decide(intent)
        guard decision.accepted else { return [] }

        state = renderedState(for: decision, current: state)
        switch decision.timerPolicy {
        case .transient(let milliseconds):
            return [.scheduleCollapse(milliseconds: milliseconds)]
        case .cancel:
            return [.cancelCollapse]
        case .unchanged:
            return []
        }
    }

    private func displayIntent(for event: Event) -> DisplayIntent? {
        switch event {
        case .hoverEntered:
            switch state {
            case .idle: return .hoverExpand
            case .flash: return .manualExpand(sessionId: nil)
            case .peek: return .promotePeek(sessionId: nil)
            case .expanded: return .pin(sessionId: nil)
            case .alert: return nil
            }
        case .hoverExited:
            return nil
        case .tappedNotch:
            return state == .expanded
                ? .collapse(.manual) : .manualExpand(sessionId: nil)
        case .tappedBody:
            return state == .peek ? .promotePeek(sessionId: nil) : nil
        case .escapePressed:
            return state == .idle ? nil : .collapse(.manual)
        case .permissionArrived:
            return .permission(sessionId: nil)
        case .permissionsCleared:
            return state == .alert ? .collapse(.system) : nil
        case .revealRequested:
            return .deferredReveal(sessionId: nil)
        case .expandedRevealRequested:
            return .taskComplete(sessionId: nil)
        case .flashRequested:
            return .statusWarning(sessionId: nil)
        case .collapseTimerFired:
            return state == .peek || state == .expanded || state == .flash
                ? .collapse(.autoTransient) : nil
        }
    }

    private static func displayState(for state: NotchState) -> NotchDisplayState {
        switch state {
        case .idle: return .closed
        case .flash: return .transient
        case .peek: return .peek
        case .expanded: return .manualExpanded
        case .alert: return .blocking(.permission)
        }
    }

    private func renderedState(
        for decision: DisplayDecision, current: NotchState
    ) -> NotchState {
        switch decision.nextState {
        case .closed:
            return .idle
        case .peek:
            return .peek
        case .manualExpanded:
            return .expanded
        case .blocking:
            return .alert
        case .transient:
            switch decision.expansion {
            case .collapse: return .idle
            case .expand: return .expanded
            case .peek: return .peek
            case .none:
                return current == .idle ? .flash : current
            }
        }
    }
}
