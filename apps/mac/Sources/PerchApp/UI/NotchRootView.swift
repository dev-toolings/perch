import PerchKit
import SwiftUI

struct NotchRootView: View {
  @Bindable var controller: NotchController
  let model: AppModel

  var body: some View {
    // The window is a fixed canvas; the panel is the only thing in it that moves, and
    // it moves on one spring. Everything below this line animates because `panelSize`
    // changed — not because anyone told a window to resize.
    VStack(spacing: 0) {
      // Hover is not read here: the controller watches the cursor against this same
      // rect, because a canvas that ignores the mouse while idle never delivers the
      // `mouseEntered` that `onHover` needs to work at all.
      panel
        .frame(width: controller.panelSize.width, height: controller.panelSize.height)

      // Deliberately empty: the room the panel grows into. Spacer takes no hits, so
      // the canvas stays as transparent to the mouse as it looks.
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(Motion.morph, value: controller.panelSize)
    .animation(Motion.morph, value: controller.state)
    .onChange(of: idleFlank, initial: true) { controller.setIdleFlank(idleFlank) }
    .background {
      Button("") { controller.dismiss() }
        .keyboardShortcut(.escape, modifiers: [])
        .opacity(0)
    }
    // The only way out of the app.
    //
    // Perch has no Dock icon and no menu bar item, so until this existed the gear
    // inside the expanded panel was the single entry point to anything — and there was
    // no exit at all: quitting meant Activity Monitor. An app that cannot be quit by
    // the person running it is not a preference, it is a defect.
    .contextMenu {
      Button(t("Settings…")) { model.showSettings() }
      Button(t("Check for Updates…")) { Task { await model.updates.check() } }
      Button(model.sounds.enabled ? t("Mute sounds") : t("Unmute sounds")) {
        model.updateSounds(model.sounds.toggledEnabled)
      }
      Divider()
      Button(t("Quit Perch")) { NSApplication.shared.terminate(nil) }
    }
  }

  private var panel: some View {
    ZStack(alignment: .top) {
      // One shape for every state, faded rather than swapped.
      //
      // This used to be an `if drawsPanel { … } else if idleFlank > 0 { … }`, which
      // reads fine and animates badly: the two branches are different views, and
      // SwiftUI cannot morph one view into another — it removes one and inserts the
      // other. So the corner radii jumped from 12 to 18 in a single frame while the
      // *frame* was still springing, and the hairline border appeared and vanished
      // instantly at both ends. The panel grew smoothly and its outline popped, which
      // is the part that read as cheap.
      //
      // With one persistent shape, `animatableData` interpolates the radii on the
      // same curve as the size, and both fills are opacity — which is a thing that
      // can be animated.
      shape
        .fill(Theme.surface)
        // Nothing is painted at rest with nothing running: the cutout is already
        // black, and drawing our own black over it is what made it look wrong.
        .opacity(controller.state.drawsPanel || idleFlank > 0 ? 1 : 0)
        .overlay {
          shape
            .stroke(Theme.hairline, lineWidth: 1)
            .opacity(controller.state.drawsPanel ? 1 : 0)
        }

      content
        // One state's content is not a redraw of another's, so it is replaced
        // rather than diffed — and it comes in from the top edge, where the panel
        // is coming from. On its own, shorter curve: the incoming content should
        // be legible while the panel is still growing, not arrive with it.
        .id(controller.state)
        .transition(Motion.contentSwap)
        .animation(Motion.content, value: controller.state)
        // A panel hangs below the bezel, under the collar; rest and the flash sit
        // level with the cutout.
        .padding(
          .top,
          controller.state.hangsBelowTheBezel
            ? controller.geometry.size.height + NotchState.bodyInset : 0
        )
        .padding(.bottom, controller.state.hangsBelowTheBezel ? 12 : 0)
        // Peek has no controls, so its whole body opens the panel. Expanded does,
        // so it gets no blanket tap — otherwise clicking near a button dismisses
        // the thing you were aiming at.
        .contentShape(Rectangle())
        .onTapGesture { controller.tapBody() }

      // The cutout itself is the toggle: the one place a click always opens and
      // closes the panel.
      //
      // It used to be the full width of the strip, which is now where the tabs and
      // the quota live — a blanket target across them would eat the clicks they
      // exist for. Last in the stack, so it wins over the content underneath it;
      // nothing is ever drawn in this rectangle anyway, it is a hole in the screen.
      Color.clear
        .frame(
          width: controller.geometry.size.width,
          height: controller.geometry.size.height
        )
        .contentShape(Rectangle())
        .onTapGesture { controller.toggleExpanded() }
    }
    // Clipped to the panel, so the content is *revealed* by the growing shape instead
    // of spilling past it. The content settles in 0.16s and the panel takes 0.38s, so
    // for a fifth of a second a full-width peek was drawing outside a panel that had
    // not reached that width yet — text over the wallpaper, either side of a black
    // box. That was the other half of what looked wrong.
    .clipShape(shape)
  }

  /// Recomputed from what is running, and pushed to the controller so the resting strip
  /// grows and shrinks with the content rather than reserving space for the worst case.
  /// The controller needs it too: it is what the cursor is tested against while idle.
  private var idleFlank: CGFloat {
    IdleView.flank(
      for: IdleReading(model.activity), waiting: model.permissions.waitingCount,
      quota: restingQuota, showsRemaining: model.preferences.showsRemainingQuota)
  }

  /// The plan the resting bar carries, or nil when the setting says the cutout should
  /// stay bare with nothing running.
  private var restingQuota: UsageLimitsReader.Reading? {
    guard model.preferences.restingQuota, model.preferences.showsUsageLimits else { return nil }
    if model.preferences.hidesWhenNoSessions, model.activity.visibleSessions.isEmpty {
      return nil
    }
    return model.usage.limits
  }

  private var shape: NotchShape {
    guard controller.state == .idle else {
      // The shoulder is what makes the top corners meet the menu bar on a curve
      // instead of a right angle. It reaches past the panel's own edge, so the
      // canvas reserves room for it — see `NotchState.shoulder`, which is where the
      // number lives precisely because two files have to agree on it.
      //
      // The collar is what keeps the menu bar. A panel that starts full-width at the
      // top of the screen buries the menus either side of the cutout; this one is
      // the hardware's width until the bezel and flares out below it.
      return NotchShape(
        bottomRadius: 18, shoulderRadius: NotchState.shoulder,
        collarWidth: controller.geometry.size.width,
        collarHeight: controller.state.hangsBelowTheBezel
          ? controller.geometry.size.height : 0)
    }
    // A painted resting strip carries more corner than an empty one: at 10pt of
    // overhang a 10pt radius is what makes it one shape wrapped around the cutout
    // rather than a rectangle stuck to it.
    return idleFlank > 0
      ? NotchShape(bottomRadius: 12, shoulderRadius: 8)
      : NotchShape(bottomRadius: 10, shoulderRadius: 6)
  }

  @ViewBuilder
  private var content: some View {
    switch controller.state {
    case .idle:
      IdleView(
        reading: IdleReading(model.activity),
        notchWidth: controller.geometry.size.width,
        notchHeight: controller.geometry.size.height,
        showsDetails: model.preferences.layout.showsCompactDetails,
        waiting: model.permissions.waitingCount,
        quota: restingQuota,
        showsRemaining: model.preferences.showsRemainingQuota)
    case .flash:
      if let notice = controller.notice {
        FlashView(notch: controller.geometry.size, notice: notice)
      }
    case .peek:
      PeekView(
        notch: controller.geometry.size,
        sessions: model.activity.visibleSessions,
        fallback: model.activity.events.first?.detail ?? t("waiting for Claude Code"),
        tokens: model.usage.today.totalTokens.compactTokens,
        cost: model.usage.today.cost.compactCost)
    case .expanded:
      ExpandedView(
        notch: controller.geometry.size, model: model,
        focusedSessionId: controller.activeSessionId,
        onHeightChange: { controller.setExpandedContentHeight($0) },
        onFocusChange: { controller.focus(sessionId: $0) },
        onClose: { controller.dismiss() })
    case .alert:
      alertContent
    }
  }

  /// The card, under a band that says where the request came from.
  ///
  /// Origin and queue depth are the same two facts whichever card it is, and they were
  /// repeated in each of the three headers — where they competed with the tool, the
  /// question or the plan for the one line that matters. They belong beside the cutout:
  /// the panel is 520pt wide and the hardware is 190 of it.
  @ViewBuilder
  private var alertContent: some View {
    if let pending = model.permissions.current {
      VStack(alignment: .leading, spacing: 8) {
        PanelHeader {
          AgentGlyph(agent: pending.agent, pixel: 1.5, isBreathing: false)
          Text(pending.projectName ?? pending.agent.displayName)
            .font(Theme.mono(10))
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
            .truncationMode(.head)
        } trailing: {
          if model.permissions.waitingCount > 1 {
            HStack(spacing: 6) {
              Chip(
                text: t("%lld waiting", model.permissions.waitingCount - 1),
                tint: Theme.warning)
              // The one at the head is not always the one worth deciding
              // first — this rotates it to the back without answering it, so
              // the rest of the queue stops hiding behind it.
              Button(t("Skip")) { model.skipCurrentPermission() }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondary)
            }
          }
        }

        card(for: pending)
          .padding(.horizontal, 14)
      }
    }
  }

  @ViewBuilder
  private func card(for pending: PendingPermission) -> some View {
    // A question and a plan are not permissions, and answering them with Allow/Deny
    // throws away the whole point of the tool.
    switch pending.kind {
    case .question(let request):
      QuestionCardView(
        request: request,
        draftID: pending.questionDraftID,
        drafts: model.questionDrafts,
        isReadOnly: pending.isObservationOnly,
        submit: { model.answer($0) },
        // Staying silent hands the question back to Claude Code's own prompt.
        cancel: { model.decide(.ask) }
      )
      // `id` resets the card's local selection when the next request arrives.
      .id(pending.id)
    case .plan(let request):
      PlanCardView(
        request: request,
        // Less the 14pt of padding either side that `alertContent` applies.
        contentWidth: controller.panelSize.width - 28,
        approve: { model.approvePlan($0) },
        reject: { model.rejectPlan(feedback: $0) }
      )
      .id(pending.id)
    case .permission:
      permissionContent(pending)
    }
  }

  @ViewBuilder
  private func permissionContent(_ pending: PendingPermission) -> some View {
    PermissionAlertView(
      pending: pending,
      waitingCount: model.permissions.waitingCount,
      decide: { decision, destination in
        model.decide(decision, rememberAt: destination)
      },
      decideAll: { model.decideAll($0) }
    )
    // Shortcuts are local to the panel, which only takes focus while an alert is
    // up — so Perch never needs Accessibility permission.
    .background {
      Group {
        Button("") { model.decide(.allow) }
          .keyboardShortcut(.return, modifiers: .option)
        Button("") { model.decide(.deny) }
          .keyboardShortcut(.delete, modifiers: .option)
        Button("") { model.decide(.allow) }
          .keyboardShortcut("y", modifiers: .control)
        Button("") { model.decide(.deny) }
          .keyboardShortcut("n", modifiers: .control)
        Button("") { model.decide(.allow, remember: true) }
          .keyboardShortcut("a", modifiers: .control)
        Button("") { model.bypassPermissions() }
          .keyboardShortcut("b", modifiers: .control)
        Button("") { TerminalJumper.jump(to: pending.request.client) }
          .keyboardShortcut("t", modifiers: .control)
      }
      .opacity(0)
    }
  }
}

// MARK: - The first row of a panel

/// What a state is, and what it offers — on one row, under the collar.
///
/// This lived in the band beside the cutout for a while, which used the 32pt of black the
/// panel was reserving anyway and looked right in isolation. It was not: that band is the
/// menu bar, and a 680pt panel drawn across it buries every menu either side of the
/// hardware. The panel hangs below the bezel now, so its header is a header again — the
/// difference is that the band above it is no longer part of the panel at all.
struct PanelHeader<Leading: View, Trailing: View>: View {
  @ViewBuilder var leading: Leading
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(spacing: 6) {
      leading
      Spacer(minLength: 8)
      trailing
    }
    .padding(.horizontal, 14)
    // Tall enough that the tabs and the round buttons sit in a band rather than on a
    // line: a header the exact height of its own text is one the eye reads as the
    // first row of the list under it.
    .frame(height: 26)
  }
}

/// A control small enough to sit in a shoulder.
struct ShoulderButton: View {
  let symbol: String
  var tint: Color = Theme.tertiary
  var help: String = ""
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 20, height: 20)
    }
    .buttonStyle(.plain)
    .help(help)
  }
}

/// The resting state: what is running, either side of the cutout.
///
/// With nothing running this draws nothing at all and the cutout looks exactly like the
/// hardware. The moment an agent is working there is something worth seeing without
/// hovering, and the menu bar beside the cutout is the only place to put it — so Vibe's
/// status sprite goes on the left and the count on the right, with the physical notch
/// left untouched between them.
struct IdleReading: Equatable {
  /// One entry per live session, in the panel's order — working first. Nothing draws
  /// them one by one any more; they still drive the count and the active state.
  var agents: [(agent: Agent, isWorking: Bool)] = []
  var count = 0
  /// Whether any of them is blocked on a person.
  var needsYou = false
  /// What the priority session is doing, formatted for the compact island.
  var summary = ""
  /// The state of the session the strip speaks for. It tints the sprite: blue while a
  /// harness works, amber when it waits on you, green once the turn is over.
  var status: SessionStatus?

  static func == (a: Self, b: Self) -> Bool {
    a.count == b.count && a.needsYou == b.needsYou
      && a.summary == b.summary && a.status == b.status
      && a.agents.map(\.agent) == b.agents.map(\.agent)
      && a.agents.map(\.isWorking) == b.agents.map(\.isWorking)
  }

  /// Every session the panel draws, working or not. This counted working sessions until
  /// it was pointed out that a CLI waiting for an answer is exactly the one you want to
  /// see from across the room — and it was invisible: the moment a permission card went
  /// up, the session left the strip and the count went down. Finished turns stay on the
  /// panel now, so they stay in the count too: the strip counts the same list the panel
  /// draws, and Vibe's pill says `2` over a green sprite for the same reason.
  ///
  /// The label and the sprite, though, belong to one session — and it is the one still
  /// working, not the one that most recently said something. A turn ending is always the
  /// newest event, and picking by recency put a finished session's title next to a
  /// running mark while another harness was actually at work.
  @MainActor
  init(_ activity: ActivityStore) {
    let sessions = activity.visibleSessions
    for session in sessions {
      agents.append((session.agent, session.isWorking))
    }
    count = sessions.count
    needsYou = sessions.contains { $0.status.needsYou }

    if let session = SessionDisplaySelection.priority(in: sessions) {
      summary = SessionDisplaySelection.compactSummary(for: session)
      status = session.status
    }
  }

  /// For the off-screen preview, which has no store to read.
  init(
    agents: [(agent: Agent, isWorking: Bool)], count: Int, needsYou: Bool,
    summary: String = "Bash: swift test", status: SessionStatus? = nil
  ) {
    self.agents = agents
    self.count = count
    self.needsYou = needsYou
    self.summary = summary
    self.status =
      status
      ?? (count == 0
        ? nil
        : needsYou ? .needsApproval : (agents.contains { $0.isWorking } ? .runningTool : .idle))
  }
}

/// Vibe Island's collapsed status sprite, as its `PixelStatusIconCompact(status:)` draws
/// it: one 20 x 14 invader tinted by the priority session's state, and — only while that
/// session works — an 11 x 11 companion trailing it. Green once the turn is over, blue
/// while a harness works, amber when it waits on you.
///
/// This is what the strip shows in place of the resting creature as soon as anything is
/// running: the creature says "nothing here", and an animated one next to a live count
/// said the opposite of what the panel underneath it did.
struct CompactStatusSprites: View {
  let status: SessionStatus?

  private var isWorking: Bool {
    status == .working || status == .runningTool || status == .compacting
      || status == .background
  }

  var body: some View {
    HStack(spacing: 4) {
      PixelStatusIconCompact(
        isPrimary: true, isWorking: isWorking, needsYou: status?.needsYou == true)
      if isWorking {
        PixelStatusIconCompact(isPrimary: false, isWorking: true, needsYou: false)
      }
    }
    .accessibilityHidden(true)
  }
}

/// The small Space-Invader status mark used by Vibe in the collapsed island.
///
/// The rows are reconstructed from the 1.0.44 idle and working captures at the
/// screenshot's native scale. Vibe changes the colour with the session state:
/// green after completion, blue while working, amber when input is required.
struct PixelStatusIconCompact: View {
  let isPrimary: Bool
  let isWorking: Bool
  let needsYou: Bool

  private var rows: [String] {
    if isPrimary {
      return [
        "..x....x..",
        "...x..x...",
        "..xxxxxx..",
        ".xx.oo.xx.",
        "xxxxxxxxxx",
        "x.xxxxxx.x",
        ".x......x.",
      ]
    }
    return [
      "...x...x...",
      "....x.x....",
      "...xxxxx...",
      "..xx.o.xx..",
      ".xxxxxxxxx.",
      ".x.xxxxx.x.",
      "...x...x...",
      "..x.....x..",
      ".x.......x.",
      "...........",
      "...........",
    ]
  }

  private var pixel: CGFloat { isPrimary ? 2 : 1 }

  private var tint: Color {
    if needsYou { return Theme.warning }
    return isWorking ? Theme.info : Theme.active
  }

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        HStack(spacing: 0) {
          ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
            Rectangle()
              .fill(colour(cell))
              .frame(width: pixel, height: pixel)
          }
        }
      }
    }
    .accessibilityHidden(true)
  }

  private func colour(_ cell: Character) -> Color {
    switch cell {
    case "x": return tint.opacity(isPrimary ? 0.90 : 0.68)
    case "o": return tint
    default: return .clear
    }
  }
}

/// The animated status mark used at the leading edge of a Vibe session card.
/// Reflection metadata for 1.0.44 shows a single `status` input plus animation state;
/// the previous Perch card incorrectly drew both collapsed-island icons on every row.
struct PixelSessionIcon: View {
  let status: SessionStatus
  @State private var phase = false

  private var isWorking: Bool {
    status == .working || status == .runningTool || status == .compacting
      || status == .background
  }

  var body: some View {
    PixelStatusIconCompact(
      isPrimary: true,
      isWorking: isWorking,
      needsYou: status.needsYou)
      .offset(y: isWorking && phase ? -1 : 0)
      .animation(
        isWorking
          ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true)
          : .default,
        value: phase)
      .onAppear { phase = true }
      .accessibilityHidden(true)
  }
}

struct IdleView: View {
  let reading: IdleReading
  let notchWidth: CGFloat
  let notchHeight: CGFloat
  let showsDetails: Bool
  /// How many requests are held. Distinct from the amber pill, which says *that* someone
  /// is waiting: this says how many, and four queued approvals is a different afternoon
  /// from one.
  var waiting: Int = 0
  /// What to say when nothing is running. The plan is the one thing that keeps moving on
  /// a machine with no session open — another window, another host, the window's own
  /// clock — so it is what the bar carries while it has no agent to draw.
  var quota: UsageLimitsReader.Reading?
  var showsRemaining = false
  var summaryMaximumWidth: CGFloat = 116

  private var count: Int { reading.count }
  /// The pill changes colour rather than growing a second badge — at 32pt there is room
  /// for one signal, and "someone is waiting for you" outranks everything else.
  private var needsYou: Bool { reading.needsYou }

  /// The bar says one thing at a time. An agent outranks the plan: what is running now is
  /// worth more of a glance than what the week has cost, and two rows of numbers either
  /// side of the hardware would be a dashboard rather than a strip.
  private var showsQuota: Bool { count == 0 && !IdleView.windows(of: quota).isEmpty }

  var body: some View {
    Group {
      if showsQuota {
        HStack(spacing: 5) {
          IslandPresetSprite(side: 18)
          UsageLimitsStrip(
            reading: quota, showsRemaining: showsRemaining, maximum: 2,
            showsReset: false)
        }
      } else if count > 0 {
        HStack(spacing: 10) {
          CompactStatusSprites(status: reading.status)

          Spacer(minLength: 6)

          if showsDetails, !reading.summary.isEmpty {
            Text(reading.summary)
              .font(Theme.mono(11, .bold))
              .foregroundStyle(Theme.primary)
              .lineLimit(1)
              .truncationMode(.tail)
              .frame(maxWidth: summaryMaximumWidth, alignment: .trailing)
          }

          if waiting > 0 || needsYou {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.system(size: 8, weight: .bold))
              .foregroundStyle(Theme.warning)
          }

          Text("\(count)")
            .font(Theme.mono(11, .bold))
            .foregroundStyle(Theme.primary)
            .monospacedDigit()
        }
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 30, alignment: .center)
  }

  /// Gap between the content and the cutout, on each side.
  static let inset: CGFloat = 5

  /// How big a sprite the resting strip carries. Two thirds of the 32pt band: at 20pt a
  /// creature reads as a mark, and at 24 it reads as itself.
  static let glyphPixel: CGFloat = 2.4
  /// Between the resting creature and the window beside it.
  static let spriteGap: CGFloat = 4

  /// What the enclosing `HStack` puts behind each chip — 6pt on the left of the cutout,
  /// 4 on the right. Counted in the width, because it is drawn whether or not anyone
  /// remembered it: forgetting the 6 is what left the first chip a point short.
  static let quotaGap: CGFloat = 6

  /// Sized to the content: one agent must not reserve room for four, and an empty strip
  /// must be exactly zero wide or it paints black shoulders beside the notch.
  ///
  /// The inset is part of this number. It was not at first, and the window came out ten
  /// points narrower than what it had to draw — so the count was clipped by the edge it
  /// was supposed to sit inside.
  static func flank(
    for reading: IdleReading, waiting: Int = 0,
    quota: UsageLimitsReader.Reading? = nil, showsRemaining: Bool = false
  ) -> CGFloat {
    // Nothing running: the plan, if there is one to show.
    //
    // This used to return zero unconditionally — a Mac doing nothing looked like a Mac
    // doing nothing, and the quota was not allowed to open two black shoulders on a
    // machine with no session. It earns them: it is the one number that keeps moving
    // while nothing here is running, and reading it should not cost a hover.
    //
    // Zero still, when there is nothing to say. A bridge that was never installed
    // leaves the cutout exactly as the hardware made it.
    guard reading.count > 0 else {
      let windows = windows(of: quota)
      guard !windows.isEmpty else { return 0 }

      // Measured off the layout, not off a sentence. The window is sized before it
      // draws, so a width taken on faith is a chip wrapped onto a second line inside
      // the menu bar — which is exactly what a joined string bought: it counted two
      // spaces where the `HStack` puts two 3pt gaps, and none of the 6pt the strip
      // sits behind.
      func chip(_ index: Int) -> CGFloat {
        guard windows.indices.contains(index) else { return 0 }
        return UsageLimitsStrip.width(
          for: windows[index], showsRemaining: showsRemaining, showsReset: false)
      }
      // The agent's glyph is always drawn — it falls back to pixel art of our own
      // when no sheet is installed. The resting creature is not: no sheet, no room
      // reserved, and the week's number closes up against the cutout rather than
      // sitting beside a hole.
      let resting = IdleSprite.sheet == nil ? 0 : IdleSprite.side + spriteGap
      let left = AgentGlyph.width(pixel: glyphPixel) + spriteGap + chip(0) + quotaGap
      let right = chip(1) + resting + quotaGap
      return max(left, right) + inset
    }

    // The compact activity line mostly uses the cutout's own width. A small, symmetric
    // shoulder supplies the two rounded ends without turning it into a menu-bar strip.
    return 3
  }

  /// The two windows the resting bar has room for, in the order it draws them: the
  /// tightest on the left, the next on the right. Empty when the bridge has published
  /// nothing, which is what keeps the cutout bare.
  static func windows(of reading: UsageLimitsReader.Reading?) -> [NamedWindow] {
    Array(reading?.limits.windows.prefix(2) ?? [])
  }
}

/// The creature that keeps the cutout company when no agent does.
///
/// Its own sheet — `idle.png`, beside the agents' in `~/.perch/sprites` — because this one
/// is not an agent: nothing is running, and drawing Claude's would say something untrue.
/// Held on its first frame rather than played: a creature flapping its wings in the menu
/// bar for hours is noise, and the bar is meant to be glanceable, not animated.
///
/// Nothing installed is nothing drawn, and the width follows: the two percentages simply
/// close up. Perch ships no sheet — what would be in one is not ours to redistribute.
struct IdleSprite: View {
  /// The same 24pt box an agent's glyph occupies, so a strip that swaps one for the
  /// other does not change height or jump.
  static let side: CGFloat = AgentGlyph.width(pixel: IdleView.glyphPixel) - 3

  static var sheet: SpriteSheet? {
    if let cached { return cached }
    let loaded = SpriteLocation.sheetURL(
      named: "idle",
      bundled: Bundle.main.url(
        forResource: "idle", withExtension: "png", subdirectory: "Sprites")
    ).flatMap(SpriteSheet.load)
    cached = .some(loaded)
    return loaded
  }

  /// Read once. A miss costs a directory lookup, and this is on the path of a view that
  /// redraws with the clock.
  nonisolated(unsafe) private static var cached: SpriteSheet??

  var body: some View {
    if let sheet = Self.sheet {
      AnimatedSprite(sheet: sheet, side: Self.side, isPlaying: false)
    }
  }
}

private struct PulsingDot: View {
  let tint: Color
  @State private var isPulsing = false

  var body: some View {
    Circle()
      .fill(tint)
      .frame(width: 5, height: 5)
      .opacity(isPulsing ? 1 : 0.3)
      .animation(
        .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing
      )
      .onAppear { isPulsing = true }
  }
}

/// Hover preview: which sessions are running, and what today has cost.
///
/// It used to answer *how many* — a count, the last tool call from whichever session
/// emitted it, and the day's total. Which is the one question the resting strip already
/// answers, so hovering bought a bigger version of what you could see without hovering.
/// The band beside the cutout takes the totals, and the body says who: one row per
/// session, the same order the panel lists them in.
struct PeekView: View {
  let notch: CGSize
  /// Plain data rather than the stores, so the off-screen preview draws the same view
  /// the app does instead of an imitation of it that can drift.
  let sessions: [SessionSnapshot]
  /// What to say when nothing is running: the last thing that happened.
  let fallback: String
  let tokens: String
  let cost: String

  /// Three rows is the most that fits before the peek becomes the panel.
  private var shown: [SessionSnapshot] { Array(sessions.prefix(3)) }
  private var hidden: Int { max(0, sessions.count - shown.count) }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      PanelHeader {
        Text(headline)
          .font(Theme.mono(10))
          .foregroundStyle(Theme.secondary)
          .lineLimit(1)
      } trailing: {
        Text(tokens)
          .font(Theme.mono(10, .semibold))
          .foregroundStyle(Theme.primary)
        Text(cost)
          .font(Theme.mono(10))
          .foregroundStyle(Theme.active)
        // Without this the peek reads as a dead end: nothing suggests the panel
        // goes any further.
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(Theme.tertiary)
      }

      VStack(alignment: .leading, spacing: 3) {
        if shown.isEmpty {
          Text(fallback)
            .font(Theme.mono(10))
            .foregroundStyle(Theme.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
        } else {
          ForEach(shown, id: \.id) { session in
            PeekRow(session: session)
          }
          if hidden > 0 {
            Text(t("+%lld more", hidden))
              .font(Theme.mono(9))
              .foregroundStyle(Theme.tertiary)
          }
        }
      }
      .padding(.horizontal, 14)
      .padding(.top, 2)
    }
  }

  /// Live, not working — the same count the resting strip shows, so the number does not
  /// change under the cursor on the way in.
  private var headline: String {
    let live = sessions.count
    let blocked = sessions.filter { $0.status.needsYou }.count
    guard live > 0 else { return t("Perch") }
    guard blocked > 0 else { return t("%lld live", live) }
    return t("%lld live · %lld on you", live, blocked)
  }
}

/// One session, on one line: who, what, how long, and whether it needs you.
struct PeekRow: View {
  let session: SessionSnapshot

  var body: some View {
    HStack(spacing: 6) {
      AgentGlyph(
        agent: session.agent, pixel: 1.4,
        isBreathing: session.isWorking, isFighting: false)

      Text(session.projectName ?? t("session"))
        .font(Theme.mono(10))
        .foregroundStyle(Theme.primary)
        .lineLimit(1)

      Text(session.activitySummary.text)
        .font(Theme.mono(10))
        .foregroundStyle(session.activitySummary.tint)
        .lineLimit(1)
        .truncationMode(.middle)

      Spacer(minLength: 4)

      Text(SessionCardView.elapsed(since: session.startedAt))
        .font(Theme.mono(9))
        .foregroundStyle(Theme.tertiary)
        .monospacedDigit()

      StateIndicator(status: session.status, isActive: session.isWorking)
    }
  }
}

// MARK: - Expanded

/// The menu-bar band stays alive while the panel is expanded. Quota owns the left
/// shoulder, the same compact session reading stays centred over the hardware, and the
/// controls own the right shoulder.
struct ExpandedPanelHeader<Leading: View, Trailing: View>: View {
  private static var panelWidth: CGFloat { 650 }

  let notch: CGSize
  let reading: IdleReading
  let waiting: Int
  @ViewBuilder let leading: Leading
  @ViewBuilder let trailing: Trailing

  private var shoulderWidth: CGFloat {
    max(0, (Self.panelWidth - 40 - notch.width - 12) / 2)
  }

  var body: some View {
    ZStack {
      HStack(spacing: 0) {
        leading
          .fixedSize(horizontal: true, vertical: true)
          .frame(width: shoulderWidth, alignment: .leading)
          .clipped()

        Color.clear
          .frame(width: notch.width + 12)

        trailing
          .frame(width: shoulderWidth, alignment: .trailing)
      }
      .padding(.horizontal, 20)

      IdleView(
        reading: reading,
        notchWidth: notch.width,
        notchHeight: notch.height,
        showsDetails: true,
        waiting: waiting,
        quota: nil,
        showsRemaining: false,
        summaryMaximumWidth: 92)
        .frame(width: notch.width + 6)
    }
    .frame(height: 36)
  }
}

/// What the expanded panel is about. Sessions by default; the plan and the board on their
/// own tabs, so "how much of the week is left" and "who is winning" are a click away
/// rather than a settings window away.
private enum PanelTab: String, CaseIterable {
  case activity, stats, rank
}

private struct ExpandedView: View {
  let notch: CGSize
  let model: AppModel
  let focusedSessionId: String?
  let onHeightChange: (CGFloat) -> Void
  let onFocusChange: (String) -> Void
  let onClose: () -> Void
  @State private var openedSessionId: String?
  @State private var showsAllSessions = false
  /// Back to `activity` every time the panel opens: what is running is the reason to open
  /// it, and a stats tab left selected yesterday should not hide today's session.
  @State private var tab: PanelTab = .activity

  /// The strip's own row under the header, in the height and on screen.
  private static let tabStripHeight: CGFloat = 24

  init(
    notch: CGSize, model: AppModel, focusedSessionId: String?,
    onHeightChange: @escaping (CGFloat) -> Void,
    onFocusChange: @escaping (String) -> Void,
    onClose: @escaping () -> Void
  ) {
    self.notch = notch
    self.model = model
    self.focusedSessionId = focusedSessionId
    self.onHeightChange = onHeightChange
    self.onFocusChange = onFocusChange
    self.onClose = onClose
    let visible = model.activity.visibleSessions
    let initiallyOpened = SessionDisplaySelection.featured(
      in: visible, focusedSessionId: focusedSessionId)?.id
    _openedSessionId = State(initialValue: initiallyOpened)
  }

  private var selectedSessionId: String? { openedSessionId ?? focusedSessionId }

  private var displayedSessions: [SessionSnapshot] {
    SessionDisplaySelection.shown(
      in: model.activity.visibleSessions,
      focusedSessionId: selectedSessionId,
      showsAll: showsAllSessions)
  }

  private var additionalSessionCount: Int {
    SessionDisplaySelection.additionalCount(
      in: model.activity.visibleSessions,
      focusedSessionId: selectedSessionId,
      showsAll: showsAllSessions)
  }

  private var contentHeight: CGFloat {
    // The stats and rank panes have their own fixed shape; only the session list is
    // measured. 452 is what the panel used to be before it followed its content, and
    // `NotchState.expandedHeight` still clamps it to the person's maximum.
    guard tab == .activity else {
      return notch.height + NotchState.bodyInset + 36 + Self.tabStripHeight + 452 + 20
    }
    let rows = displayedSessions.reduce(CGFloat.zero) { total, session in
      let isOpen = openedSessionId == session.id
      let hasConversation = session.turn?.isEmpty == false || session.prompt?.isEmpty == false
      let revealsConversation =
        isOpen && model.preferences.layout.showsPrompt && hasConversation
      let summarySpacing: CGFloat =
        model.preferences.layout.showsPrompt && hasConversation ? 3 : 0
      let board = model.tasks.board(for: session.id)
      let visibleTaskRows =
        min(board.tasks.count, 3) + (board.tasks.count > 3 ? 1 : 0)
      let taskHeight: CGFloat =
        !isOpen || board.isEmpty || !model.preferences.layout.showsTasks
          || !model.preferences.showsTasks
          ? 0
          : 34 + CGFloat(visibleTaskRows) * 22
      return total + 34 + summarySpacing + (revealsConversation ? 166 : 0) + taskHeight
    }
    let footerHeight: CGFloat = additionalSessionCount > 0 ? 24 : 0
    return notch.height + NotchState.bodyInset + 36 + Self.tabStripHeight
      + min(max(rows + footerHeight, 96), 452) + 20
  }

  private var sessionGeometrySignature: [String] {
    model.activity.visibleSessions.map {
      "\($0.id):\($0.status.rawValue):\($0.turn?.isEmpty == false):\($0.prompt?.isEmpty == false)"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ExpandedPanelHeader(
        notch: notch,
        reading: IdleReading(model.activity),
        waiting: model.permissions.waitingCount
      ) {
        if model.preferences.showsUsageLimits {
          UsageHeaderCycle(
            usage: model.usage,
            showsRemaining: model.preferences.showsRemainingQuota,
            showsReset: model.preferences.showsResetCards)
        }
      } trailing: {
        HStack(spacing: 10) {
        if model.preferences.showsUpdateIndicator, let update = model.updates.available {
          ShoulderButton(
            symbol: "arrow.up.circle.fill", tint: Theme.info,
            help: t("Update to %@", update.version)
          ) {
            Task { await model.updates.install(update) }
          }
        }

        // Muting is a thing you want *while* a machine is being noisy, which is
        // never the moment to go and find a settings window.
        ShoulderButton(
          symbol: model.sounds.enabled ? "speaker.wave.2" : "speaker.slash",
          tint: Theme.tertiary,
          help: model.sounds.enabled ? t("Mute sounds") : t("Unmute sounds")
        ) { model.updateSounds(model.sounds.toggledEnabled) }

        // With no Dock icon and no menu bar item, this is the only way in.
        ShoulderButton(symbol: "gearshape.fill", help: t("Settings")) {
          model.showSettings()
        }
        }
      }

      TabBar(selection: tab) { tab = $0 }
        .padding(.horizontal, 20)
        .frame(height: Self.tabStripHeight)

      Group {
        switch tab {
        case .activity:
          ActivityList(
            model: model,
            focusedSessionId: focusedSessionId,
            opened: $openedSessionId,
            showsAllSessions: $showsAllSessions,
            onFocusChange: onFocusChange)
        case .stats:
          StatsView(
            usage: model.usage,
            showsRemaining: model.preferences.showsRemainingQuota,
            onToggleQuota: {
              var next = model.preferences
              next.showsRemainingQuota.toggle()
              model.updatePreferences(next)
            })
        case .rank:
          RankView(model: model)
        }
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 20)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear {
      if let openedSessionId { onFocusChange(openedSessionId) }
      onHeightChange(contentHeight)
    }
    .onChange(of: tab) { _, _ in onHeightChange(contentHeight) }
    .onChange(of: model.tasks.revision) { _, _ in
      if openedSessionId == nil,
        let planned = model.activity.visibleSessions.first(where: {
          !model.tasks.board(for: $0.id).isEmpty
        })
      {
        openedSessionId = planned.id
      }
      onHeightChange(contentHeight)
    }
    .onChange(of: sessionGeometrySignature) { _, _ in onHeightChange(contentHeight) }
    .onChange(of: openedSessionId) { _, sessionId in
      if let sessionId { onFocusChange(sessionId) }
      onHeightChange(contentHeight)
    }
    .onChange(of: showsAllSessions) { _, _ in onHeightChange(contentHeight) }
    .onChange(of: model.preferences.layout) { _, _ in onHeightChange(contentHeight) }
    .onChange(of: focusedSessionId) { _, sessionId in
      guard let sessionId,
        model.activity.visibleSessions.contains(where: { $0.id == sessionId })
      else { return }
      openedSessionId = sessionId
    }
    // Opening the panel is the moment to catch up on plans that moved while Perch was
    // not running, or while a session sat quiet — but *after* it has finished opening.
    // Reading transcripts on the frame the morph starts is work competing with the
    // spring for the same 0.38s.
    .task {
      try? await Task.sleep(for: .milliseconds(420))
      guard !Task.isCancelled else { return }
      model.tasks.refreshAll(model.activity.activeSessions)
    }
  }
}

/// The three panes, as pills. The selected one is lit; the others are there to be found.
private struct TabBar: View {
  let selection: PanelTab
  let onSelect: (PanelTab) -> Void

  var body: some View {
    HStack(spacing: 4) {
      ForEach(PanelTab.allCases, id: \.self) { tab in
        Button { onSelect(tab) } label: {
          Text(t(tab.rawValue))
            .font(Theme.label(11, .medium))
            .foregroundStyle(tab == selection ? Theme.primary : Theme.tertiary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
              RoundedRectangle(cornerRadius: 6)
                .fill(tab == selection ? Theme.hairlineStrong : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("panel.tab.\(tab.rawValue)")
      }
      Spacer(minLength: 0)
    }
  }
}

/// Vibe rotates through each available provider in the expanded header. Each provider
/// keeps its own windows together: Codex is one weekly lane, Claude is 5h + 7d + model.
private struct UsageHeaderCycle: View {
  let usage: UsageModel
  let showsRemaining: Bool
  let showsReset: Bool
  @State private var selectedProvider: UsageStore.Agent?

  private struct Entry: Identifiable {
    let id: UsageStore.Agent
    let reading: UsageLimitsReader.Reading
  }

  private var entries: [Entry] {
    var result: [Entry] = []
    if let reading = usage.codexLimits { result.append(Entry(id: .codex, reading: reading)) }
    if let reading = usage.claudeLimits { result.append(Entry(id: .claude, reading: reading)) }
    return result
  }

  private var selectedEntry: Entry? {
    selectedProvider.flatMap { provider in entries.first { $0.id == provider } }
      ?? entries.first
  }

  var body: some View {
    if let entry = selectedEntry {
      Button {
        selectedProvider = UsageProviderCycle.next(
          after: entry.id, in: entries.map(\.id))
      } label: {
        HStack(spacing: 5) {
          UsageProviderBadge(provider: entry.id)
          UsageLimitsStrip(
            reading: entry.reading, showsRemaining: showsRemaining,
            maximum: 2, fontSize: 10, usesSystemFont: true,
            showsReset: showsReset)
        }
      }
      .buttonStyle(.plain)
      .contentShape(Rectangle())
      .help(t("Switch usage provider"))
      .accessibilityElement(children: .combine)
      .accessibilityLabel(t("Usage limits"))
      .accessibilityValue(entry.id == .codex ? "Codex" : "Claude")
      .onAppear { selectedProvider = entry.id }
      .onChange(of: entries.map(\.id)) { _, providers in
        guard let selectedProvider, providers.contains(selectedProvider) else {
          self.selectedProvider = providers.first
          return
        }
      }
    }
  }
}

private struct UsageProviderBadge: View {
  let provider: UsageStore.Agent

  var body: some View {
    Circle()
      .fill(provider == .codex ? Color.white.opacity(0.45) : Color(hex: 0xF06C5E))
      .frame(width: 12, height: 12)
      .overlay {
        Image(systemName: provider == .codex ? "circle.dotted" : "sparkles")
          .font(.system(size: 7, weight: .bold))
          .foregroundStyle(.white)
      }
      .accessibilityHidden(true)
  }
}

/// The creature beside the plan when nothing is running. The installed `idle.png` sheet
/// is Mewtwo and already survives app updates in `~/.perch/sprites`; it is one animation
/// clock, not one per session, which is what previously saturated the main thread. It
/// leaves the strip the moment a harness runs — Vibe's status sprite takes its place,
/// because a creature that means "idle" has no business next to a live count.
private struct IslandPresetSprite: View {
  let side: CGFloat

  var body: some View {
    if let sheet = IdleSprite.sheet {
      AnimatedSprite(sheet: sheet, side: side, isPlaying: true)
        .accessibilityHidden(true)
    }
  }
}

/// Sessions first, then the tool feed underneath.
///
/// The feed alone answered "what just happened"; the cards answer "what are my agents
/// doing", which is the reason to open the notch at all.
private struct ActivityList: View {
  let model: AppModel
  let focusedSessionId: String?

  /// The one row that is open, if any.
  ///
  /// One at a time, and closed to begin with. Six sessions of full cards is four screens
  /// of scrolling, and a panel you have to scroll is a panel you do not glance at.
  @Binding var opened: String?
  @Binding var showsAllSessions: Bool
  let onFocusChange: (String) -> Void

  private var activity: ActivityStore { model.activity }
  private var selectedSessionId: String? { opened ?? focusedSessionId }
  private var shownSessions: [SessionSnapshot] {
    SessionDisplaySelection.shown(
      in: activity.visibleSessions,
      focusedSessionId: selectedSessionId,
      showsAll: showsAllSessions)
  }
  private var additionalSessionCount: Int {
    SessionDisplaySelection.additionalCount(
      in: activity.visibleSessions,
      focusedSessionId: selectedSessionId,
      showsAll: showsAllSessions)
  }

  var body: some View {
    if activity.sessions.isEmpty && activity.events.isEmpty {
      // An empty panel has several causes with opposite fixes, so it says which.
      EmptyStateView(health: activity.health)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else {
      VStack(alignment: .leading, spacing: Theme.rowSpacing) {
        ScrollView {
          // Cycling past the fold used to move a selection nobody could see. The
          // reader is only ever driven by the switcher — scrolling the panel while
          // someone is reading it would be the opposite of helpful.
          ScrollViewReader { scroller in
            LazyVStack(alignment: .leading, spacing: Theme.rowSpacing) {
              HealthBanner(advice: activity.health.advice())

              ForEach(
                Array(shownSessions.enumerated()), id: \.element.id
              ) { position, session in
                SessionCardView(
                  session: session,
                  tasks: model.tasks.board(for: session.id),
                  layout: model.preferences.layout,
                  allowsJump: !model.preferences.disablesSessionJump,
                  contentFontSize: model.preferences.contentFontSize,
                  showsProjectName: model.preferences.showsProjectName,
                  showsWorktree: model.preferences.showsWorktree,
                  showsAIModel: model.preferences.showsAIModel,
                  showsReasoningEffort: model.preferences.showsReasoningEffort,
                  showsTasks: model.preferences.showsTasks,
                  showsSubagents: model.preferences.showsSubagents,
                  showsActivityDetails: model.preferences.showsActivityDetails,
                  jumpLabel: ShortcutFormatter.describe(
                    keyCode: model.preferences.switcherKeyCode,
                    modifiers: model.preferences.switcherModifiers) + " ↗",
                  isActive: session.isWorking,
                  isFocused: model.switcher.isOpen && model.switcher.index == position,
                  isCollapsed: opened != session.id,
                  onToggle: {
                    let next = opened == session.id ? nil : session.id
                    opened = next
                    if let next { onFocusChange(next) }
                  },
                  onJump: { TerminalJumper.jump(to: session.client) },
                  onArchive: { model.archiveSession(session.id) },
                  onSilence: { rule in
                    var policy = activity.admission
                    policy.add(rule)
                    activity.updateAdmission(policy)
                  }
                )
              }
            }
            .onChange(
              of: activity.visibleSessions.map { "\($0.id):\($0.status.rawValue)" }
            ) { _, _ in
              guard
                let completed = shownSessions.last(where: {
                  $0.status == .idle
                    && ($0.turn?.isEmpty == false || $0.prompt?.isEmpty == false)
                })
              else { return }
              opened = completed.id
            }
            .onChange(of: model.switcher.index) { _, index in
              guard model.switcher.isOpen,
                activity.visibleSessions.indices.contains(index)
              else { return }
              if index >= shownSessions.count { showsAllSessions = true }
              withAnimation(.easeOut(duration: 0.12)) {
                scroller.scrollTo(activity.visibleSessions[index].id, anchor: .center)
              }
            }
          }
        }
        .scrollIndicators(.never)

        if additionalSessionCount > 0 {
          ShowAllSessionsButton(count: additionalSessionCount) {
            showsAllSessions = true
          }
        }
      }
    }
  }
}

/// The rest of the sessions, behind one quiet line.
///
/// This was a 52pt raised card with a glyph and an arrow, which read like Vibe's
/// paywall row rather than a disclosure — and it carried two numbers that disagreed:
/// "Show all N+1 sessions" over "+N additional". `count` is already the hidden count,
/// so one honest number is the whole message. Vibe keeps this to a single 11pt row that
/// lifts on hover; so does this.
struct ShowAllSessionsButton: View {
  let count: Int
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Text(t("+%lld more sessions", count))
          .font(Theme.label(11))
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .semibold))
      }
      .foregroundStyle(isHovered ? Theme.primary : Theme.secondary)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 4)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .accessibilityIdentifier("sessions.show-all")
  }
}

/// A live configuration problem above the sessions it affects.
///
/// Vibe keeps these warnings in the session list rather than hiding them in Settings;
/// otherwise a populated panel can look healthy while its newest sessions are detached.
private struct HealthBanner: View {
  let advice: HookHealth.Advice

  @ViewBuilder
  var body: some View {
    switch advice {
    case .fine:
      EmptyView()
    case .restartSessions:
      PanelStatusBanner(
        icon: "arrow.clockwise.circle.fill",
        title: t("Restart your sessions"),
        detail: t("Hooks just installed — restart running sessions to connect."),
        tint: Theme.info)
    case .reinstallHooks(let missing):
      PanelStatusBanner(
        icon: "wrench.and.screwdriver.fill",
        title: t("Reinstall recommended"),
        detail: t("%lld hook files no longer contain Perch.", missing),
        tint: Theme.warning)
    case .notInstalled:
      PanelStatusBanner(
        icon: "bolt.slash.fill",
        title: t("Hooks are not installed"),
        detail: t("Install hooks, then restart your sessions."),
        tint: Theme.warning)
    case .installedTwice(let sites):
      PanelStatusBanner(
        icon: "square.on.square",
        title: t("Hooks are installed twice"),
        detail: t("%lld project hook files duplicate the global installation.", sites),
        tint: Theme.info)
    }
  }
}

private struct PanelStatusBanner: View {
  let icon: String
  let title: String
  let detail: String
  let tint: Color

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 14)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(Theme.label(10, .semibold))
          .foregroundStyle(Theme.primary)
        Text(detail)
          .font(Theme.mono(9))
          .foregroundStyle(Theme.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
    .padding(8)
    .background(
      RoundedRectangle(cornerRadius: Theme.cornerRadius)
        .fill(tint.opacity(0.09))
        .overlay {
          RoundedRectangle(cornerRadius: Theme.cornerRadius)
            .stroke(tint.opacity(0.2), lineWidth: 0.5)
        }
    )
  }
}

/// What an empty panel means, and what to do about it.
///
/// "No activity yet" is not an answer: hooks stripped by another tool and sessions that
/// started before the hooks existed look identical from here, and the fixes are opposite.
private struct EmptyStateView: View {
  let health: HookHealth

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(Theme.label(11))
        .foregroundStyle(tint)
      Text(detail)
        .font(Theme.mono(10))
        .foregroundStyle(Theme.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var title: String {
    switch health.advice() {
    case .fine: return t("No activity yet")
    case .restartSessions: return t("Restart your sessions")
    case .reinstallHooks: return t("Hooks were removed")
    case .notInstalled: return t("Hooks are not installed")
    case .installedTwice: return t("Hooks are installed twice")
    }
  }

  private var detail: String {
    switch health.advice() {
    case .fine:
      return t("Waiting for Claude Code.")
    case .restartSessions:
      return t(
        "Hooks are installed, but a session already open ignores them — Claude Code "
          + "reads them once, at session start.")
    case .reinstallHooks(let missing):
      return t(
        "%lld settings files no longer mention Perch. Another tool may manage them "
          + "too. Run ./scripts/install-hooks.sh again.", missing)
    case .notInstalled:
      return t("Run ./scripts/install-hooks.sh <project>, then restart your sessions.")
    case .installedTwice(let sites):
      return t(
        "%lld projects install Perch on top of the global hooks, so every event "
          + "fires twice. The copies are dropped, but the second hook still runs: "
          + "./scripts/install-hooks.sh --uninstall <project>.", sites)
    }
  }

  private var tint: Color {
    switch health.advice() {
    case .fine: return Theme.secondary
    case .restartSessions: return Theme.info
    case .reinstallHooks, .notInstalled: return Theme.warning
    case .installedTwice: return Theme.info
    }
  }
}

private struct EventRow: View {
  let event: ActivityEvent

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Circle()
        .fill(statusColor)
        .frame(width: 4, height: 4)

      Text(event.tool ?? event.kind)
        .font(Theme.mono(10, .medium))
        .foregroundStyle(Theme.primary.opacity(0.9))
        .frame(width: 68, alignment: .leading)

      // Which project this happened in, before what happened. A feed of bare paths
      // and commands is unreadable the moment two agents are running: every line
      // needs to say whose work it is.
      if let project = event.projectName {
        Text(project)
          .font(Theme.mono(10))
          .foregroundStyle(Theme.tertiary)
          .lineLimit(1)
          .layoutPriority(1)
      }

      Text(event.location)
        .font(Theme.mono(10))
        .foregroundStyle(Theme.secondary)
        .lineLimit(1)
        .truncationMode(.middle)

      Spacer(minLength: 0)

      Text(event.date, format: .dateTime.hour().minute().second())
        .font(Theme.mono(9))
        .foregroundStyle(Theme.tertiary)
    }
  }

  private var statusColor: Color {
    switch event.status {
    case .running: return Theme.warning
    case .done: return Theme.active.opacity(0.7)
    case .failed: return Theme.danger
    }
  }
}
