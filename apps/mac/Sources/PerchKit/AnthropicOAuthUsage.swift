import Foundation
import Security

public enum UsageNetworkRefresh {
  public static let minimumInterval: TimeInterval = 60

  public static func shouldFetch(
    lastAttempt: Date?, now: Date, force: Bool
  ) -> Bool {
    force || lastAttempt.map { now.timeIntervalSince($0) >= minimumInterval } ?? true
  }
}

public enum AnthropicOAuthUsageError: Error, Equatable, LocalizedError {
  case invalidCredentialsFile
  case missingAccessToken
  case keychain(OSStatus)

  public var errorDescription: String? {
    switch self {
    case .invalidCredentialsFile:
      return "Claude Code's OAuth credentials file is not valid JSON."
    case .missingAccessToken:
      return "Claude Code's OAuth access token is missing."
    case .keychain(let status):
      let detail = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
      return
        "Claude Code's OAuth credential could not be read from the login keychain: \(detail) (\(status))."
    }
  }
}

/// Reads only the access token Claude Code already stores locally. The token is never
/// copied to Perch's cache or diagnostics; it is used solely as the Authorization header
/// for Anthropic's usage endpoint.
public enum AnthropicOAuthCredentials {
  public static var defaultURL: URL {
    URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent(".claude/.credentials.json")
  }

  public static func accessToken(in data: Data) throws -> String {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw AnthropicOAuthUsageError.invalidCredentialsFile }
    let oauth = root["claudeAiOauth"] as? [String: Any]
    let token = (oauth?["accessToken"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let token, !token.isEmpty else {
      throw AnthropicOAuthUsageError.missingAccessToken
    }
    return token
  }

  public static func load(
    from url: URL = defaultURL,
    keychainService: String = "Claude Code-credentials"
  ) throws -> String {
    if FileManager.default.fileExists(atPath: url.path) {
      return try loadFromFile(url)
    }

    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { throw AnthropicOAuthUsageError.missingAccessToken }
    guard status == errSecSuccess, let data = result as? Data else {
      throw AnthropicOAuthUsageError.keychain(status)
    }
    return try accessToken(in: data)
  }

  /// Loads Claude's credential file without falling back to Keychain. Development app
  /// bundles are ad-hoc signed, so their code identity changes after every rebuild and a
  /// background Keychain lookup would trigger a fresh macOS approval prompt each time.
  public static func loadFromFile(_ url: URL = defaultURL) throws -> String {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw AnthropicOAuthUsageError.missingAccessToken
    }
    return try accessToken(in: Data(contentsOf: url))
  }
}

public enum AnthropicOAuthUsageRequest {
  public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

  public static func make(accessToken: String) throws -> URLRequest {
    let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else { throw AnthropicOAuthUsageError.missingAccessToken }

    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }
}

public enum AnthropicOAuthUsageResponse {
  public static func parse(_ data: Data) -> RateLimits? {
    guard var result = RateLimits.parse(data),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    let reserved: Set<String> = [
      "five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet",
      "extra_usage", "spend", "rate_limits_available", "rate_limits",
    ]
    result.modelScoped += root.compactMap { key, value -> NamedWindow? in
      guard !reserved.contains(key), let raw = value as? [String: Any],
        let wrapped = try? JSONSerialization.data(
          withJSONObject: ["five_hour": raw]),
        let window = RateLimits.parse(wrapped)?.fiveHour,
        window.utilization != nil
      else { return nil }
      let title = key.split(separator: "_").map {
        $0.prefix(1).uppercased() + $0.dropFirst()
      }.joined(separator: " ")
      return NamedWindow(id: key, title: title, window: window)
    }
    result.modelScoped.sort { $0.id < $1.id }
    return result
  }
}
