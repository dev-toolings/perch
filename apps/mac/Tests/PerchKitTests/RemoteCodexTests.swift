import Foundation
import Testing

@testable import PerchKit

@Suite("Remote Codex configuration")
struct RemoteCodexTests {
  @Test func rootSetupMergesDiscoveryAndSavedPathsWithoutDuplicates() {
    let model = RemoteCodexRootSetupModel(
      discovered: [
        .init(path: "/srv/work/.codex/", source: .paperclip),
        .init(path: "/srv/work/.codex", source: .manual),
      ],
      previouslySelected: ["/opt/codex", "/srv/work/.codex"])

    #expect(model.rows.map(\.path) == ["/srv/work/.codex", "/opt/codex", "~/.codex"])
    #expect(model.selectedPaths == ["/srv/work/.codex", "/opt/codex"])
  }

  @Test func manualRootsMustBeAbsoluteRemotePaths() {
    var model = RemoteCodexRootSetupModel(discovered: [])

    let rejected = model.addManualPath("relative/.codex")
    let accepted = model.addManualPath(" /workspace/.codex/ ")
    #expect(!rejected)
    #expect(accepted)
    #expect(model.selectedAdditionalRoots == ["/workspace/.codex"])
  }

  @Test func defaultCodexHomeIsNotPersistedAsAnAdditionalRoot() {
    var model = RemoteCodexRootSetupModel(discovered: [])
    model.toggle("~/.codex")

    #expect(model.selectedPaths == ["~/.codex"])
    #expect(model.selectedAdditionalRoots.isEmpty)
  }

  @Test func legacyRemoteHostsStartWithUnverifiedCodexTrust() throws {
    let raw = Data(#"{"name":"gpu","destination":"dev@example.test"}"#.utf8)
    let host = try JSONDecoder().decode(RemoteHost.self, from: raw)

    #expect(host.remoteCodexHookTrust == .init())
  }

  @Test func remoteTrustAndRootsRoundTrip() throws {
    let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let original = RemoteHost(
      name: "gpu", destination: "dev@example.test",
      remoteCodexHookTrust: .init(state: .trusted, lastCheckedAt: checkedAt),
      additionalCodexConfigRoots: ["/srv/project/.codex"])

    let decoded = try JSONDecoder().decode(
      RemoteHost.self, from: JSONEncoder().encode(original))

    #expect(decoded == original)
  }

  @Test func remoteHookTrustUsesCodexAppServersOwnStatuses() throws {
    func state(
      _ status: String,
      command: String = "/home/me/.perch-remote/perch-remote-hook.sh Stop --source codex"
    ) throws -> RemoteCodexHookTrustState {
      let object: [String: Any] = [
        "data": [[
          "errors": [], "warnings": [],
          "hooks": [[
            "command": command, "sourcePath": "/home/me/.codex/hooks.json",
            "trustStatus": status,
          ]],
        ]]
      ]
      let response = try JSONDecoder().decode(
        RemoteCodexHooksListResponse.self,
        from: JSONSerialization.data(withJSONObject: object))
      return RemoteCodexHookTrustEvaluator.evaluate(response)
    }

    #expect(try state("trusted") == .trusted)
    #expect(try state("managed") == .trusted)
    #expect(try state("untrusted") == .needsManualTrust)
    #expect(try state("modified") == .needsManualTrust)
    #expect(try state("future-status") == .unverified)
    #expect(try state("trusted", command: "/usr/bin/foreign-hook") == .unverified)
  }

  @Test func remoteHookTrustRefusesAResponseWithErrors() throws {
    let object: [String: Any] = [
      "data": [[
        "errors": [["message": "bad config", "path": "/tmp/hooks.json"]],
        "warnings": [],
        "hooks": [[
          "command": "perch-remote-hook Stop", "sourcePath": "/tmp/hooks.json",
          "trustStatus": "trusted",
        ]],
      ]]
    ]
    let response = try JSONDecoder().decode(
      RemoteCodexHooksListResponse.self,
      from: JSONSerialization.data(withJSONObject: object))
    #expect(RemoteCodexHookTrustEvaluator.evaluate(response) == .unverified)
  }

  @Test func remoteRateLimitsPreferTheNamedMultiBucketSnapshot() throws {
    let raw = Data(#"""
    {
      "rateLimits":{"limitId":"codex","primary":{"usedPercent":90,"windowDurationMins":10080,"resetsAt":1787196751}},
      "rateLimitsByLimitId":{
        "codex":{"limitId":"codex","limitName":null,"primary":{"usedPercent":90,"windowDurationMins":10080,"resetsAt":1787196751}},
        "spark":{"limitId":"spark","limitName":"Codex Spark","primary":{"usedPercent":9,"windowDurationMins":10080,"resetsAt":1787324312}}
      }
    }
    """#.utf8)
    let response = try JSONDecoder().decode(RemoteCodexRateLimitsResponse.self, from: raw)
    let limits = try #require(
      RemoteCodexRateLimitsEvaluator.evaluate(response, rootLabel: "~/.codex"))

    #expect(limits.windows.map(\.title) == ["~/.codex · 7d", "~/.codex · Codex Spark"])
    #expect(limits.windows.map(\.window.utilization) == [90, 9])
  }

  @Test func remoteRateLimitsFallBackToTheHistoricalBucket() throws {
    let raw = Data(#"""
    {
      "rateLimits":{"limitId":"codex","primary":{"usedPercent":42,"windowDurationMins":300,"resetsAt":null}},
      "rateLimitsByLimitId":null
    }
    """#.utf8)
    let response = try JSONDecoder().decode(RemoteCodexRateLimitsResponse.self, from: raw)
    let limits = try #require(RemoteCodexRateLimitsEvaluator.evaluate(response))

    #expect(limits.windows.map(\.title) == ["5h"])
    #expect(limits.windows.first?.window.utilization == 42)
  }
}
