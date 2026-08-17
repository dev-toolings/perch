import Foundation

public enum RemoteCodexConfigRoot: Codable, Sendable, Equatable, Hashable {
  case defaultHome
  case absolute(String)

  public var path: String {
    switch self {
    case .defaultHome: return "~/.codex"
    case .absolute(let path): return path
    }
  }
}

public enum RemoteCodexConfigRootSource: String, Codable, Sendable, Equatable {
  case paperclip
  case manual
  case saved
}

public struct RemoteCodexConfigRootCandidate: Codable, Sendable, Equatable, Identifiable {
  public var path: String
  public var source: RemoteCodexConfigRootSource

  public var id: String { path }

  public init(path: String, source: RemoteCodexConfigRootSource) {
    self.path = path
    self.source = source
  }
}

public enum RemoteCodexHookTrustState: String, Codable, Sendable, Equatable {
  case trusted
  case needsManualTrust
  case unverified
}

public struct RemoteCodexHookTrustSnapshot: Codable, Sendable, Equatable {
  public var state: RemoteCodexHookTrustState
  public var lastCheckedAt: Date?

  public init(state: RemoteCodexHookTrustState = .unverified, lastCheckedAt: Date? = nil) {
    self.state = state
    self.lastCheckedAt = lastCheckedAt
  }
}

public struct RemoteCodexRootSetupModel: Sendable, Equatable {
  public private(set) var rows: [RemoteCodexConfigRootCandidate]
  public private(set) var selectedPaths: Set<String>

  public init(
    discovered: [RemoteCodexConfigRootCandidate],
    previouslySelected: [String] = []
  ) {
    let selected = Set(previouslySelected.map(Self.normalizedPath))
    var candidates = discovered
    candidates.append(contentsOf: selected.map {
      RemoteCodexConfigRootCandidate(path: $0, source: .saved)
    })
    candidates.append(
      RemoteCodexConfigRootCandidate(path: RemoteCodexConfigRoot.defaultHome.path, source: .saved))

    var seen = Set<String>()
    rows = candidates.compactMap { candidate in
      let path = Self.normalizedPath(candidate.path)
      guard !path.isEmpty, seen.insert(path).inserted else { return nil }
      return RemoteCodexConfigRootCandidate(path: path, source: candidate.source)
    }
    selectedPaths = selected
  }

  public mutating func toggle(_ path: String) {
    let path = Self.normalizedPath(path)
    guard rows.contains(where: { $0.path == path }) else { return }
    if selectedPaths.remove(path) == nil { selectedPaths.insert(path) }
  }

  @discardableResult
  public mutating func addManualPath(_ value: String) -> Bool {
    let path = Self.normalizedPath(value)
    guard Self.isAbsoluteRemotePath(path) else { return false }
    if !rows.contains(where: { $0.path == path }) {
      rows.append(RemoteCodexConfigRootCandidate(path: path, source: .manual))
    }
    selectedPaths.insert(path)
    return true
  }

  public var selectedAdditionalRoots: [String] {
    selectedPaths.filter { $0 != RemoteCodexConfigRoot.defaultHome.path }.sorted()
  }

  public static func isAbsoluteRemotePath(_ value: String) -> Bool {
    let path = normalizedPath(value)
    return path == RemoteCodexConfigRoot.defaultHome.path || path.hasPrefix("/")
  }

  private static func normalizedPath(_ value: String) -> String {
    var path = value.trimmingCharacters(in: .whitespacesAndNewlines)
    while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
    return path
  }
}

public struct RemoteCodexHooksListResponse: Decodable, Sendable, Equatable {
  public struct Entry: Decodable, Sendable, Equatable {
    public struct Issue: Decodable, Sendable, Equatable {
      public var message: String
      public var path: String
    }

    public struct Hook: Decodable, Sendable, Equatable {
      public var command: String?
      public var sourcePath: String
      public var trustStatus: String
    }

    public var errors: [Issue]
    public var warnings: [String]
    public var hooks: [Hook]
  }

  public var data: [Entry]
}

/// Reduces Codex app-server's `hooks/list` response to Vibe's three-state remote model.
/// Unknown statuses and reported errors stay unverified: a security result is never
/// guessed from a response this version does not understand.
public enum RemoteCodexHookTrustEvaluator {
  public static func evaluate(
    _ response: RemoteCodexHooksListResponse
  ) -> RemoteCodexHookTrustState {
    guard response.data.allSatisfy({ $0.errors.isEmpty }) else { return .unverified }
    let hooks = response.data.flatMap(\.hooks).filter {
      $0.command?.contains("perch-remote-hook") == true
    }
    guard !hooks.isEmpty else { return .unverified }

    let statuses = Set(hooks.map(\.trustStatus))
    if !statuses.isSubset(of: ["managed", "trusted", "untrusted", "modified"]) {
      return .unverified
    }
    if statuses.contains("untrusted") || statuses.contains("modified") {
      return .needsManualTrust
    }
    return .trusted
  }
}

/// Minimal shape returned by Codex app-server's `account/rateLimits/read` method.
public struct RemoteCodexRateLimitsResponse: Decodable, Sendable, Equatable {
  public struct Snapshot: Decodable, Sendable, Equatable {
    public struct Window: Decodable, Sendable, Equatable {
      public var usedPercent: Int
      public var windowDurationMins: Int?
      public var resetsAt: Int?
    }

    public var limitId: String?
    public var limitName: String?
    public var primary: Window?
    public var secondary: Window?
  }

  public var rateLimits: Snapshot
  public var rateLimitsByLimitId: [String: Snapshot]?
}

public enum RemoteCodexRateLimitsEvaluator {
  public static func evaluate(
    _ response: RemoteCodexRateLimitsResponse, rootLabel: String? = nil
  ) -> RateLimits? {
    let snapshots: [(String, RemoteCodexRateLimitsResponse.Snapshot)]
    if let byID = response.rateLimitsByLimitId, !byID.isEmpty {
      snapshots = byID.sorted { $0.key < $1.key }
    } else {
      snapshots = [(response.rateLimits.limitId ?? "codex", response.rateLimits)]
    }

    var windows: [NamedWindow] = []
    for (fallbackID, snapshot) in snapshots {
      let limitID = snapshot.limitId ?? fallbackID
      let name = snapshot.limitName?.trimmingCharacters(in: .whitespacesAndNewlines)
      append(snapshot.primary, suffix: "primary", limitID: limitID, name: name,
             rootLabel: rootLabel, to: &windows)
      append(snapshot.secondary, suffix: "secondary", limitID: limitID, name: name,
             rootLabel: rootLabel, to: &windows)
    }
    guard !windows.isEmpty else { return nil }
    return RateLimits(modelScoped: windows)
  }

  private static func append(
    _ source: RemoteCodexRateLimitsResponse.Snapshot.Window?, suffix: String,
    limitID: String, name: String?, rootLabel: String?, to windows: inout [NamedWindow]
  ) {
    guard let source else { return }
    let duration = source.windowDurationMins
    let durationTitle = CodexQuota.title(forWindowMinutes: duration)
    let baseTitle = name.flatMap { $0.isEmpty ? nil : $0 } ?? durationTitle
    let title = rootLabel.map { "\($0) · \(baseTitle)" } ?? baseTitle
    let idPrefix = rootLabel.map { "\($0):" } ?? ""
    windows.append(
      NamedWindow(
        id: "\(idPrefix)\(limitID)_\(suffix)", title: title,
        window: RateLimitWindow(
          utilization: Double(source.usedPercent),
          resetsAt: source.resetsAt.map { Date(timeIntervalSince1970: Double($0)) })))
  }
}
