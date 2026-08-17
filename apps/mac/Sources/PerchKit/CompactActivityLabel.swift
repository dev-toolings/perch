import Foundation

/// Turns a card's detailed activity into the one short tool label that fits in the
/// collapsed island. Prose and command arguments stay in the expanded panel.
public enum CompactActivityLabel {
  public static func name(from detail: String) -> String? {
    let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    // Computer Use records its JavaScript as `code=...`; Vibe groups this under the
    // generic execution activity instead of leaking source into the menu bar.
    if trimmed.hasPrefix("code=") { return "exec" }

    if let separator = trimmed.range(of: ": ") {
      let candidate = String(trimmed[..<separator.lowerBound])
      if isToolIdentifier(candidate) { return candidate }
    }

    guard trimmed.count <= 24, isToolIdentifier(trimmed) else { return nil }
    return trimmed
  }

  /// The one line the collapsed island shows for work in flight: `Bash: swift test`,
  /// `Read: ~/lab/x.swift`, `exec: swift test`. Vibe's pill carries the arguments as
  /// well as the tool and lets the width cut them; so does this — the strip truncates
  /// with an ellipsis, and a bare `Bash` for a running command says less than the
  /// command does.
  ///
  /// Nil when nothing names the work: prose, a command whose tool was never recorded.
  /// The strip then falls back to the session's title rather than showing a line of
  /// shell with nothing to say what it belongs to.
  public static func line(tool: String?, detail: String) -> String? {
    let arguments = firstLine(of: detail)
    if let tool, isToolIdentifier(tool) {
      return arguments.isEmpty ? tool : "\(tool): \(arguments)"
    }
    // A detail that already reads `exec: swift test` — Codex's rollout reader writes
    // them that way — is a line as it stands.
    guard name(from: arguments) != nil else { return nil }
    return arguments
  }

  /// The first non-empty line, whitespace collapsed, and no longer than a strip could
  /// ever draw: a pasted script must not become a kilobyte of `Text` in the menu bar.
  static func firstLine(of detail: String, limit: Int = 80) -> String {
    let line =
      detail.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .first { !$0.isEmpty } ?? ""
    let collapsed = line.split(separator: " ", omittingEmptySubsequences: true)
      .joined(separator: " ")
    guard collapsed.count > limit else { return collapsed }
    return String(collapsed.prefix(limit)) + "…"
  }

  private static func isToolIdentifier(_ value: String) -> Bool {
    !value.isEmpty
      && value.unicodeScalars.allSatisfy {
        CharacterSet.alphanumerics.contains($0) || "_.-".unicodeScalars.contains($0)
      }
  }
}
