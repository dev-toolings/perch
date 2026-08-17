import Foundation
import Testing

@testable import PerchKit

@Suite("Anthropic OAuth usage")
struct AnthropicOAuthUsageTests {
  @Test func forcedRefreshBypassesTheBackgroundThrottle() {
    let now = Date(timeIntervalSince1970: 1_700_000_030)
    let recent = Date(timeIntervalSince1970: 1_700_000_000)

    #expect(UsageNetworkRefresh.shouldFetch(lastAttempt: recent, now: now, force: true))
  }

  @Test func backgroundRefreshKeepsItsThrottle() {
    let now = Date(timeIntervalSince1970: 1_700_000_030)
    let recent = Date(timeIntervalSince1970: 1_700_000_000)
    let old = Date(timeIntervalSince1970: 1_699_999_900)

    #expect(!UsageNetworkRefresh.shouldFetch(lastAttempt: recent, now: now, force: false))
    #expect(UsageNetworkRefresh.shouldFetch(lastAttempt: old, now: now, force: false))
    #expect(UsageNetworkRefresh.shouldFetch(lastAttempt: nil, now: now, force: false))
  }

  @Test func readsClaudeCodesCredentialShape() throws {
    let data = Data(
      #"{"claudeAiOauth":{"accessToken":"oauth-secret","expiresAt":1999999999999}}"#.utf8)
    #expect(try AnthropicOAuthCredentials.accessToken(in: data) == "oauth-secret")
  }

  @Test func aCredentialFileWinsBeforeKeychainLookup() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(#"{"claudeAiOauth":{"accessToken":"file-token"}}"#.utf8).write(to: url)

    #expect(
      try AnthropicOAuthCredentials.load(
        from: url, keychainService: "service-that-does-not-exist") == "file-token")
  }

  @Test func fileOnlyLoadDoesNotFallBackToKeychain() {
    let missingURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)

    #expect(throws: AnthropicOAuthUsageError.missingAccessToken) {
      try AnthropicOAuthCredentials.loadFromFile(missingURL)
    }
  }

  @Test func buildsTheSameOAuthUsageRequestAsVibe() throws {
    let request = try AnthropicOAuthUsageRequest.make(accessToken: "oauth-secret")
    #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-secret")
    #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    #expect(request.httpBody == nil)
    #expect(!request.url!.absoluteString.contains("oauth-secret"))
  }

  @Test func parsesDirectUsageWindows() throws {
    let data = Data(
      #"{"five_hour":{"utilization":18,"resets_at":"2026-08-16T22:00:00Z"},"seven_day":{"utilization":51,"resets_at":"2026-08-20T12:00:00Z"},"seven_day_sonnet":{"utilization":28,"resets_at":"2026-08-20T12:00:00Z"}}"#
        .utf8)
    let limits = try #require(AnthropicOAuthUsageResponse.parse(data))
    #expect(limits.fiveHour?.utilization == 18)
    #expect(limits.sevenDay?.utilization == 51)
    #expect(limits.sevenDaySonnet?.utilization == 28)
  }

  @Test func keepsNewModelScopedWindowsWithoutAnAppUpdate() throws {
    let data = Data(
      #"{"five_hour":{"utilization":18},"nimbus_quill":{"utilization":7,"resets_at":null},"extra_usage":{"utilization":null}}"#
        .utf8)
    let limits = try #require(AnthropicOAuthUsageResponse.parse(data))

    #expect(limits.modelScoped.map(\.id) == ["nimbus_quill"])
    #expect(limits.modelScoped.first?.title == "Nimbus Quill")
    #expect(limits.modelScoped.first?.window.utilization == 7)
  }

  @Test func rejectsMissingCredentials() {
    #expect(throws: AnthropicOAuthUsageError.missingAccessToken) {
      try AnthropicOAuthCredentials.accessToken(in: Data(#"{"claudeAiOauth":{}}"#.utf8))
    }
  }
}
