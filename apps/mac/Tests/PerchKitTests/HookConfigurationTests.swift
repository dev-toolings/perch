import Foundation
import Testing

@testable import PerchKit

@Suite("Hook configuration")
struct HookConfigurationTests {
    @Test("install preserves foreign hooks and replaces Perch entries")
    func preservesForeignHooks() throws {
        let input = Data(
            """
            {
              "theme": "dark",
              "hooks": {
                "Stop": [
                  {"hooks": [{"type": "command", "command": "notify-me"}]},
                  {"hooks": [{"type": "command", "command": "/old/perch-hook Stop"}]}
                ]
              }
            }
            """.utf8)

        let output = try HookConfiguration.merged(
            data: input, hookBinary: "/Applications/Perch.app/perch-hook", source: "droid",
            events: [.init("Stop")])
        let text = try #require(String(data: output, encoding: .utf8))

        #expect(text.contains("notify-me"))
        #expect(text.contains("/Applications/Perch.app/perch-hook Stop --source droid"))
        #expect(!text.contains("/old/perch-hook"))
        #expect(text.contains("\"theme\" : \"dark\""))
    }

    @Test("install is idempotent")
    func idempotent() throws {
        let first = try HookConfiguration.merged(
            data: Data("{}".utf8), hookBinary: "/perch-hook", source: "claude",
            events: [.init("Stop")])
        let second = try HookConfiguration.merged(
            data: first, hookBinary: "/perch-hook", source: "claude",
            events: [.init("Stop")])
        let text = try #require(String(data: second, encoding: .utf8))

        #expect(text.components(separatedBy: "/perch-hook").count - 1 == 1)
    }

    @Test("malformed hook objects fail explicitly")
    func rejectsMalformedHooks() {
        #expect(throws: HookConfiguration.Failure.invalidHooks) {
            try HookConfiguration.merged(
                data: Data("{\"hooks\": []}".utf8), hookBinary: "/perch-hook",
                source: "claude")
        }
    }

    @Test("Cursor hooks use its flat schema and preserve other commands")
    func cursorSchema() throws {
        let input = Data(
            """
            {"version": 1, "hooks": {"stop": [{"command": "notify-me"}]}}
            """.utf8)
        let output = try HookConfiguration.mergedCursor(
            data: input, hookBinary: "/perch-hook")
        let object = try #require(
            JSONSerialization.jsonObject(with: output) as? [String: Any])
        let hooks = try #require(object["hooks"] as? [String: Any])
        let stop = try #require(hooks["stop"] as? [[String: Any]])

        #expect(stop.count == 2)
        #expect(stop[0]["command"] as? String == "notify-me")
        #expect(stop[1]["command"] as? String == "/perch-hook Stop --source cursor")
    }

    @Test("reinstall keeps the first backup")
    func keepsFirstBackup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = root.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("{\"owner\":\"first\"}".utf8).write(to: settings)

        try HookConfiguration.install(
            at: settings, hookBinary: "/perch-hook", source: "claude",
            events: [.init("Stop")])
        try HookConfiguration.install(
            at: settings, hookBinary: "/perch-hook", source: "claude",
            events: [.init("Stop")])

        let backup = try Data(contentsOf: URL(fileURLWithPath: settings.path + ".perch-backup"))
        #expect(String(data: backup, encoding: .utf8) == "{\"owner\":\"first\"}")
    }

    @Test("Gemini uses its event names and millisecond timeouts")
    func geminiSchema() throws {
        let output = try HookConfiguration.merged(
            data: Data("{}".utf8), hookBinary: "/perch-hook", source: "gemini",
            events: [.init("BeforeTool", command: "PreToolUse", timeout: 5_000)])
        let text = try #require(String(data: output, encoding: .utf8))

        #expect(text.contains("\"BeforeTool\""))
        #expect(text.contains("/perch-hook PreToolUse --source gemini"))
        #expect(text.contains("\"timeout\" : 5000"))
    }

    @Test("Kimi TOML hooks preserve user settings and reinstall in place")
    func kimiTOMLIsIdempotent() throws {
        let input = Data(
            """
            default_model = "kimi-code/k3"

            [[hooks]]
            event = "Notification"
            command = "notify-me"
            """.utf8)

        let first = try HookConfiguration.mergedKimiTOML(
            data: input, hookBinary: "/Applications/Perch.app/perch-hook", source: "kimicode",
            events: [.init("UserPromptSubmit"), .init("Stop")])
        let second = try HookConfiguration.mergedKimiTOML(
            data: first, hookBinary: "/Applications/Perch.app/perch-hook", source: "kimicode",
            events: [.init("UserPromptSubmit"), .init("Stop")])
        let text = try #require(String(data: second, encoding: .utf8))

        #expect(text.contains("default_model = \"kimi-code/k3\""))
        #expect(text.contains("command = \"notify-me\""))
        #expect(text.components(separatedBy: "# --- perch Kimi hooks START").count - 1 == 1)
        #expect(text.components(separatedBy: "--source kimicode").count - 1 == 2)
        #expect(text.contains("event = \"UserPromptSubmit\""))
        #expect(text.contains("timeout = 5"))
    }

    @Test("Kimi TOML refuses a conflicting root hooks array")
    func kimiTOMLRejectsRootArray() {
        #expect(throws: HookConfiguration.Failure.conflictingTOMLHooks) {
            try HookConfiguration.mergedKimiTOML(
                data: Data("hooks = []\n".utf8), hookBinary: "/perch-hook",
                source: "kimi")
        }
    }

    @Test("Kimi TOML rejects an unterminated Perch block")
    func kimiTOMLRejectsBrokenManagedBlock() {
        #expect(throws: HookConfiguration.Failure.invalidManagedTOMLBlock) {
            try HookConfiguration.mergedKimiTOML(
                data: Data("# --- perch Kimi hooks START (managed, do not edit) ---\n".utf8),
                hookBinary: "/perch-hook", source: "kimi")
        }
    }

    @Test("a new Kimi config starts as TOML, not a JSON object")
    func installsNewKimiTOML() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent(".kimi/config.toml")

        try HookConfiguration.installKimiTOML(
            at: config, hookBinary: "/perch-hook", source: "kimi")
        let text = try String(contentsOf: config, encoding: .utf8)

        #expect(text.hasPrefix("# --- perch Kimi hooks START"))
        #expect(!text.contains("{}"))
    }

    @Test("Mistral Vibe hooks use stable native types and preserve foreign hooks")
    func mistralVibeTOMLIsIdempotent() throws {
        let input = Data(
            """
            [[hooks]]
            name = "foreign-audit"
            type = "post_tool"
            command = "audit-me"
            """.utf8)

        let first = try HookConfiguration.mergedMistralVibeTOML(
            data: input, hookBinary: "/perch-hook")
        let second = try HookConfiguration.mergedMistralVibeTOML(
            data: first, hookBinary: "/perch-hook")
        let text = try #require(String(data: second, encoding: .utf8))

        #expect(text.contains("command = \"audit-me\""))
        #expect(text.components(separatedBy: "# --- perch Mistral Vibe hooks START").count - 1 == 1)
        #expect(text.components(separatedBy: "--source mistralvibe").count - 1 == 3)
        #expect(text.contains("name = \"perch-pre-tool\""))
        #expect(text.contains("type = \"pre_tool\""))
        #expect(text.contains("/perch-hook PreToolUse --source mistralvibe"))
        #expect(text.contains("/perch-hook PostToolUse --source mistralvibe"))
        #expect(text.contains("/perch-hook Stop --source mistralvibe"))
    }

    @Test("Mistral Vibe rejects an unterminated Perch block")
    func mistralVibeRejectsBrokenManagedBlock() {
        #expect(throws: HookConfiguration.Failure.invalidManagedTOMLBlock) {
            try HookConfiguration.mergedMistralVibeTOML(
                data: Data(
                    "# --- perch Mistral Vibe hooks START (managed, do not edit) ---\n".utf8),
                hookBinary: "/perch-hook")
        }
    }

    @Test("DeepSeek hooks use the nested TOML schema and preserve user hooks")
    func deepSeekTOMLIsIdempotent() throws {
        let input = Data(
            """
            [hooks]
            enabled = true

            [[hooks.hooks]]
            name = "foreign"
            event = "session_start"
            command = "notify-me"
            """.utf8)

        let first = try HookConfiguration.mergedDeepSeekTOML(
            data: input, hookBinary: "/perch-hook")
        let second = try HookConfiguration.mergedDeepSeekTOML(
            data: first, hookBinary: "/perch-hook")
        let text = try #require(String(data: second, encoding: .utf8))

        #expect(text.contains("command = \"notify-me\""))
        #expect(text.components(separatedBy: "# --- perch DeepSeek hooks START").count - 1 == 1)
        #expect(text.components(separatedBy: "--source deepseek").count - 1 == 9)
        #expect(text.contains("event = \"tool_call_before\""))
        #expect(text.contains("/perch-hook PreToolUse --source deepseek"))
        #expect(text.components(separatedBy: "[hooks]\n").count - 1 == 1)
    }

    @Test("a new DeepSeek config enables its managed hook table")
    func newDeepSeekTOMLHasHooksTable() throws {
        let output = try HookConfiguration.mergedDeepSeekTOML(
            data: Data(), hookBinary: "/perch-hook")
        let text = try #require(String(data: output, encoding: .utf8))

        #expect(text.contains("[hooks]\nenabled = true"))
        #expect(text.contains("[[hooks.hooks]]"))
    }

    @Test("Antigravity owns one named hook without rewriting foreign hooks")
    func antigravityNamedHookIsIdempotent() throws {
        let input = Data(#"{"foreign":{"Stop":[{"command":"notify-me"}]}}"#.utf8)
        let first = try HookConfiguration.mergedAntigravityHooks(
            data: input, hookBinary: "/perch-hook")
        let second = try HookConfiguration.mergedAntigravityHooks(
            data: first, hookBinary: "/perch-hook")
        let root = try #require(
            JSONSerialization.jsonObject(with: second) as? [String: Any])
        let perch = try #require(root["perch"] as? [String: Any])

        #expect(root["foreign"] != nil)
        #expect(perch["PreToolUse"] != nil)
        #expect(perch["PostToolUse"] != nil)
        #expect(perch["Stop"] != nil)
        let text = try #require(String(data: second, encoding: .utf8))
        #expect(text.components(separatedBy: "--source antigravity").count - 1 == 3)
    }

    @Test("Copilot uses its versioned flat hook file and keeps foreign entries")
    func copilotHookFileIsIdempotent() throws {
        let input = Data(
            #"{"version":1,"hooks":{"Stop":[{"type":"command","bash":"notify-me"}]}}"#.utf8)
        let first = try HookConfiguration.mergedCopilotHooks(
            data: input, hookBinary: "/perch-hook")
        let second = try HookConfiguration.mergedCopilotHooks(
            data: first, hookBinary: "/perch-hook")
        let text = try #require(String(data: second, encoding: .utf8))

        #expect(text.contains("notify-me"))
        #expect(text.contains("\"version\" : 1"))
        #expect(text.components(separatedBy: "--source copilot").count - 1 == 13)
        #expect(text.contains("/perch-hook PreToolUse --source copilot"))
        #expect(text.contains("/perch-hook StopFailure --source copilot"))
    }
}
