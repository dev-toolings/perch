import Foundation
import PerchKit

/// Reads Claude's subscription windows from the same OAuth endpoint as Vibe Island.
/// The access token stays in Claude Code's credential file and in the request header;
/// Perch's cache contains only the usage response.
actor AnthropicUsageClient {
  private let credentialsURL: URL
  private let cacheURL: URL
  private let session: URLSession
  private var lastAttempt: Date?
  private var lastReading: UsageLimitsReader.Reading?

  init(
    credentialsURL: URL = AnthropicOAuthCredentials.defaultURL,
    cacheURL: URL = URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent(".perch/cache/anthropic-oauth-usage.json"),
    session: URLSession = .shared
  ) {
    self.credentialsURL = credentialsURL
    self.cacheURL = cacheURL
    self.session = session
  }

  func fetch(now: Date = .now) async -> UsageLimitsReader.Reading? {
    if let lastAttempt, now.timeIntervalSince(lastAttempt) < 60 {
      return lastReading ?? cached()
    }
    lastAttempt = now

    do {
      // Perch is ad-hoc signed in local builds. Never fall back to Claude's Keychain item
      // from the background usage poll: every rebuild changes the code identity and would
      // reopen the "Claude Code-credentials" approval dialog. The credential file is the
      // same local OAuth source when Claude Code has written one; otherwise usage is simply
      // unavailable and the cached reading remains visible.
      let token = try AnthropicOAuthCredentials.loadFromFile(credentialsURL)
      let request = try AnthropicOAuthUsageRequest.make(accessToken: token)
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
      else {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        throw FetchError.http(status)
      }
      guard let limits = AnthropicOAuthUsageResponse.parse(data), !limits.isEmpty
      else { throw FetchError.emptyResponse }

      try FileManager.default.createDirectory(
        at: cacheURL.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      try data.write(to: cacheURL, options: .atomic)
      let reading = UsageLimitsReader.Reading(limits: limits, updatedAt: now)
      lastReading = reading
      return reading
    } catch AnthropicOAuthUsageError.missingAccessToken {
      // An ordinary state for API-key, Bedrock, or Vertex users.
      let reading = cached()
      lastReading = reading
      return reading
    } catch {
      PerchLog.error("anthropic usage: \(error.localizedDescription)")
      let reading = cached()
      lastReading = reading
      return reading
    }
  }

  private func cached() -> UsageLimitsReader.Reading? {
    guard let data = try? Data(contentsOf: cacheURL),
      let limits = AnthropicOAuthUsageResponse.parse(data)
    else { return nil }
    let modified = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?
      .contentModificationDate
    return UsageLimitsReader.Reading(limits: limits, updatedAt: modified)
  }

  private enum FetchError: LocalizedError {
    case http(Int)
    case emptyResponse

    var errorDescription: String? {
      switch self {
      case .http(let status): return "Anthropic usage returned HTTP \(status)."
      case .emptyResponse: return "Anthropic usage returned no usable windows."
      }
    }
  }
}
