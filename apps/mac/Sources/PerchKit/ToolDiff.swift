import Foundation

/// A line-level diff of what a file-editing tool call is about to change, built from the
/// hook's `tool_input`.
///
/// Approving an `Edit` you cannot read is voting blind: the one fact the decision needs —
/// what actually changes — was sitting in the payload the whole time. This turns
/// `old_string`/`new_string` (or a `Write`'s content) into numbered, coloured lines,
/// fragment-relative: an Edit hunk does not know where in the file it lands, and a line
/// number invented to look absolute would be a guess presented as a fact.
public struct ToolDiff: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case context
        case deleted
        case added
    }

    public struct Line: Sendable, Equatable {
        public let kind: Kind
        public let text: String
        /// The line number within the fragment — old side for deletions, new side for
        /// additions and context. A gutter can only ever show one number per line.
        public let number: Int
    }

    public let filePath: String
    public let lines: [Line]
    public let additions: Int
    public let deletions: Int

    /// The summary chip, `+3 -1` style.
    public var badge: String { "+\(additions) -\(deletions)" }

    /// Builds a diff for the tools whose input is a change to a file: `Edit`,
    /// `MultiEdit`, `Write`, `NotebookEdit`. Anything else returns nil and the caller
    /// keeps the one-line summary it already had.
    public static func build(toolName: String?, toolInput: JSONValue?) -> ToolDiff? {
        guard let toolName, let toolInput else { return nil }

        switch toolName {
        case "Edit", "NotebookEdit":
            guard let path = toolInput["file_path"]?.stringValue
                    ?? toolInput["notebook_path"]?.stringValue,
                let old = toolInput["old_string"]?.stringValue,
                let new = toolInput["new_string"]?.stringValue
            else { return nil }
            return make(filePath: path, old: old, new: new)

        case "MultiEdit":
            guard let path = toolInput["file_path"]?.stringValue,
                case .array(let edits)? = toolInput["edits"]
            else { return nil }
            // The hunks are concatenated with an ellipsis between them: each edit carries
            // its own fragment, and fusing them into one line-numbered block would imply
            // an adjacency nobody promised.
            var lines: [Line] = []
            var additions = 0
            var deletions = 0
            for (index, edit) in edits.enumerated() {
                guard let old = edit["old_string"]?.stringValue,
                    let new = edit["new_string"]?.stringValue
                else { continue }
                if index > 0 {
                    lines.append(Line(kind: .context, text: "…", number: 0))
                }
                let hunk = make(filePath: path, old: old, new: new)
                lines.append(contentsOf: hunk.lines)
                additions += hunk.additions
                deletions += hunk.deletions
            }
            guard !lines.isEmpty else { return nil }
            return ToolDiff(
                filePath: path, lines: lines, additions: additions, deletions: deletions)

        case "Write":
            guard let path = toolInput["file_path"]?.stringValue,
                let content = toolInput["content"]?.stringValue
            else { return nil }
            let added = content.split(separator: "\n", omittingEmptySubsequences: false)
            // A new file is all additions; a trailing newline is not a line.
            let rows = added.last == "" ? added.dropLast() : added
            guard !rows.isEmpty else { return nil }
            return ToolDiff(
                filePath: path,
                lines: rows.enumerated().map {
                    Line(kind: .added, text: String($0.element), number: $0.offset + 1)
                },
                additions: rows.count, deletions: 0)

        default:
            return nil
        }
    }

    /// Lines are diffed with a plain LCS dynamic program. The inputs are Edit fragments,
    /// not files — anything past a few hundred lines a side is a pathological payload,
    /// and the caller falls back to the summary line rather than pay for it.
    private static let maxCells = 250_000

    private static func make(filePath: String, old: String, new: String) -> ToolDiff {
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        guard oldLines.count * newLines.count <= maxCells else {
            return ToolDiff(
                filePath: filePath, lines: [],
                additions: newLines.count, deletions: oldLines.count)
        }

        // LCS table, then walk it back into aligned rows.
        let n = oldLines.count
        let m = newLines.count
        var table = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] =
                    oldLines[i] == newLines[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }

        var lines: [Line] = []
        var additions = 0
        var deletions = 0
        var i = 0
        var j = 0
        while i < n, j < m {
            if oldLines[i] == newLines[j] {
                lines.append(Line(kind: .context, text: newLines[j], number: j + 1))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                lines.append(Line(kind: .deleted, text: oldLines[i], number: i + 1))
                deletions += 1
                i += 1
            } else {
                lines.append(Line(kind: .added, text: newLines[j], number: j + 1))
                additions += 1
                j += 1
            }
        }
        while i < n {
            lines.append(Line(kind: .deleted, text: oldLines[i], number: i + 1))
            deletions += 1
            i += 1
        }
        while j < m {
            lines.append(Line(kind: .added, text: newLines[j], number: j + 1))
            additions += 1
            j += 1
        }

        // Context is trimmed to two lines around each island of change — the card is an
        // approval prompt, not a code review surface.
        let trimmed = trimContext(lines, keeping: 2)
        return ToolDiff(
            filePath: filePath, lines: trimmed, additions: additions, deletions: deletions)
    }

    private static func trimContext(_ lines: [Line], keeping keep: Int) -> [Line] {
        var isChange = lines.map { $0.kind != .context }
        // Mark context within `keep` of a change as worth keeping. The counter saturates
        // at keep + 1: anything further is elided either way, and counting to Int.max is
        // an overflow trap.
        var keepContext = [Bool](repeating: false, count: lines.count)
        var distance = keep + 1
        for index in lines.indices {
            distance = isChange[index] ? 0 : min(distance + 1, keep + 1)
            if distance <= keep { keepContext[index] = true }
        }
        distance = keep + 1
        for index in lines.indices.reversed() {
            distance = isChange[index] ? 0 : min(distance + 1, keep + 1)
            if distance <= keep { keepContext[index] = true }
        }

        var result: [Line] = []
        var elided = false
        for (index, line) in lines.enumerated() {
            if line.kind != .context || keepContext[index] {
                result.append(line)
                elided = false
            } else if !elided {
                result.append(Line(kind: .context, text: "…", number: 0))
                elided = true
            }
        }
        return result
    }
}
