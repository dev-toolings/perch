import AppKit
import Observation
import PerchKit
import SwiftUI

/// Owns the panel and applies the interaction rules from `NotchInteraction`.
///
/// The controller deliberately holds no rules of its own: it forwards events to the
/// machine and executes the effects it returns, so behaviour stays testable.
@MainActor
@Observable
final class NotchController {
  private(set) var state: NotchState = .idle
  private(set) var geometry: NotchGeometry
  /// Bumped on every hook event so the idle view can pulse without resizing the panel.
  private(set) var activityPulse: Int = 0
  var activeSessionId: String? { interaction.activeSessionId }
  /// Whether the panel opened by itself to show a finished turn, or was opened by hand.
  /// Read at the moment the panel is built, which is why `state` — published — is
  /// enough to invalidate it.
  var isTransientReveal: Bool { interaction.isTransient }

  @ObservationIgnored private var interaction = NotchInteraction()
  @ObservationIgnored private let window = NotchWindow()
  @ObservationIgnored private var screen: NSScreen
  @ObservationIgnored private var collapseTask: Task<Void, Never>?
  /// Hover and clicks, watched from outside the view tree. See `startWatchingTheCursor`.
  @ObservationIgnored private var mouseMonitors: [Any] = []
  @ObservationIgnored private var cursorTimer: Timer?
  @ObservationIgnored private var isHovering = false
  @ObservationIgnored private var expandsOnHover = true
  @ObservationIgnored private var collapsesOnHoverExit = true
  @ObservationIgnored private var panelMaximumWidth: CGFloat = 640
  @ObservationIgnored private var panelMaximumHeight: CGFloat = 560
  private var expandedContentHeight: CGFloat = NotchState.expandedInitialHeight
  @ObservationIgnored private var completionCardHeight: CGFloat = 90
  @ObservationIgnored private var hidesInFullscreen = true
  @ObservationIgnored private var closesAutoDisplayOnOutsideClick = false

  /// Supplied by the scene monitor so the panel stays independent of window discovery.
  @ObservationIgnored var frontmostAppIsFullscreen: () -> Bool = { false }

  /// Points added to what macOS reports for the cutout, from Settings.
  @ObservationIgnored private var tuning: (width: Double, height: Double) = (0, 0)

  init() {
    // `.main` follows the focused window; at launch we want the screen that owns the
    // menu bar, which is always screens[0].
    screen = NSScreen.screens.first ?? NSScreen.main!
    geometry = NotchGeometry.detect(on: screen)
  }

  /// Re-measures and redraws immediately, so dragging a slider in Settings shows its
  /// effect on the notch rather than at the next relaunch.
  func applyTuning(width: Double, height: Double) {
    tuning = (width, height)
    geometry = NotchGeometry.detect(on: screen).adjusted(width: width, height: height)
    pinCanvas()
  }

  func applyInteractionPreferences(_ preferences: Preferences) {
    screen =
      preferences.targetDisplayName.flatMap { target in
        NSScreen.screens.first { $0.localizedName == target }
      } ?? NSScreen.screens.first ?? screen
    geometry = NotchGeometry.detect(on: screen)
      .adjusted(width: tuning.width, height: tuning.height)
    pinCanvas()
    expandsOnHover = preferences.expandsOnHover
    collapsesOnHoverExit = preferences.collapsesOnHoverExit
    panelMaximumWidth = preferences.panelMaximumWidth
    panelMaximumHeight = preferences.panelMaximumHeight
    completionCardHeight = preferences.completionCardHeight
    hidesInFullscreen = preferences.hidesInFullscreen
    closesAutoDisplayOnOutsideClick = preferences.closesAutoDisplayOnOutsideClick
    interaction.autoDisplayMilliseconds = Int(preferences.autoDisplayDuration * 1_000)
  }

  func start(content: some View) {
    window.contentView = NSHostingView(rootView: AnyView(content))
    pinCanvas()
    window.orderFrontRegardless()
    startWatchingTheCursor()

    NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.screenParametersChanged() }
    }
  }

  /// The window's frame, set once and then left alone. Everything that moves, moves
  /// inside it.
  private func pinCanvas() {
    let requested = NotchState.canvas(notch: geometry.size)
    let canvas = CGSize(
      width: min(requested.width, max(geometry.size.width, screen.frame.width - 16)),
      height: min(requested.height, max(geometry.size.height, screen.frame.height - 8)))
    window.setFrame(geometry.panelFrame(for: canvas, on: screen), display: true)
  }

  /// Hover is measured against the panel's rect, not reported by the view tree.
  ///
  /// `onHover` cannot work here any more. While idle the window ignores the mouse — it
  /// has to, or a 680×660 canvas would answer for every click in the top half of the
  /// screen — so no tracking area is ever entered. By the time the canvas does take
  /// events the cursor is already inside it, and AppKit does not synthesise the
  /// `mouseEntered` that was missed. SwiftUI therefore believes the panel was never
  /// hovered, and never reports leaving it either: the panel opened and stayed open.
  ///
  /// So the cursor is watched directly, from two angles.
  ///
  /// The monitors are what make it feel instant, and both are installed because either
  /// can be the one that sees a given move — the global one while the events belong to
  /// another app, the local one once they belong to us.
  ///
  /// The timer is what makes it correct. A cursor can arrive somewhere without a single
  /// event being emitted: `CGWarpMouseCursorPosition` does exactly that, and so does
  /// coming back from a Space switch or from under a window that was just closed. The
  /// old panel got away with it because it resized on every transition, and resizing a
  /// window forces AppKit to re-evaluate its tracking areas; a window that never resizes
  /// has no such accident to rely on. A quarter second is far below noticing, and the
  /// monitors mean it is almost never the one that reports the crossing.
  ///
  /// Mouse events need no permission to observe; only keyboard ones do. Perch still
  /// never asks for Accessibility.
  private func startWatchingTheCursor() {
    mouseMonitors = [
      NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) {
        [weak self] event in
        MainActor.assumeIsolated { self?.sampleCursor(clicked: event.type == .leftMouseDown) }
      },
      NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) {
        [weak self] event in
        MainActor.assumeIsolated {
          self?.sampleCursor(clicked: event.type == .leftMouseDown)
        }
        return event
      },
    ].compactMap { $0 }

    cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.sampleCursor(clicked: false) }
    }
  }

  private func sampleCursor(clicked: Bool) {
    // Hysteresis: it takes 6pt more to leave than it took to enter.
    //
    // Without it the boundary is a single line, and a hand resting on it crosses that
    // line several times a second — each crossing starting a 220ms collapse and then
    // cancelling it. The panel never settled, and the flicker was blamed on the
    // animation rather than on the hit test underneath it.
    let rect = isHovering ? panelRect.insetBy(dx: -6, dy: -6) : panelRect
    let inside = rect.contains(NSEvent.mouseLocation)

    if hidesInFullscreen, frontmostAppIsFullscreen() {
      window.alphaValue = 0
      window.isInteractive = false
      return
    }
    window.alphaValue = 1
    window.isInteractive = state.drawsPanel

    if clicked, !inside, closesAutoDisplayOnOutsideClick,
      state == .peek || state == .flash
    {
      send(.escapePressed)
      return
    }

    // A click on the resting strip opens the panel. Only from idle: once the canvas
    // takes events, the strip is a real tap target and SwiftUI owns it — handling the
    // click here too would toggle it twice.
    if clicked {
      guard inside, state == .idle else { return }
      // The whole strip opens the panel, and nothing else.
      //
      // It carried a mute and a gear for a while, drawn but not clickable — the
      // canvas ignores the mouse while idle, which is what lets the menu bar
      // underneath keep working — so their clicks were routed here against
      // rectangles computed a second time, in a second file. Two pieces of
      // arithmetic that had to agree about where a thing was drawn, for two
      // controls that are one click away inside the panel and in the right-click
      // menu. The strip is what is running; it is not a toolbar.
      send(.tappedNotch)
      return
    }

    if inside != isHovering {
      isHovering = inside
      if inside {
        // From rest, honour the hover-to-expand preference. Once a panel is already
        // open, re-entering it always cancels a pending collapse — that is not the
        // same choice as whether hovering opens it in the first place.
        if state == .idle {
          if expandsOnHover { send(.hoverEntered) }
        } else {
          send(.hoverEntered)
        }
      } else if collapsesOnHoverExit {
        send(.hoverExited)
      }
      return
    }

    // A panel opened by a click the cursor never entered — it dropped down below the
    // pointer, or the pointer left before the next sample — has no leave edge to fire,
    // so it used to sit open until something else closed it. If it is expanded, the
    // cursor is outside, auto-collapse is on and nothing is already counting down, arm
    // the same one-second leave timer now.
    if state == .expanded, !inside, collapsesOnHoverExit, collapseTask == nil {
      send(.hoverExited)
    }
  }

  /// Where the panel actually is on screen: centred in the canvas, hanging from its top
  /// edge — which is what the view does with it.
  private var panelRect: CGRect {
    let canvas = window.frame
    let size = panelSize
    return CGRect(
      x: canvas.midX - size.width / 2,
      y: canvas.maxY - size.height,
      width: size.width,
      height: size.height)
  }

  // MARK: - Events

  func toggleExpanded() {
    send(.tappedNotch)
  }

  /// A click on the panel body — opens the panel from a peek, ignored once expanded.
  func tapBody() {
    send(.tappedBody)
  }

  func dismiss() {
    send(.escapePressed)
  }

  /// Opens the panel outright, whatever it was doing. The switcher's shortcut has to
  /// work from idle and from a peek alike, and `toggleExpanded` would close it on the
  /// second press — which is exactly what cycling does.
  func expand() {
    guard state != .expanded else { return }
    send(.tappedNotch)
    if state != .expanded { send(.tappedNotch) }
  }

  /// Extra height the current request needs. A question with four options, or a plan,
  /// does not fit the height a `Bash(...)` prompt does — and a card that has to scroll
  /// to reach its own buttons is unanswerable.
  private(set) var alertExtraHeight: CGFloat = 0
  /// And how much wider. A plan is prose: at 520pt every sentence wraps three times, and
  /// a wrapped plan reads as a wall rather than as a list of steps.
  private(set) var alertExtraWidth: CGFloat = 0

  /// Called when a permission arrives or the queue empties.
  func showAlert(
    _ isWaiting: Bool, extraHeight: CGFloat = 0, extraWidth: CGFloat = 0,
    sessionId: String? = nil, kind: DisplayBlockingKind = .permission
  ) {
    // One request replacing another leaves the state alone but changes the height;
    // publishing it is enough, because the panel's size is now something SwiftUI
    // animates rather than something AppKit is told about.
    alertExtraHeight = isWaiting ? extraHeight : 0
    alertExtraWidth = isWaiting ? extraWidth : 0
    if isWaiting {
      send(kind == .question ? .question(sessionId: sessionId) : .permission(sessionId: sessionId))
    } else {
      send(.collapse(.system))
    }
  }

  /// Shows the peek for something worth a glance, and takes it back without being asked.
  /// Ignored unless the notch is at rest — see `NotchInteraction`.
  func reveal(sessionId: String? = nil) {
    send(.deferredReveal(sessionId: sessionId))
  }

  /// Shows the complete session card for a finished turn, then restores the resting
  /// notch after the configured auto-display duration.
  func revealExpanded(sessionId: String? = nil) {
    send(.taskComplete(sessionId: sessionId))
  }

  /// What the flash is currently saying. Held rather than passed, because the state
  /// machine owns *whether* it shows and this owns *what* — and the notice has to
  /// survive the transition out, or the last frame of the animation is an empty strip.
  private(set) var notice: NotchFlash?

  /// A line of news at the cutout, taken back on its own. Ignored unless the notch is
  /// at rest: a panel someone opened outranks anything Perch has to say.
  func flash(_ notice: NotchFlash, sessionId: String? = nil) {
    guard state == .idle else { return }
    self.notice = notice
    send(.statusWarning(sessionId: sessionId))
  }

  func flashActivity() {
    activityPulse &+= 1
  }

  /// Reconciles the focused display with the authoritative session store. Vibe carries
  /// this as `FocusedSnapshot`: a card that was archived, filtered or removed cannot
  /// leave a transient panel focused on content that no longer exists.
  func reconcileFocusedSession(
    sessions: [String: SessionSnapshot], visibleSessions: [SessionSnapshot]
  ) {
    guard let activeSessionId else { return }
    let session = sessions[activeSessionId]
    send(
      .snapshotChanged(
        FocusedSnapshot(
          focusedSessionId: activeSessionId,
          sessionExists: session != nil,
          isHidden: !visibleSessions.contains(where: { $0.id == activeSessionId }),
          status: session?.status)))
  }

  private func send(_ event: NotchInteraction.Event) {
    let effects = interaction.handle(event)
    apply(effects)
  }

  private func send(_ intent: DisplayIntent) {
    let effects = interaction.handle(intent)
    apply(effects)
  }

  private func apply(_ effects: [NotchInteraction.Effect]) {
    for effect in effects {
      switch effect {
      case .cancelCollapse:
        collapseTask?.cancel()
        collapseTask = nil
      case .scheduleCollapse(let milliseconds):
        scheduleCollapse(after: .milliseconds(milliseconds))
      }
    }
    apply(interaction.state)
  }

  private func scheduleCollapse(after delay: Duration) {
    collapseTask?.cancel()
    collapseTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      self?.send(.collapseTimerFired)
    }
  }

  // MARK: - Presentation

  /// Called when the panel starts or stops being drawn, so work that only matters while
  /// someone is looking — re-reading transcripts — runs then and not the rest of the day.
  var onPanelVisibilityChanged: ((Bool) -> Void)?

  private func apply(_ next: NotchState) {
    guard next != state else { return }
    let wasDrawing = state.drawsPanel
    state = next
    if next.drawsPanel != wasDrawing { onPanelVisibilityChanged?(next.drawsPanel) }
    window.wantsKeyboard = next.wantsKeyboard
    // The canvas answers for the mouse only while it has something under the cursor to
    // answer for. At rest the strip is watched from the outside instead.
    window.isInteractive = next.drawsPanel

    if next.wantsKeyboard { window.makeKey() }
  }

  /// How far the resting state reaches past the cutout, set from what is running.
  private(set) var idleFlank: CGFloat = 0

  /// Records how far the resting content reaches past the cutout — an agent starting or
  /// stopping should widen or narrow the strip. Publishing it is the whole job now:
  /// `panelSize` changes, and the same spring that runs every other transition carries
  /// it.
  func setIdleFlank(_ flank: CGFloat) {
    guard flank != idleFlank else { return }
    idleFlank = flank
  }

  func setExpandedContentHeight(_ height: CGFloat) {
    let clamped = NotchState.expandedHeight(
      contentHeight: height, maximumHeight: panelMaximumHeight)
    guard clamped != expandedContentHeight else { return }
    expandedContentHeight = clamped
  }

  /// Remembers the session the person actually opened. Collapsing the island keeps this
  /// focus, so the next hover returns to the same card instead of jumping to the first
  /// working harness.
  func focus(sessionId: String) {
    send(.pin(sessionId: sessionId))
  }

  /// What the panel measures right now. The only thing the view animates.
  var panelSize: CGSize {
    var size = state.size(notch: geometry.size, flank: idleFlank)
    if state == .expanded {
      size.width = min(size.width, panelMaximumWidth + 16)
      size.height = min(expandedContentHeight, panelMaximumHeight)
    }
    if state == .flash { size.height = completionCardHeight }
    if state == .alert {
      size.height += alertExtraHeight
      size.width += alertExtraWidth
    }
    // Requests can ask for extra prose room, and preferences can be carried from a
    // larger display. Neither is permission to paint off-screen. Keep one small gutter
    // so the inverse shoulders remain visible even on a compact external display.
    size.width = min(size.width, max(geometry.size.width, screen.frame.width - 16))
    size.height = min(size.height, max(geometry.size.height, screen.frame.height - 8))
    return size
  }

  private func screenParametersChanged() {
    if !NSScreen.screens.contains(screen) { screen = NSScreen.screens.first ?? screen }
    geometry = NotchGeometry.detect(on: screen)
      .adjusted(width: tuning.width, height: tuning.height)
    // A display change is a cut, not a transition: re-pin and redraw where we are.
    pinCanvas()
  }
}
