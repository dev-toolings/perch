import Foundation

/// Builds the Claude-compatible hook configuration used by Claude Code, Codex and Droid.
///
/// This lives in the shipped binary instead of a `jq` script: a Mac that installed Perch
/// from a DMG is not expected to have Homebrew utilities available. Existing third-party
/// hooks are preserved and only entries invoking `perch-hook` are replaced.
public enum HookConfiguration {
    public enum Failure: Error, LocalizedError, Equatable {
        case invalidRoot
        case invalidHooks
        case invalidEvent(String)
        case conflictingTOMLHooks
        case invalidManagedTOMLBlock
        case invalidTOMLString
        case unreadable(String)
        case unwritable(String)

        public var errorDescription: String? {
            switch self {
            case .invalidRoot:
                return "The agent configuration must contain a JSON object at its root."
            case .invalidHooks:
                return "The agent configuration has a hooks value that is not a JSON object."
            case .invalidEvent(let event):
                return "The hook list for \(event) is not a JSON array."
            case .conflictingTOMLHooks:
                return "The agent configuration uses a root hooks = value that conflicts with its TOML hook tables. Convert it to the documented hook-table format before installing Perch."
            case .invalidManagedTOMLBlock:
                return "The Perch-managed TOML hook block is incomplete. Restore the configuration backup before reinstalling."
            case .invalidTOMLString:
                return "The hook path or source contains a character that cannot be written safely to TOML."
            case .unreadable(let path):
                return "Perch could not read the agent configuration at \(path)."
            case .unwritable(let path):
                return "Perch could not write the agent configuration at \(path)."
            }
        }
    }

    public struct Event: Sendable, Equatable {
        public var name: String
        public var commandName: String
        public var timeout: Int

        public init(_ name: String, command: String? = nil, timeout: Int = 5) {
            self.name = name
            self.commandName = command ?? name
            self.timeout = timeout
        }
    }

    public static let claudeEvents: [Event] = [
        Event("PermissionRequest", timeout: 86_400),
        Event("PreToolUse"), Event("PostToolUse"), Event("PostToolUseFailure"),
        Event("PermissionDenied"), Event("Notification"), Event("UserPromptSubmit"),
        Event("Stop"), Event("StopFailure"), Event("SubagentStart"),
        Event("SubagentStop"), Event("PreCompact"), Event("SessionStart"),
        Event("SessionEnd", timeout: 3),
    ]

    public static let cursorEvents: [(cursor: String, perch: String)] = [
        ("beforeSubmitPrompt", "UserPromptSubmit"),
        ("beforeShellExecution", "PreToolUse"),
        ("beforeMCPExecution", "PreToolUse"),
        ("beforeReadFile", "PreToolUse"),
        ("afterShellExecution", "PostToolUse"),
        ("afterMCPExecution", "PostToolUse"),
        ("afterFileEdit", "PostToolUse"),
        ("afterAgentThought", "PostToolUse"),
        ("afterAgentResponse", "PostToolUse"),
        ("stop", "Stop"),
        ("subagentStart", "SubagentStart"),
        ("subagentStop", "SubagentStop"),
        ("sessionStart", "SessionStart"),
        ("sessionEnd", "SessionEnd"),
    ]

    public static let geminiEvents: [Event] = [
        Event("BeforeAgent", command: "UserPromptSubmit", timeout: 5_000),
        Event("BeforeTool", command: "PreToolUse", timeout: 5_000),
        Event("AfterTool", command: "PostToolUse", timeout: 5_000),
        Event("AfterAgent", command: "Stop", timeout: 5_000),
        Event("Notification", timeout: 5_000),
        Event("SessionStart", timeout: 5_000),
        Event("SessionEnd", timeout: 5_000),
    ]

    /// Kimi and Kimi Code use Claude's event names but a flat TOML `[[hooks]]` array.
    /// `PermissionRequest` is observation-only in Kimi: the hook records the wait while
    /// Kimi's own prompt remains the authority that answers it.
    public static let kimiEvents: [Event] = [
        Event("UserPromptSubmit"), Event("PreToolUse"), Event("PostToolUse"),
        Event("PostToolUseFailure"), Event("PermissionRequest"), Event("Notification"),
        Event("Stop"), Event("StopFailure"), Event("SubagentStart"),
        Event("SubagentStop"), Event("PreCompact"), Event("SessionStart"),
        Event("SessionEnd"),
    ]

    private static let kimiBlockStart =
        "# --- perch Kimi hooks START (managed, do not edit) ---"
    private static let kimiBlockEnd = "# --- perch Kimi hooks END ---"

    /// Mistral Vibe's stable hook surface has three lifecycle types. The argv event keeps
    /// Perch's one event model while the native `type` keeps Vibe's own configuration valid.
    public static let mistralVibeEvents: [Event] = [
        Event("pre_tool", command: "PreToolUse"),
        Event("post_tool", command: "PostToolUse"),
        Event("post_agent", command: "Stop"),
    ]

    private static let mistralVibeBlockStart =
        "# --- perch Mistral Vibe hooks START (managed, do not edit) ---"
    private static let mistralVibeBlockEnd = "# --- perch Mistral Vibe hooks END ---"

    /// DeepSeek TUI uses named entries nested below `[hooks]`. Its hooks are observers:
    /// Perch records lifecycle state but never writes a steering response to stdout.
    public static let deepSeekEvents: [Event] = [
        Event("session_start", command: "SessionStart"),
        Event("session_end", command: "SessionEnd"),
        Event("message_submit", command: "UserPromptSubmit"),
        Event("tool_call_before", command: "PreToolUse"),
        Event("tool_call_after", command: "PostToolUse"),
        Event("on_error", command: "PostToolUseFailure"),
        Event("turn_end", command: "Stop"),
        Event("subagent_spawn", command: "SubagentStart"),
        Event("subagent_complete", command: "SubagentStop"),
    ]

    private static let deepSeekBlockStart =
        "# --- perch DeepSeek hooks START (managed, do not edit) ---"
    private static let deepSeekBlockEnd = "# --- perch DeepSeek hooks END ---"

    public static let antigravityEvents: [Event] = [
        Event("PreToolUse"), Event("PostToolUse"), Event("Stop"),
    ]

    public static let copilotEvents: [Event] = [
        Event("SessionStart"), Event("SessionEnd"), Event("UserPromptSubmit"),
        Event("PreToolUse"), Event("PostToolUse"), Event("PostToolUseFailure"),
        Event("PermissionRequest"), Event("Notification"), Event("Stop"),
        Event("SubagentStart"), Event("SubagentStop"), Event("PreCompact"),
        Event("ErrorOccurred", command: "StopFailure"),
    ]

    /// Returns a stable, human-readable JSON file and never mutates the input object.
    public static func merged(
        data: Data, hookBinary: String, source: String,
        events: [Event] = claudeEvents
    ) throws -> Data {
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard var root = decoded as? [String: Any] else { throw Failure.invalidRoot }

        var hooks: [String: Any]
        if let existing = root["hooks"] {
            guard let object = existing as? [String: Any] else { throw Failure.invalidHooks }
            hooks = object
        } else {
            hooks = [:]
        }

        for key in hooks.keys.sorted() {
            guard let groups = hooks[key] as? [[String: Any]] else {
                throw Failure.invalidEvent(key)
            }
            let cleaned = groups.compactMap(removePerchEntries)
            if cleaned.isEmpty { hooks.removeValue(forKey: key) } else { hooks[key] = cleaned }
        }

        for event in events {
            var groups = hooks[event.name] as? [[String: Any]] ?? []
            groups.append([
                "hooks": [[
                    "type": "command",
                    "command": "\(hookBinary) \(event.commandName) --source \(source)",
                    "timeout": event.timeout,
                ]]
            ])
            hooks[event.name] = groups
        }

        root["hooks"] = hooks
        return try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Writes a timestamp-independent backup before replacing an existing file.
    public static func install(
        at url: URL, hookBinary: String, source: String,
        events: [Event] = claudeEvents
    ) throws {
        let manager = FileManager.default
        let existed = manager.fileExists(atPath: url.path)
        let existing: Data
        if existed {
            guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable(url.path) }
            existing = data
        } else {
            existing = Data("{}".utf8)
        }

        let output = try merged(
            data: existing, hookBinary: hookBinary, source: source, events: events)
        guard output != existing else { return }
        if existed {
            let backup = URL(fileURLWithPath: url.path + ".perch-backup")
            if !manager.fileExists(atPath: backup.path) {
                do { try existing.write(to: backup, options: .atomic) }
                catch { throw Failure.unwritable(backup.path) }
            }
        }
        do {
            try manager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try output.write(to: url, options: .atomic)
        } catch {
            throw Failure.unwritable(url.path)
        }
    }

    /// Cursor stores direct command rows rather than Claude-style nested hook groups.
    public static func mergedCursor(data: Data, hookBinary: String) throws -> Data {
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard var root = decoded as? [String: Any] else { throw Failure.invalidRoot }
        var hooks: [String: Any]
        if let existing = root["hooks"] {
            guard let object = existing as? [String: Any] else { throw Failure.invalidHooks }
            hooks = object
        } else {
            hooks = [:]
        }

        for mapping in cursorEvents {
            let current = hooks[mapping.cursor]
            guard current == nil || current is [[String: Any]] else {
                throw Failure.invalidEvent(mapping.cursor)
            }
            var entries = (current as? [[String: Any]] ?? []).filter { entry in
                guard let command = entry["command"] as? String else { return true }
                return !command.contains("perch-hook")
            }
            entries.append([
                "command": "\(hookBinary) \(mapping.perch) --source cursor"
            ])
            hooks[mapping.cursor] = entries
        }

        root["version"] = root["version"] ?? 1
        root["hooks"] = hooks
        return try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    public static func installCursor(at url: URL, hookBinary: String) throws {
        try installFile(at: url) { data in
            try mergedCursor(data: data, hookBinary: hookBinary)
        }
    }

    /// Merges a complete, delimited hook block into Kimi's TOML without parsing or
    /// rewriting the user's provider/model configuration.
    ///
    /// Kimi officially permits only `event`, `matcher`, `command`, and `timeout` in each
    /// hook table. Perch emits the three fields it needs and owns only the delimited block.
    public static func mergedKimiTOML(
        data: Data, hookBinary: String, source: String,
        events: [Event] = kimiEvents
    ) throws -> Data {
        guard var text = String(data: data, encoding: .utf8) else {
            throw Failure.invalidTOMLString
        }
        text = try removingManagedTOMLBlock(
            from: text, startMarker: kimiBlockStart, endMarker: kimiBlockEnd)
        try rejectRootHooksArray(in: text)

        _ = try quotedTOML(hookBinary)
        _ = try quotedTOML(source)
        var block = [kimiBlockStart]
        for event in events {
            let name = try quotedTOML(event.name)
            block.append(
                """
                [[hooks]]
                event = \(name)
                command = \(try quotedTOML("\(hookBinary) \(event.commandName) --source \(source)"))
                timeout = \(event.timeout)
                """)
        }
        block.append(kimiBlockEnd)

        let base = text.trimmingCharacters(in: .newlines)
        let merged = base.isEmpty
            ? block.joined(separator: "\n") + "\n"
            : base + "\n\n" + block.joined(separator: "\n") + "\n"
        return Data(merged.utf8)
    }

    public static func installKimiTOML(
        at url: URL, hookBinary: String, source: String
    ) throws {
        try installFile(at: url, emptyData: Data()) { data in
            try mergedKimiTOML(data: data, hookBinary: hookBinary, source: source)
        }
    }

    /// Merges Perch into Mistral Vibe's dedicated `hooks.toml` using named native hooks.
    /// Foreign hook tables stay byte-for-byte intact outside Perch's delimited block.
    public static func mergedMistralVibeTOML(
        data: Data, hookBinary: String,
        events: [Event] = mistralVibeEvents
    ) throws -> Data {
        guard var text = String(data: data, encoding: .utf8) else {
            throw Failure.invalidTOMLString
        }
        text = try removingManagedTOMLBlock(
            from: text, startMarker: mistralVibeBlockStart,
            endMarker: mistralVibeBlockEnd)
        _ = try quotedTOML(hookBinary)

        var block = [mistralVibeBlockStart]
        for event in events {
            let slug = event.name.replacingOccurrences(of: "_", with: "-")
            block.append(
                """
                [[hooks]]
                name = \(try quotedTOML("perch-\(slug)"))
                type = \(try quotedTOML(event.name))
                command = \(try quotedTOML("\(hookBinary) \(event.commandName) --source mistralvibe"))
                timeout = \(event.timeout).0
                strict = false
                description = "Send lifecycle state to Perch."
                """)
        }
        block.append(mistralVibeBlockEnd)

        let base = text.trimmingCharacters(in: .newlines)
        let merged = base.isEmpty
            ? block.joined(separator: "\n") + "\n"
            : base + "\n\n" + block.joined(separator: "\n") + "\n"
        return Data(merged.utf8)
    }

    public static func installMistralVibeTOML(
        at url: URL, hookBinary: String
    ) throws {
        try installFile(at: url, emptyData: Data()) { data in
            try mergedMistralVibeTOML(data: data, hookBinary: hookBinary)
        }
    }

    /// Merges Perch into DeepSeek TUI's `[hooks]` / `[[hooks.hooks]]` schema while
    /// preserving every user-owned byte outside the delimited block.
    public static func mergedDeepSeekTOML(
        data: Data, hookBinary: String,
        events: [Event] = deepSeekEvents
    ) throws -> Data {
        guard var text = String(data: data, encoding: .utf8) else {
            throw Failure.invalidTOMLString
        }
        text = try removingManagedTOMLBlock(
            from: text, startMarker: deepSeekBlockStart, endMarker: deepSeekBlockEnd)
        try rejectRootHooksArray(in: text)
        _ = try quotedTOML(hookBinary)

        var block = [deepSeekBlockStart]
        let hookHeaders = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let hasHooksTable = hookHeaders.contains("[hooks]")
            || hookHeaders.contains("[[hooks.hooks]]")
        if !hasHooksTable {
            block.append("[hooks]\nenabled = true")
        }
        for event in events {
            let slug = event.name.replacingOccurrences(of: "_", with: "-")
            block.append(
                """
                [[hooks.hooks]]
                name = \(try quotedTOML("perch-\(slug)"))
                event = \(try quotedTOML(event.name))
                command = \(try quotedTOML("\(hookBinary) \(event.commandName) --source deepseek"))
                timeout_secs = \(event.timeout)
                continue_on_error = true
                """)
        }
        block.append(deepSeekBlockEnd)

        let base = text.trimmingCharacters(in: .newlines)
        let merged = base.isEmpty
            ? block.joined(separator: "\n") + "\n"
            : base + "\n\n" + block.joined(separator: "\n") + "\n"
        return Data(merged.utf8)
    }

    public static func installDeepSeekTOML(
        at url: URL, hookBinary: String
    ) throws {
        try installFile(at: url, emptyData: Data()) { data in
            try mergedDeepSeekTOML(data: data, hookBinary: hookBinary)
        }
    }

    /// Antigravity owns a named object inside its global `hooks.json`. Reinstalling
    /// replaces only `perch`; every other named hook remains untouched.
    public static func mergedAntigravityHooks(
        data: Data, hookBinary: String,
        events: [Event] = antigravityEvents
    ) throws -> Data {
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard var root = decoded as? [String: Any] else { throw Failure.invalidRoot }

        var perch: [String: Any] = ["enabled": true]
        for event in events {
            let command: [String: Any] = [
                "type": "command",
                "command": "\(hookBinary) \(event.commandName) --source antigravity",
                "timeout": event.timeout,
            ]
            if event.name == "PreToolUse" || event.name == "PostToolUse" {
                perch[event.name] = [["matcher": "*", "hooks": [command]]]
            } else {
                perch[event.name] = [command]
            }
        }
        root["perch"] = perch
        return try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    public static func installAntigravityHooks(
        at url: URL, hookBinary: String
    ) throws {
        try installFile(at: url) { data in
            try mergedAntigravityHooks(data: data, hookBinary: hookBinary)
        }
    }

    public static func mergedCopilotHooks(
        data: Data, hookBinary: String,
        events: [Event] = copilotEvents
    ) throws -> Data {
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard var root = decoded as? [String: Any] else { throw Failure.invalidRoot }
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for key in hooks.keys {
            guard let entries = hooks[key] as? [[String: Any]] else {
                throw Failure.invalidEvent(key)
            }
            let kept = entries.filter { entry in
                let command = (entry["bash"] as? String) ?? (entry["command"] as? String) ?? ""
                return !command.contains("perch-hook")
            }
            if kept.isEmpty { hooks.removeValue(forKey: key) } else { hooks[key] = kept }
        }
        for event in events {
            var entries = hooks[event.name] as? [[String: Any]] ?? []
            entries.append([
                "type": "command",
                "bash": "\(hookBinary) \(event.commandName) --source copilot",
                "timeoutSec": event.timeout,
            ])
            hooks[event.name] = entries
        }
        root["version"] = 1
        root["hooks"] = hooks
        return try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    public static func installCopilotHooks(
        at url: URL, hookBinary: String
    ) throws {
        try installFile(at: url) { data in
            try mergedCopilotHooks(data: data, hookBinary: hookBinary)
        }
    }

    private static func installFile(
        at url: URL, emptyData: Data = Data("{}".utf8),
        transform: (Data) throws -> Data
    ) throws {
        let manager = FileManager.default
        let existed = manager.fileExists(atPath: url.path)
        let existing: Data
        if existed {
            guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable(url.path) }
            existing = data
        } else {
            existing = emptyData
        }
        let output = try transform(existing)
        guard output != existing else { return }
        if existed {
            let backup = URL(fileURLWithPath: url.path + ".perch-backup")
            if !manager.fileExists(atPath: backup.path) {
                do { try existing.write(to: backup, options: .atomic) }
                catch { throw Failure.unwritable(backup.path) }
            }
        }
        do {
            try manager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try output.write(to: url, options: .atomic)
        } catch {
            throw Failure.unwritable(url.path)
        }
    }

    private static func removingManagedTOMLBlock(
        from input: String, startMarker: String, endMarker: String
    ) throws -> String {
        var text = input
        while let start = text.range(of: startMarker) {
            guard let end = text.range(
                of: endMarker, range: start.upperBound..<text.endIndex)
            else { throw Failure.invalidManagedTOMLBlock }
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }
        guard !text.contains(endMarker) else {
            throw Failure.invalidManagedTOMLBlock
        }
        return text
    }

    private static func rejectRootHooksArray(in input: String) throws {
        for rawLine in input.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") { return }
            guard let equals = line.firstIndex(of: "=") else { continue }
            if line[..<equals].trimmingCharacters(in: .whitespaces) == "hooks" {
                throw Failure.conflictingTOMLHooks
            }
        }
    }

    private static func quotedTOML(_ value: String) throws -> String {
        guard !value.unicodeScalars.contains(where: {
            $0.value < 0x20 && $0 != "\t"
        }) else { throw Failure.invalidTOMLString }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private static func removePerchEntries(_ group: [String: Any]) -> [String: Any]? {
        guard let entries = group["hooks"] as? [[String: Any]] else { return group }
        let kept = entries.filter { entry in
            guard let command = entry["command"] as? String else { return true }
            return !command.contains("perch-hook")
        }
        guard !kept.isEmpty else { return nil }
        var result = group
        result["hooks"] = kept
        return result
    }
}
