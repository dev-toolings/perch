import PerchKit
import SwiftUI

/// A session's plan, under its card.
///
/// The tool feed answers "what did it just do" and the card's activity line answers "what
/// is it doing"; neither answers "how far through is it", which is the question you have
/// when you glance at a machine that has been working for twenty minutes without you.
///
/// Ordered the way it is read rather than the way it is stored — what is happening, then
/// what is next. Completed tasks leave the island immediately; their count remains in the
/// header without letting old work push the next step off the card.
struct TaskBoardView: View {
  let board: TaskBoard

  /// Three concrete rows plus one overflow line, matching the bounded Vibe card.
  private let visibleRows = 3

  private var shown: [AgentTask] { Array(board.tasks.prefix(visibleRows)) }
  private var hidden: [AgentTask] { Array(board.tasks.dropFirst(visibleRows)) }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 4) {
        Text(t("Tasks"))
          .font(Theme.label(12, .semibold))
          .foregroundStyle(Theme.secondary)
        Text("(\(headlineCounts))")
          .font(Theme.label(11.5))
          .foregroundStyle(Theme.tertiary)
      }
      .lineLimit(1)
      .frame(height: 22)

      ForEach(shown) { task in
        TaskRow(task: task)
      }

      if !hidden.isEmpty {
        Text(overflow)
          .font(Theme.label(11.5))
          .foregroundStyle(Theme.tertiary)
          // Aligned with the subjects above, not with the marks.
          .padding(.leading, 17)
          .frame(height: 22)
      }
    }
    .padding(.vertical, 6)
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.03)))
  }

  /// Counts, not a progress bar: "3 done, 1 running, 3 open" says which of the three
  /// numbers moved since you last looked, and a bar does not.
  private var headlineCounts: String {
    let parts = [
      t("%lld done", board.completed),
      t("%lld running", board.inProgress),
      t("%lld open", board.open),
    ]
    return parts.joined(separator: ", ")
  }

  private var overflow: String {
    t("… +%lld active", hidden.count)
  }
}

private struct TaskRow: View {
  let task: AgentTask

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: mark)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 11)

      Text(task.subject)
        .font(Theme.label(12.5, task.status == .inProgress ? .medium : .regular))
        .foregroundStyle(text)
        .strikethrough(task.status == .completed, color: Theme.tertiary)
        .lineLimit(1)
        .truncationMode(.tail)

      Spacer(minLength: 0)
    }
    .frame(height: 22)
  }

  private var mark: String {
    switch task.status {
    case .inProgress: return "circle.fill"
    case .pending: return "square"
    case .completed: return "checkmark.square.fill"
    }
  }

  private var tint: Color {
    switch task.status {
    case .inProgress: return Theme.info
    case .pending: return Theme.tertiary
    case .completed: return Theme.tertiary
    }
  }

  /// The running step is the one you are looking for, so it is the only one at full
  /// contrast.
  private var text: Color {
    switch task.status {
    case .inProgress: return Theme.primary
    case .pending: return Theme.primary.opacity(0.85)
    case .completed: return Theme.tertiary
    }
  }
}
