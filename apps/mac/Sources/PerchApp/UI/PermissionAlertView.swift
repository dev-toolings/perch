import PerchKit
import SwiftUI

/// The permission prompt, in the notch.
///
/// A Claude Code session is blocked while this is on screen, so it has to answer three
/// questions at a glance: which tool, doing what, in which project.
struct PermissionAlertView: View {
    let pending: PendingPermission
    let waitingCount: Int
    /// The destination names how far a grant reaches: `nil` this turn, `.session` this
    /// conversation, `.localSettings` always. Deny/ask always pass `nil`.
    let decide: (PermissionDecision, RememberedRule.Destination?) -> Void
    var decideAll: ((PermissionDecision) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            command
            buttons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)

            // Project and queue depth are in the band beside the cutout: they are the same
            // two facts on every card, and they were crowding the one line that is not.
            Text(pending.tool)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)

            // The change in one glance: `+3 -1` next to the tool name, the diff below.
            if let diff = pending.diff {
                Text(diff.badge)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 0)
        }
    }

    private var command: some View {
        // An Edit or a Write carries its change in the payload: showing the diff is the
        // difference between approving a change and approving a label. Anything else keeps
        // the one-line summary.
        if let diff = pending.diff {
            AnyView(diffBlock(diff))
        } else {
            AnyView(
                Text(pending.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.07)))
            )
        }
    }

    /// The card is an approval prompt, not a code review surface: eight lines is enough to
    /// recognise the change, and the count says how much more there is.
    private static let maxDiffRows = 8

    private func diffBlock(_ diff: ToolDiff) -> some View {
        let rows = Array(diff.lines.prefix(Self.maxDiffRows))
        let remaining = diff.lines.count - rows.count
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 0) {
                    Text(line.number > 0 ? String(line.number) : "")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 26, alignment: .trailing)
                        .padding(.trailing, 6)
                    Text(marker(for: line.kind))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(tint(for: line.kind))
                        .frame(width: 10)
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(
                            line.kind == .context ? .white.opacity(0.65) : tint(for: line.kind))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 1)
                .padding(.trailing, 6)
                .background(background(for: line.kind))
            }
            if remaining > 0 {
                Text(t("%lld more lines", remaining))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.leading, 42)
                    .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.05)))
    }

    private func marker(for kind: ToolDiff.Kind) -> String {
        switch kind {
        case .context: return " "
        case .deleted: return "-"
        case .added: return "+"
        }
    }

    private func tint(for kind: ToolDiff.Kind) -> Color {
        switch kind {
        case .context: return .white.opacity(0.65)
        case .deleted: return Theme.danger
        case .added: return Theme.active
        }
    }

    private func background(for kind: ToolDiff.Kind) -> Color {
        switch kind {
        case .context: return .clear
        case .deleted: return Theme.danger.opacity(0.12)
        case .added: return Theme.active.opacity(0.10)
        }
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            AlertButton(title: "Allow", tint: .green, shortcut: "⌥↵") {
                decide(.allow, nil)
            }

            // Only offered when we can express a rule the user can read and audit. Two
            // scopes: the grant that lasts as long as this chat, and the one written down
            // for good. Both show the exact rule so nobody grants more than they meant to.
            if let rule = PermissionRule.rule(for: pending.request) {
                AlertButton(title: "This chat", tint: .green.opacity(0.6), shortcut: nil) {
                    decide(.allow, .session)
                }
                .help("Allows \(rule) for the rest of this conversation")

                AlertButton(title: "Always", tint: .green.opacity(0.6), shortcut: nil) {
                    decide(.allow, .localSettings)
                }
                .help("Adds \(rule) to this project's .claude/settings.local.json")
            }

            AlertButton(title: "Deny", tint: .red, shortcut: "⌥⌫") {
                decide(.deny, nil)
            }

            Spacer(minLength: 0)

            // Only when there is a queue, and only allow/deny: writing an "Always" rule
            // for requests you have not read is how a permission system stops meaning
            // anything.
            if waitingCount > 1, let decideAll {
                Button(t("Allow all %lld", waitingCount)) { decideAll(.allow) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.active.opacity(0.8))
                Button(t("Deny all")) { decideAll(.deny) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.danger.opacity(0.8))
            }

            Button(t("Ask in terminal")) { decide(.ask, nil) }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

private struct AlertButton: View {
    let title: String
    let tint: Color
    let shortcut: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(tint.opacity(isHovering ? 0.45 : 0.25))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
