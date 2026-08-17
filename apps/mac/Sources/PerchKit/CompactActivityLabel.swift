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

  private static func isToolIdentifier(_ value: String) -> Bool {
    !value.isEmpty
      && value.unicodeScalars.allSatisfy {
        CharacterSet.alphanumerics.contains($0) || "_.-".unicodeScalars.contains($0)
      }
  }
}
