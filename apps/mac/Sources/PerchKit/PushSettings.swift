import Foundation

/// Which events also reach a phone, and where.
///
/// A notch notification only exists while you are at the machine; ntfy is the same idea
/// pointed at a phone instead, so "the agent needs you" reaches you when you have stepped
/// away from it. Off by default, and empty by default within that: a push service is an
/// address Perch would otherwise post to on someone else's behalf, so both have to be
/// chosen before anything leaves the machine.
public struct PushSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// The ntfy topic to publish to. ntfy topics are unauthenticated by convention — anyone
    /// who knows the name can read it — so this is a name someone picks, not a password.
    public var topic: String
    /// Self-hostable, so the default points at the public instance rather than assuming a
    /// private server exists.
    public var server: String
    /// How long the user has to be away from the keyboard before a push is allowed out.
    /// Someone who stepped away for thirty seconds does not need their phone to buzz for
    /// something the notch would have shown them the moment they sat back down.
    public var idleThresholdMinutes: Int
    /// Which kinds of interruption are worth a phone buzz. Restricted to the two blocking
    /// kinds by default: those are the ones holding a session hostage until someone
    /// answers, which is the one case a notch on an empty desk cannot help with.
    public var pushedKinds: Set<InterruptionKind>

    public init(
        enabled: Bool = false,
        topic: String = "",
        server: String = "https://ntfy.sh",
        idleThresholdMinutes: Int = 3,
        pushedKinds: Set<InterruptionKind> = [.approvalNeeded, .questionAsked]
    ) {
        self.enabled = enabled
        self.topic = topic
        self.server = server
        self.idleThresholdMinutes = idleThresholdMinutes
        self.pushedKinds = pushedKinds
    }

    /// Tolerant field by field, not just key by key: `decodeIfPresent` still throws when a
    /// key is present with the wrong shape — a `pushedKinds` array containing a case a
    /// later version added, read back after a downgrade, would otherwise fail the whole
    /// container and silently turn every field off, `enabled` included. `try? decode`
    /// catches both "missing" and "wrong shape" the same way, so one broken field costs
    /// only itself.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PushSettings()
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? false
        topic = (try? container.decode(String.self, forKey: .topic)) ?? ""
        server = (try? container.decode(String.self, forKey: .server)) ?? defaults.server
        idleThresholdMinutes =
            (try? container.decode(Int.self, forKey: .idleThresholdMinutes))
            ?? defaults.idleThresholdMinutes
        pushedKinds =
            (try? container.decode(Set<InterruptionKind>.self, forKey: .pushedKinds))
            ?? defaults.pushedKinds
    }

    /// The characters ntfy accepts in a topic name. Anything else survives in the string
    /// but changes meaning once URL-escaped — a topic typed with a stray space addresses a
    /// *different* topic than the one on screen, silently.
    private static let topicCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

    /// A blank server, a threshold too short to survive a glance away from the screen, or a
    /// topic carrying characters that would change the URL it lands on, is not a
    /// configuration choice — it is a broken one. Applied at commit or at load, never on
    /// every keystroke: doing it live in a text field's own binding is what made the
    /// server field impossible to type into in the first place.
    public var sanitised: PushSettings {
        var copy = self
        if copy.server.trimmingCharacters(in: .whitespaces).isEmpty {
            copy.server = PushSettings().server
        }
        // Trailing slash would double up against the `/<topic>` the notifier appends.
        while copy.server.hasSuffix("/") { copy.server.removeLast() }
        copy.idleThresholdMinutes = min(max(idleThresholdMinutes, 1), 60)
        copy.topic = String(
            topic.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.filter {
                Self.topicCharacters.contains($0)
            })
        return copy
    }
}

extension PushSettings {
    public static var defaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".perch/push.json")
    }

    public static func load(from url: URL = defaultURL) -> PushSettings {
        guard let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(PushSettings.self, from: data)
        else { return PushSettings() }
        return decoded.sanitised
    }

    public func save(to url: URL = defaultURL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(sanitised).write(to: url, options: .atomic)
        } catch {
            NSLog("perch: could not save push settings: \(error)")
        }
    }
}
