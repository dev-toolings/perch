import Foundation
import PerchKit

/// Installs the hook formats Perch can currently emit without external tools.
enum AgentConfigurator {
    enum Failure: Error, LocalizedError {
        case missingHookBinary
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .missingHookBinary:
                return "The Perch hook binary is missing from the application bundle. Reinstall Perch."
            case .unsupported(let name):
                return "Automatic configuration for \(name) is not implemented yet."
            }
        }
    }

    static func configure(_ name: String, home: String = NSHomeDirectory()) throws {
        guard let hook = Bundle.main.url(forResource: "perch-hook", withExtension: nil) else {
            throw Failure.missingHookBinary
        }
        let root = URL(fileURLWithPath: home, isDirectory: true)
        switch name {
        case "Claude Code":
            try HookConfiguration.install(
                at: root.appendingPathComponent(".claude/settings.json"),
                hookBinary: hook.path, source: "claude")
        case "Codex":
            try HookConfiguration.install(
                at: root.appendingPathComponent(".codex/hooks.json"),
                hookBinary: hook.path, source: "codex")
        case "Gemini CLI":
            try HookConfiguration.install(
                at: root.appendingPathComponent(".gemini/settings.json"),
                hookBinary: hook.path, source: "gemini",
                events: HookConfiguration.geminiEvents)
        case "OpenCode":
            guard let resources = Bundle.main.resourceURL else {
                throw Failure.missingHookBinary
            }
            let sourceDirectory = resources.appendingPathComponent("scripts/opencode-plugin")
            let destination = root.appendingPathComponent(".config/opencode/plugins")
            try FileManager.default.createDirectory(
                at: destination, withIntermediateDirectories: true)
            for filename in ["perch.js", "package.json"] {
                let source = sourceDirectory.appendingPathComponent(filename)
                let target = destination.appendingPathComponent(filename)
                guard let data = try? Data(contentsOf: source) else {
                    throw Failure.missingHookBinary
                }
                if filename == "package.json", FileManager.default.fileExists(atPath: target.path) {
                    continue
                }
                if FileManager.default.fileExists(atPath: target.path) {
                    let backup = URL(fileURLWithPath: target.path + ".perch-backup")
                    if !FileManager.default.fileExists(atPath: backup.path) {
                        try Data(contentsOf: target).write(to: backup, options: .atomic)
                    }
                }
                try data.write(to: target, options: .atomic)
            }
        case "Amp":
            guard let resources = Bundle.main.resourceURL else {
                throw Failure.missingHookBinary
            }
            let source = resources.appendingPathComponent("scripts/amp-plugin/perch.ts")
            let target = root.appendingPathComponent(".config/amp/plugins/perch.ts")
            guard let template = try? String(contentsOf: source, encoding: .utf8) else {
                throw Failure.missingHookBinary
            }
            let data = Data(template.replacingOccurrences(of: "__PERCH_HOOK__", with: hook.path).utf8)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) {
                let backup = URL(fileURLWithPath: target.path + ".perch-backup")
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try Data(contentsOf: target).write(to: backup, options: .atomic)
                }
            }
            try data.write(to: target, options: .atomic)
        case "Pi Agent":
            guard let resources = Bundle.main.resourceURL else {
                throw Failure.missingHookBinary
            }
            let source = resources.appendingPathComponent("scripts/pi-extension/perch.ts")
            let target = root.appendingPathComponent(".pi/agent/extensions/perch.ts")
            guard let template = try? String(contentsOf: source, encoding: .utf8) else {
                throw Failure.missingHookBinary
            }
            let data = Data(
                template.replacingOccurrences(of: "__PERCH_HOOK__", with: hook.path).utf8)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) {
                let backup = URL(fileURLWithPath: target.path + ".perch-backup")
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try Data(contentsOf: target).write(to: backup, options: .atomic)
                }
            }
            try data.write(to: target, options: .atomic)
        case "Cursor Agent":
            try HookConfiguration.installCursor(
                at: root.appendingPathComponent(".cursor/hooks.json"),
                hookBinary: hook.path)
        case "Droid":
            try HookConfiguration.install(
                at: root.appendingPathComponent(".factory/settings.json"),
                hookBinary: hook.path, source: "droid")
        case "Kimi":
            try HookConfiguration.installKimiTOML(
                at: root.appendingPathComponent(".kimi/config.toml"),
                hookBinary: hook.path, source: "kimi")
        case "Kimi Code":
            try HookConfiguration.installKimiTOML(
                at: root.appendingPathComponent(".kimi-code/config.toml"),
                hookBinary: hook.path, source: "kimicode")
        case "Mistral Vibe":
            try HookConfiguration.installMistralVibeTOML(
                at: root.appendingPathComponent(".vibe/hooks.toml"),
                hookBinary: hook.path)
        case "DeepSeek TUI":
            try HookConfiguration.installDeepSeekTOML(
                at: root.appendingPathComponent(".deepseek/config.toml"),
                hookBinary: hook.path)
        case "CodeWhale":
            try HookConfiguration.installDeepSeekTOML(
                at: root.appendingPathComponent(".codewhale/config.toml"),
                hookBinary: hook.path)
        case "WorkBuddy":
            try HookConfiguration.install(
                at: root.appendingPathComponent(".workbuddy/settings.json"),
                hookBinary: hook.path, source: "workbuddy")
        case "CodeBuddy":
            try HookConfiguration.install(
                at: root.appendingPathComponent(".codebuddy/settings.json"),
                hookBinary: hook.path, source: "codebuddy")
        case "Antigravity CLI":
            try HookConfiguration.installAntigravityHooks(
                at: root.appendingPathComponent(".gemini/config/hooks.json"),
                hookBinary: hook.path)
        case "GitHub Copilot CLI":
            try HookConfiguration.installCopilotHooks(
                at: root.appendingPathComponent(".copilot/hooks/perch.json"),
                hookBinary: hook.path)
        default:
            throw Failure.unsupported(name)
        }
    }

    /// Only configure agents with a complete native installer.
    static func configureDetected(
        home: String = NSHomeDirectory(), names: Set<String>? = nil
    ) -> [String: Error] {
        var failures: [String: Error] = [:]
        for tool in EnvironmentScan.run(home: home)
        where tool.kind == .agent && tool.isConfigured == false
            && (names?.contains(tool.name) ?? true)
            && [
                "Claude Code", "Codex", "Gemini CLI", "OpenCode", "Cursor Agent",
                "Droid", "Pi Agent", "Amp", "Kimi", "Kimi Code", "Mistral Vibe",
                "DeepSeek TUI", "CodeWhale",
                "WorkBuddy", "CodeBuddy",
                "Antigravity CLI",
                "GitHub Copilot CLI",
            ]
                .contains(tool.name)
        {
            do { try configure(tool.name, home: home) }
            catch { failures[tool.name] = error }
        }
        return failures
    }
}
