import Foundation

/// Which events also reach a phone, and where.
///
/// A notch notification only exists while you are at the machine; Bark points that same
/// signal at an iPhone and a paired Watch. Off by default: a push service is an address
/// Perch would otherwise post to on someone else's behalf, so it must be chosen before
/// anything leaves the machine. Device and encryption credentials live in Keychain.
public struct PushSettings: Codable, Sendable, Equatable {
  public var enabled: Bool
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
    server: String = "https://api.day.app",
    idleThresholdMinutes: Int = 2,
    pushedKinds: Set<InterruptionKind> = [.approvalNeeded, .questionAsked]
  ) {
    self.enabled = enabled
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
    server = (try? container.decode(String.self, forKey: .server)) ?? defaults.server
    idleThresholdMinutes =
      (try? container.decode(Int.self, forKey: .idleThresholdMinutes))
      ?? defaults.idleThresholdMinutes
    pushedKinds =
      (try? container.decode(Set<InterruptionKind>.self, forKey: .pushedKinds))
      ?? defaults.pushedKinds
  }

  /// A blank server, a threshold too short to survive a glance away from the screen, or a
  /// configuration choice — it is a broken one. Applied at commit or at load, never on
  /// every keystroke: doing it live in a text field's own binding is what made the
  /// server field impossible to type into in the first place.
  public var sanitised: PushSettings {
    var copy = self
    if copy.server.trimmingCharacters(in: .whitespaces).isEmpty {
      copy.server = PushSettings().server
    }
    // Trailing slash would double up against the `/push` endpoint the notifier appends.
    while copy.server.hasSuffix("/") { copy.server.removeLast() }
    copy.idleThresholdMinutes = min(max(idleThresholdMinutes, 1), 60)
    // The pre-Bark build stored ntfy here. Never reinterpret an old endpoint as a
    // Bark server: disable outward traffic and require an explicit Bark setup.
    if URL(string: copy.server)?.host?.caseInsensitiveCompare("ntfy.sh") == .orderedSame {
      copy.enabled = false
      copy.server = PushSettings().server
    }
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
