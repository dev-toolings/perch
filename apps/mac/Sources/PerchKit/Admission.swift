import Foundation

/// Decides what is even allowed into the panel.
///
/// A machine that runs agents runs a lot of sessions nobody asked for: memory writers,
/// title generators, background reviewers, plugin compaction passes. Without a filter in
/// front of the panel, those bury the two sessions you actually care about — so this is
/// not a preference, it is what makes a notch app usable at all.
///
/// Rules are matched against the working directory and the session's first prompt, which
/// are the only two things a background session reliably differs by.
public struct AdmissionRule: Codable, Sendable, Equatable, Identifiable {
    public enum Field: String, Codable, Sendable {
        case directory
        case prompt
    }

    public enum Match: String, Codable, Sendable {
        case contains
        case prefix
    }

    public var id: String
    public var field: Field
    public var match: Match
    public var pattern: String
    public var enabled: Bool
    /// Preset rules ship with Perch and are listed apart from the user's own.
    public var isPreset: Bool
    /// Shown next to a preset so it is clear what it is for.
    public var note: String?

    public init(
        id: String = UUID().uuidString,
        field: Field,
        match: Match,
        pattern: String,
        enabled: Bool = true,
        isPreset: Bool = false,
        note: String? = nil
    ) {
        self.id = id
        self.field = field
        self.match = match
        self.pattern = pattern
        self.enabled = enabled
        self.isPreset = isPreset
        self.note = note
    }

    /// Case-insensitive: paths and prompts are typed by humans.
    public func matches(directory: String?, prompt: String?) -> Bool {
        guard enabled, !pattern.isEmpty else { return false }
        let subject = (field == .directory ? directory : prompt)?.lowercased()
        guard let subject, !subject.isEmpty else { return false }
        let needle = pattern.lowercased()

        switch match {
        case .contains: return subject.contains(needle)
        case .prefix: return subject.hasPrefix(needle)
        }
    }
}

public struct AdmissionPolicy: Codable, Sendable, Equatable {
    public var rules: [AdmissionRule]

    public init(rules: [AdmissionRule] = AdmissionPolicy.presets) {
        self.rules = rules
    }

    /// Background sessions Perch knows about. Off by default: silently hiding a session
    /// someone did want is worse than showing one they did not, so these are opt-in.
    public static let presets: [AdmissionRule] = [
        AdmissionRule(
            id: "preset.codex-memory-cwd", field: .directory, match: .contains,
            pattern: "/.codex/memories", enabled: false, isPreset: true,
            note: "Codex Memory Writer (cwd)"),
        AdmissionRule(
            id: "preset.codex-chronicle", field: .directory, match: .contains,
            pattern: "/chronicle/screen_recording", enabled: false, isPreset: true,
            note: "Codex Chronicle Memory Summary"),
        AdmissionRule(
            id: "preset.claude-mem-directory", field: .directory, match: .contains,
            pattern: "/.claude-mem", enabled: false, isPreset: true,
            note: "Claude-Mem plugin background compression sessions"),
        AdmissionRule(
            id: "preset.claude-mem", field: .prompt, match: .prefix,
            pattern: "## Memory Writing Agent", enabled: false, isPreset: true,
            note: "Codex Memory Writer (prompt prefix)"),
        AdmissionRule(
            id: "preset.codex-suggestions", field: .prompt, match: .prefix,
            pattern: "# Overview Generate 0 to 3 hyperpersonalized suggestions",
            enabled: false, isPreset: true,
            note: "Codex App suggested prompts"),
        AdmissionRule(
            id: "preset.codex-git-helper", field: .prompt, match: .prefix,
            pattern: "Using the supplied git context below, generate",
            enabled: false, isPreset: true,
            note: "Codex App Git helper prompts"),
        AdmissionRule(
            id: "preset.craft-title", field: .prompt, match: .prefix,
            pattern: "What topic or area is the user exploring? Reply with ONLY a short descriptive title",
            enabled: false, isPreset: true,
            note: "Craft Agent title generator"),
    ]

    /// True when the session should never reach the panel.
    public func isSilenced(directory: String?, prompt: String?) -> Bool {
        rules.contains { $0.matches(directory: directory, prompt: prompt) }
    }

    /// How many of the given sessions a pattern would hide — shown live while typing, so
    /// nobody commits to a rule that silences everything.
    public func matchCount(
        of rule: AdmissionRule,
        in sessions: [(directory: String?, prompt: String?)]
    ) -> Int {
        sessions.filter { rule.matches(directory: $0.directory, prompt: $0.prompt) }.count
    }

    public mutating func add(_ rule: AdmissionRule) {
        guard
            !rules.contains(where: {
                $0.field == rule.field && $0.match == rule.match
                    && $0.pattern.caseInsensitiveCompare(rule.pattern) == .orderedSame
            })
        else { return }
        rules.append(rule)
    }

    public mutating func remove(id: String) {
        rules.removeAll { $0.id == id && !$0.isPreset }
    }

    public mutating func setEnabled(_ enabled: Bool, id: String) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].enabled = enabled
    }

    public var custom: [AdmissionRule] { rules.filter { !$0.isPreset } }
    public var presetRules: [AdmissionRule] { rules.filter(\.isPreset) }
}

extension AdmissionPolicy {
    public static var defaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".perch/admission.json")
    }

    /// Missing or corrupt file means the presets, not an empty policy — a filter that
    /// silently stops filtering is worse than one that never started.
    public static func load(from url: URL = defaultURL) -> AdmissionPolicy {
        guard let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(AdmissionPolicy.self, from: data)
        else { return AdmissionPolicy() }

        // Presets added by a later version must appear for people who already have a file.
        var policy = decoded
        let presetIDs = Set(AdmissionPolicy.presets.map(\.id))
        policy.rules.removeAll { $0.isPreset && !presetIDs.contains($0.id) }
        for preset in AdmissionPolicy.presets {
            if let index = policy.rules.firstIndex(where: { $0.id == preset.id }) {
                let enabled = policy.rules[index].enabled
                policy.rules[index] = preset
                policy.rules[index].enabled = enabled
            } else {
                policy.rules.append(preset)
            }
        }
        return policy
    }

    public func save(to url: URL = defaultURL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(self)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("perch: could not save admission rules: \(error)")
        }
    }
}
