import PerchKit
import SwiftUI

/// One running agent, as a card.
///
/// The panel used to be a feed of tool calls, which answers "what just happened" but not
/// "what are my agents doing" — and the second is the question you open the notch for.
/// A card is per session: what it is working on, what you asked, where it runs, how long
/// it has been going.
struct SessionCardView: View {
  let session: SessionSnapshot
  /// The session's plan, empty for the many sessions that never use the task tool.
  var tasks: TaskBoard = .empty
  /// The compact-strip density. Expanded cards keep their prompt and plan in both modes.
  var layout: PanelLayout = .detailed
  var allowsJump = true
  var contentFontSize: Double = 11
  var showsProjectName = true
  var showsWorktree = true
  var showsAIModel = true
  var showsReasoningEffort = true
  var showsTasks = true
  var showsSubagents = true
  var showsActivityDetails = true
  var jumpLabel = "⌃G ↗"
  /// Selected by the switcher. Distinct from hover: the keyboard and the mouse can point
  /// at different cards at the same time.
  var isActive = false
  var isFocused = false
  /// Whether this card is showing the exchange, the subagents and the plan.
  ///
  /// Closed is the default and the resting state of the whole list. A card open is a card
  /// asked for: six sessions of full cards is four screens of scrolling, and the panel
  /// exists to be read at a glance.
  var isCollapsed = true
  var onToggle: (() -> Void)?
  var onJump: (() -> Void)?
  var onArchive: (() -> Void)?
  var onSilence: ((AdmissionRule) -> Void)?

  @State private var isHovered = false

  private var isOpen: Bool { !isCollapsed }

  /// Persisted sessions can outlive a parser upgrade. Clean again at the rendering
  /// boundary so an old teammate transport payload disappears immediately on relaunch
  /// rather than waiting for that session's next hook event.
  private var visiblePrompt: String? {
    guard let prompt = session.prompt else { return nil }
    let cleaned = SessionTracker.condense(prompt)
    guard !cleaned.isEmpty else { return nil }
    let lowercased = cleaned.lowercased()
    if lowercased.hasPrefix("code=")
      || lowercased.contains("get_app_state")
      || lowercased.contains("element_index")
      || lowercased.contains("noderepl")
      || lowercased.contains("sky.")
      || lowercased.contains("tools.")
    {
      return nil
    }
    return cleaned
  }

  private var plan: JumpPlan { TerminalJump.plan(for: session.client) }

  /// Whether opening this card would show anything that closing it does not.
  ///
  /// Often it would not: a session with no turn read yet, no prompt, no subagents and no
  /// plan has nothing under its headline. Clicking one of those toggled a disclosure arrow
  /// over an unchanged row, which
  /// reads as a card that is broken rather than as a card that is empty.
  private var hasDetail: Bool {
    if layout.showsPrompt, session.turn?.isEmpty == false { return true }
    if layout.showsPrompt, visiblePrompt != nil { return true }
    if layout.showsTasks, showsSubagents, !session.children.isEmpty { return true }
    if layout.showsTasks, showsTasks, !tasks.isEmpty { return true }
    return false
  }

  /// A click with nothing to open goes where the work is instead.
  ///
  /// Only when the jump can actually happen — a session whose terminal was never recorded
  /// keeps the toggle, because falling through to nothing at all is the behaviour this
  /// replaces.
  private var tapJumps: Bool { allowsJump && !hasDetail && plan.isPossible }

  /// Each agent keeps its own colour, so two of them in the same project stay apart.
  private var agentTint: Color {
    switch session.agent {
    case .claude: return Theme.claude
    case .codex: return Theme.info
    case .gemini: return Theme.warning
    // No brand colour of its own here, so it borrows the "working / succeeded" green —
    // distinct from the other three and already the tone the glyph draws it in.
    case .opencode: return Theme.active
    case .cursor: return Theme.info
    case .droid: return Theme.warning
    case .pi: return Theme.active
    case .amp: return Theme.claude
    case .kimi: return Theme.info
    case .deepseek: return Theme.active
    case .mistralVibe: return Theme.warning
    case .workbuddy: return Theme.info
    case .codebuddy: return Theme.active
    case .antigravity: return Theme.warning
    case .copilot: return Theme.info
    case .unknown: return Theme.secondary
    }
  }

  var body: some View {
    card
      .contentShape(Rectangle())
      .onHover { isHovered = $0 }
      // The row opens and closes; the terminal chip is what jumps.
      //
      // The whole card used to be the jump target, which is a lot of surface for an
      // action that switches application — and it left nowhere to click for the thing
      // you want far more often, which is to see what this session is actually doing.
      // The chip has carried the ↗ since it became clickable, so the affordance was
      // already pointing at the right place.
      .onTapGesture { tapJumps ? onJump?() : onToggle?() }
      .help(tapJumps ? plan.summary : (isOpen ? t("Close") : t("Open")))
      // Silencing from the card itself is the only entry point that costs nothing:
      // the session you want gone is the one you are already looking at.
      .contextMenu {
        if let cwd = session.cwd {
          Button(t("Hide sessions in %@", session.projectName ?? cwd)) {
            onSilence?(
              AdmissionRule(field: .directory, match: .contains, pattern: cwd))
          }
        }
        if let prompt = visiblePrompt {
          Button(t("Silence prompts starting with “%@…”", String(prompt.prefix(28)))) {
            onSilence?(
              AdmissionRule(
                field: .prompt, match: .prefix,
                pattern: String(prompt.prefix(28))))
          }
        }
      }
  }

  private var card: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 28) {
        AgentGlyph(
          agent: session.agent, pixel: 2,
          isBreathing: session.isWorking, isFighting: false)
          .frame(width: 20, alignment: .leading)
          .padding(.top, 2)

        VStack(alignment: .leading, spacing: 2) {
          headline

          if layout.showsPrompt, let turn = session.turn, !turn.isEmpty {
            conversationSummary(turn)
              .padding(.top, 3)
          } else if layout.showsPrompt, let prompt = visiblePrompt {
            Text(t("You: %@", prompt))
              .font(Theme.prose(contentFontSize + 1))
              .foregroundStyle(Theme.secondary)
              .lineLimit(1)
              .truncationMode(.tail)
              .padding(.top, 3)
          }

        // Vibe keeps the glanceable exchange above the expanded card. Opening a
        // session adds the readable transcript; it does not replace its summary.
          if isOpen, layout.showsPrompt, let turn = session.turn, !turn.isEmpty {
            TranscriptView(
              turn: turn,
              fallbackPrompt: visiblePrompt,
              isFinished: !session.isWorking
            )
            .padding(.top, 3)
            .padding(.bottom, 1)
          }

        // A finished expanded transcript carries "Done" in its own header, as in
        // Vibe. Repeating it under the card turns one state into a stray extra row.
          if showsActivityDetails,
            !(isOpen && session.status == .idle && session.turn?.isEmpty == false)
          {
            activityLine
          }

        // Vibe gives delegated work its own bounded card. Keeping the rows inside one
        // surface makes the parent/child relationship legible without widening the
        // island or turning every agent into another top-level session.
          if isOpen, layout.showsTasks, showsSubagents, !session.children.isEmpty {
            ChildAgentsSection(children: session.children, fontSize: contentFontSize)
              .padding(.top, 4)
          }
        }

        Spacer(minLength: 0)
      }

      if isOpen, layout.showsTasks, showsTasks, !tasks.isEmpty {
        TaskBoardView(board: tasks)
          .padding(.top, 10)
      }
    }
    .padding(.vertical, 6)
    .padding(.horizontal, 0)
    .background(
      RoundedRectangle(cornerRadius: Theme.cornerRadius)
        .fill(isFocused ? Theme.hairlineStrong : Color.clear)
    )
    .animation(.easeOut(duration: 0.12), value: isHovered)
    .animation(.easeOut(duration: 0.12), value: isFocused)
    // Only the rows below this one move, and they move once.
    .animation(.easeOut(duration: 0.16), value: isOpen)
  }

  private var headline: some View {
    HStack(spacing: 5) {
      SessionCardTitleParts(
        projectName: showsProjectName && session.projectName != session.title
          ? session.projectName : nil,
        worktreeDisplayLabel: showsWorktree ? visibleBranch : nil,
        hostWorkspaceDisplayName: session.client?.workspace,
        fontSize: contentFontSize
      ) {
        Text(session.title)
      }

      Spacer(minLength: 4)

      if session.subagents > 0 {
        TagPill(text: t("%lld agents", session.subagents), brandColor: Theme.info)
      }
      if session.agent == .codex {
        TagPill(text: "Codex", brandColor: Theme.info)
        if showsAIModel, let model = session.model,
          model.caseInsensitiveCompare("Codex") != .orderedSame
        {
          TagPill(text: model, brandColor: Theme.info)
        }
        if showsReasoningEffort, let effort = session.reasoningEffort {
          TagPill(text: effort)
        }
        TagPill(text: "ChatGPT")
        TagPill(text: age)
      }
      // Loudest chip on the row, and first, because it is the only one that says what
      // this agent is allowed to do to the machine without asking.
      if session.agent != .codex, let badge = session.permissionBadge {
        if session.permissionMode == "bypassPermissions" {
          BypassActivePill(
            sessionId: session.id,
            runtimeInstanceId: nil,
            showsExitButton: false,
            label: badge,
            axIdentifier: "session.bypass.\(session.id)",
            exitAction: {})
        } else {
          TagPill(
            text: badge,
            brandColor: session.permissionIsPermissive ? Theme.danger : Theme.info)
        }
      }
      if session.agent != .codex, showsAIModel {
        TagPill(text: session.agent.displayName, brandColor: agentTint)
      }
      if session.agent != .codex, let clientName = session.client?.displayName,
        clientName.caseInsensitiveCompare(session.agent.displayName) != .orderedSame
      {
        TagPill(text: clientName)
      }

      StateIndicator(status: session.status, isActive: isActive)

      if session.isCompletionUnread {
        CompletionUnreadDot()
      }

      if !isActive, onArchive != nil {
        ArchiveButton(action: { onArchive?() })
      }

      if session.agent != .codex, session.client?.displayName != nil {
        // Tinted while hovered: the chip is the thing that says where you land.
        //
        // The arrow is on it whenever a jump is possible, not only on hover. That
        // the card is clickable was discoverable by hovering it, which is to say by
        // already suspecting it — the affordance has to be visible before the
        // cursor arrives, or it is not an affordance.
        //
        // And it is a button now rather than a label, because the row it sits on
        // does something else.
        if allowsJump && plan.isPossible {
          JumpToTerminalPill(
            session: session,
            label: jumpLabel,
            action: { onJump?() })
        } else {
          TagPill(text: session.client?.displayName ?? "")
        }
      }

    }
  }

  @ViewBuilder
  private func conversationSummary(_ turn: TranscriptTurn) -> some View {
    if let prompt = displayableConversation(turn.prompt ?? visiblePrompt) {
      Text(t("You: %@", prompt))
        .font(Theme.prose(contentFontSize + 1))
        .foregroundStyle(Theme.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }
    if let reply = displayableConversation(turn.reply) {
      Text(reply)
        .font(Theme.prose(contentFontSize + 1))
        .foregroundStyle(Theme.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }
  }

  private func displayableConversation(_ text: String?) -> String? {
    guard let text else { return nil }
    let cleaned = SessionTracker.condense(text)
    guard !cleaned.isEmpty else { return nil }
    let lowercased = cleaned.lowercased()
    if lowercased.hasPrefix("code=")
      || lowercased.contains("get_app_state")
      || lowercased.contains("element_index")
      || lowercased.contains("noderepl")
      || lowercased.contains("sky.")
      || lowercased.contains("tools.")
    {
      return nil
    }
    return cleaned
  }

  /// What it is doing right now — the line that changes while you watch.
  @ViewBuilder
  private var activityLine: some View {
    if session.status == .compacting, let startedAt = session.compactingStartedAt {
      CompactingProgressLabel(startedAt: startedAt, fontSize: contentFontSize - 1)
    } else if session.status == .idle {
      CompletionCardView(session: session)
    } else if session.status == .failed {
      StatusWarningCardView(
        message: session.lastDetail.isEmpty ? t("Interrupted") : session.lastDetail)
    } else {
      let summary = displayableActivity(session.activitySummary.text)
      Text(
        summary.isEmpty
          ? (session.isWorking ? t("Working…") : t("Waiting"))
          : summary)
        .font(Theme.prose(contentFontSize))
        .foregroundStyle(session.activitySummary.tint)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }

  private func displayableActivity(_ text: String) -> String {
    let lowercased = text.lowercased()
    if lowercased.contains("get_app_state")
      || lowercased.contains("element_index")
      || lowercased.contains("noderepl")
      || lowercased.contains("sky.")
      || lowercased.contains("tools.")
    {
      return ""
    }
    return text
  }

  /// Coarse on purpose: a second-by-second counter on every card is noise, and the
  /// panel redraws often enough that it would never settle.
  private var age: String { Self.elapsed(since: session.startedAt) }

  private var visibleBranch: String? {
    guard let branch = session.gitBranch,
      branch.caseInsensitiveCompare("main") != .orderedSame,
      branch.caseInsensitiveCompare("master") != .orderedSame
    else { return nil }
    return branch
  }

  static func elapsed(since date: Date, now: Date = .now) -> String {
    let seconds = Int(now.timeIntervalSince(date))
    switch seconds {
    case ..<60: return "<1m"
    case ..<3_600: return "\(seconds / 60)m"
    case ..<86_400: return "\(seconds / 3_600)h"
    default: return "\(seconds / 86_400)d"
    }
  }
}

/// Vibe's compact child-agent group: one contained surface, live state at a glance, and
/// completed rows kept long enough to explain what happened in the current turn.
struct ChildAgentsSection: View {
  let children: [SubagentRun]
  var fontSize: Double = 11

  private let visibleLimit = 3
  private var visibleChildren: ArraySlice<SubagentRun> { children.prefix(visibleLimit) }
  private var hiddenChildren: ArraySlice<SubagentRun> { children.dropFirst(visibleLimit) }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 5) {
        Image(systemName: "point.3.connected.trianglepath.dotted")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(Theme.info)
        Text(t("Subagents (%lld)", children.count))
          .font(Theme.label(fontSize - 1, .semibold))
          .foregroundStyle(Theme.primary)
        Spacer(minLength: 8)
        if children.contains(where: { !$0.isCompleted }) {
          Text(t("%lld running", children.count(where: { !$0.isCompleted })))
            .font(Theme.mono(fontSize - 3))
            .foregroundStyle(Theme.info)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)

      Rectangle().fill(Theme.hairline).frame(height: 1)

      ForEach(visibleChildren) { child in
        ChildAgentRow(child: child, fontSize: fontSize)
        if child.id != visibleChildren.last?.id {
          Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 24)
        }
      }

      if !hiddenChildren.isEmpty {
        Rectangle().fill(Theme.hairline).frame(height: 1)
        let running = hiddenChildren.count(where: { !$0.isCompleted })
        let done = hiddenChildren.count(where: \.isCompleted)
        HStack(spacing: 6) {
          Image(systemName: "ellipsis")
          if running > 0 { Text(t("%lld running", running)) }
          if running > 0, done > 0 { Text("·") }
          if done > 0 { Text(t("%lld done", done)) }
          Spacer(minLength: 0)
        }
        .font(Theme.mono(fontSize - 3))
        .foregroundStyle(Theme.tertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.raised.opacity(0.82)))
    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 7))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("session.subagents")
  }
}

struct ChildAgentRow: View {
  let child: SubagentRun
  var fontSize: Double = 11

  private var tint: Color { child.isCompleted ? Theme.active : Theme.info }

  var body: some View {
    TimelineView(.periodic(from: child.startedAt, by: 1)) { context in
      HStack(spacing: 7) {
        Circle()
          .fill(tint)
          .frame(width: 6, height: 6)
          .overlay(Circle().stroke(tint.opacity(0.35), lineWidth: 3))
        Text(child.label)
          .font(Theme.mono(fontSize - 1, .medium))
          .foregroundStyle(Theme.primary)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 6)
        Text(child.isCompleted ? t("Done") : t("Running"))
          .font(Theme.mono(fontSize - 3))
          .foregroundStyle(tint)
        Text(Self.elapsed(child: child, now: context.date))
          .font(Theme.mono(fontSize - 3))
          .foregroundStyle(Theme.tertiary)
          .monospacedDigit()
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(child.label)
    .accessibilityValue(child.isCompleted ? t("Done") : t("Running"))
  }

  private static func elapsed(child: SubagentRun, now: Date) -> String {
    let end = child.completedAt ?? now
    return CompactingProgressLabel.elapsed(from: child.startedAt, to: end)
  }
}

/// The four-part title contract reflected by Vibe Island 1.0.44.
struct SessionCardTitleParts<SessionContent: View>: View {
  let projectName: String?
  let worktreeDisplayLabel: String?
  let hostWorkspaceDisplayName: String?
  let fontSize: Double
  let sessionContent: SessionContent

  init(
    projectName: String?, worktreeDisplayLabel: String?,
    hostWorkspaceDisplayName: String?, fontSize: Double,
    @ViewBuilder sessionContent: () -> SessionContent
  ) {
    self.projectName = projectName
    self.worktreeDisplayLabel = worktreeDisplayLabel
    self.hostWorkspaceDisplayName = hostWorkspaceDisplayName
    self.fontSize = fontSize
    self.sessionContent = sessionContent()
  }

  var body: some View {
    HStack(spacing: 4) {
      if let projectName, !projectName.isEmpty {
        Text(projectName)
          .layoutPriority(2)
      }
      if let worktreeDisplayLabel, !worktreeDisplayLabel.isEmpty,
        worktreeDisplayLabel != projectName
      {
        Text("⎇")
          .foregroundStyle(Theme.tertiary)
        Text(worktreeDisplayLabel)
          .foregroundStyle(Theme.secondary)
          .layoutPriority(1)
      }
      if let hostWorkspaceDisplayName, !hostWorkspaceDisplayName.isEmpty {
        Text("@")
          .foregroundStyle(Theme.tertiary)
        Text(hostWorkspaceDisplayName)
          .foregroundStyle(Theme.secondary)
          .layoutPriority(1)
      }
      if projectName != nil || worktreeDisplayLabel != nil || hostWorkspaceDisplayName != nil {
        Text("·")
          .foregroundStyle(Theme.tertiary)
      }
      sessionContent
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .font(Theme.label(fontSize + 2, .semibold))
    .foregroundStyle(Theme.primary)
    .lineLimit(1)
  }
}

struct CompactingProgressLabel: View {
  let startedAt: Date
  var fontSize: Double = 10

  var body: some View {
    TimelineView(.periodic(from: startedAt, by: 1)) { context in
      Text(t("Compacting · %@", Self.elapsed(from: startedAt, to: context.date)))
        .font(Theme.mono(fontSize))
        .foregroundStyle(Theme.warning)
        .monospacedDigit()
        .lineLimit(1)
    }
  }

  static func elapsed(from start: Date, to end: Date) -> String {
    let seconds = max(0, Int(end.timeIntervalSince(start)))
    if seconds < 60 { return "\(seconds)s" }
    return String(format: "%dm %02ds", seconds / 60, seconds % 60)
  }
}

/// A completed turn has its own quiet presentation in Vibe. It is deliberately a tag,
/// not another live activity line: completion is a stable result rather than an action
/// that is still moving.
struct CompletionCardView: View {
  let session: SessionSnapshot

  var body: some View {
    TagPill(
      text: t("Done"),
      opacity: session.status == .idle ? 1 : 0.6,
      backgroundOpacity: 0.1,
      brandColor: Theme.active)
      .accessibilityIdentifier("session.completion.\(session.id)")
  }
}

/// Failed or interrupted sessions are a warning surface, not a normal activity summary.
struct StatusWarningCardView: View {
  let message: String

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(Theme.warning)
      Text(t("Needs attention"))
        .font(Theme.mono(9, .medium))
        .foregroundStyle(Theme.warning)
      if !message.isEmpty {
        Text("·")
          .foregroundStyle(Theme.tertiary)
        Text(message)
          .font(Theme.mono(9))
          .foregroundStyle(Theme.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("session.statusWarning")
  }
}

/// Vibe's explicit completed-session removal, visible as a quiet icon until hovered.
struct ArchiveButton: View {
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: "archivebox")
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(isHovered ? Theme.primary : Theme.tertiary)
        .frame(width: 14, height: 14)
        .background(Circle().fill(Color.white.opacity(isHovered ? 0.1 : 0)))
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help(t("Archive session"))
    .accessibilityLabel(t("Archive session"))
  }
}

extension SessionSnapshot {
  /// What this session is doing right now, and how to feel about it.
  ///
  /// One place, because two views draw it: the card in the panel and the row in the
  /// peek. A hover that says "Bash(swift build)" over a panel that says "Waiting for
  /// your approval" is two answers to one question.
  var activitySummary: (text: String, tint: Color) {
    switch status {
    case .compacting: return (t("Compacting context…"), Theme.warning)
    // Not "waiting for you": every turn ends, and a row that announces the end of
    // each one as though it were owed something turns the panel into a to-do list of
    // things already finished.
    case .idle: return (t("Done"), Theme.tertiary)
    case .failed:
      return (lastDetail.isEmpty ? t("Ended on a failure") : lastDetail, Theme.danger)
    case .needsApproval: return (t("Waiting for your approval"), Theme.warning)
    case .waitingForAnswer: return (t("Waiting for your answer"), Theme.warning)
    case .working, .runningTool:
      // The same line either way: what it is doing is the command, and the dot
      // beside it already says whether a tool is in flight.
      return (lastDetail, Theme.info)
    case .background:
      // The turn is over and the terminal has gone quiet, which is precisely when
      // the line has to say what is still running — name it when there is one thing,
      // count them when there are several.
      return (backgroundSummary, Theme.info)
    }
  }

  /// "yoda", or "2 agents", or "1 agent, 1 command" — whichever is true.
  var backgroundSummary: String {
    let agents = background.filter(\.isSubagent)
    let shells = background.filter { !$0.isSubagent }
    if background.count == 1, let only = background.first {
      return t("%@ is still running", only.displayName)
    }
    var parts: [String] = []
    if !agents.isEmpty { parts.append(t("%lld agents", agents.count)) }
    if !shells.isEmpty { parts.append(t("%lld commands", shells.count)) }
    // Only reachable for a CLI that says something is running without saying what.
    if parts.isEmpty { return t("Still running") }
    return t("%@ still running", parts.joined(separator: ", "))
  }
}

struct StateIndicator: View {
  let status: SessionStatus
  let isActive: Bool
  @State private var isPulsing = false

  private var tint: Color {
    switch status {
    case .working, .runningTool: return Theme.active
    // Everything that is blocked on a person shares one colour. Which flavour of
    // waiting it is belongs on the line; the dot answers "does this need me".
    case .needsApproval, .waitingForAnswer: return Theme.warning
    case .compacting: return Theme.warning
    case .idle: return Theme.tertiary
    case .failed: return Theme.danger
    // The same colour as working, because it is: nobody is blocked, something is
    // running. What differs is that no one is in front of it.
    case .background: return Theme.active
    }
  }

  /// Pulses while something is happening on its own. A session waiting on you is not
  /// live — it is stopped, and a heartbeat would say the opposite.
  var body: some View {
    Circle()
      .fill(tint)
      .frame(width: 6, height: 6)
      .opacity(isActive && isPulsing ? 0.35 : 1)
      .animation(
        isActive
          ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
          : .default,
        value: isPulsing
      )
      .onAppear { isPulsing = true }
  }
}

/// A turn completed while the panel was closed and has not been read yet.
struct CompletionUnreadDot: View {
  var body: some View {
    Circle()
      .fill(Theme.info)
      .frame(width: 6, height: 6)
      .overlay {
        Circle().stroke(Color.white.opacity(0.65), lineWidth: 0.75)
      }
      .accessibilityLabel(t("Unread completion"))
  }
}

/// Vibe's configurable capsule contract. Keeping the colour and opacity as inputs lets
/// status, provider and metadata tags share one geometry without sharing one meaning.
struct TagPill: View {
  let text: String
  var opacity: Double = 1
  var backgroundOpacity: Double = 0.12
  var brandColor: Color? = nil
  var minWidth: CGFloat? = nil
  var trailingIcon: String? = nil
  var onTap: (() -> Void)? = nil

  @ViewBuilder
  private var label: some View {
    HStack(spacing: 3) {
      Text(text)
      if let trailingIcon {
        Image(systemName: trailingIcon)
          .font(.system(size: 7, weight: .semibold))
      }
    }
    .font(Theme.label(10.5, .medium))
    .foregroundStyle(brandColor ?? Theme.secondary)
    .padding(.horizontal, 4)
    .padding(.vertical, 1.5)
    .frame(minWidth: minWidth)
    .background(
      RoundedRectangle(cornerRadius: 4)
        .fill((brandColor ?? Color.white).opacity(backgroundOpacity))
    )
    .opacity(opacity)
    .fixedSize()
  }

  var body: some View {
    if let onTap {
      Button(action: onTap) { label }
        .buttonStyle(.plain)
    } else {
      label
    }
  }
}

/// The terminal affordance is its own control in Vibe rather than an inert metadata tag.
struct JumpToTerminalPill: View {
  let session: SessionSnapshot
  var label = "⌃G ↗"
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      TagPill(
        text: label,
        backgroundOpacity: isHovered ? 0.2 : 0.12,
        brandColor: Theme.info)
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help(TerminalJump.plan(for: session.client).summary)
    .accessibilityIdentifier("session.jump.\(session.id)")
  }
}

/// A permissive session is not ordinary metadata: the red pill stays explicit and owns
/// the optional exit action used by runtimes that can be returned to a guarded mode.
struct BypassActivePill: View {
  let sessionId: String
  let runtimeInstanceId: String?
  let showsExitButton: Bool
  let label: String
  let axIdentifier: String
  let exitAction: () -> Void

  var body: some View {
    TagPill(
      text: label,
      brandColor: Theme.danger,
      trailingIcon: showsExitButton ? "xmark" : nil,
      onTap: showsExitButton ? exitAction : nil)
      .accessibilityIdentifier(axIdentifier)
      .accessibilityValue(runtimeInstanceId ?? sessionId)
  }
}

/// Compatibility for panel surfaces that have not yet adopted the reflected tag contract.
struct Chip: View {
  let text: String
  let tint: Color?

  var body: some View {
    TagPill(text: text, brandColor: tint)
  }
}
