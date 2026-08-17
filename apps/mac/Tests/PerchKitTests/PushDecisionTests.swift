import Foundation
import Testing

@testable import PerchKit

/// Disabled is disabled, regardless of how away or how blocking the event is.
@Test func disabledSettingsNeverPush() {
  var settings = PushSettings(enabled: false)
  #expect(
    !PushDecision.shouldPush(
      settings: settings, hasCredentials: true, kind: .approvalNeeded, isAway: true,
      sessionId: "s1",
      dedup: PushDedupState()))

  settings.enabled = true
  #expect(
    !PushDecision.shouldPush(
      settings: settings, hasCredentials: false, kind: .approvalNeeded, isAway: true,
      sessionId: "s1",
      dedup: PushDedupState()))
}

/// The one rule this whole function exists to enforce: nothing goes out while someone is
/// at the machine.
@Test func anActiveUserNeverGetsPushed() {
  let settings = PushSettings(enabled: true)
  #expect(
    !PushDecision.shouldPush(
      settings: settings, hasCredentials: true, kind: .approvalNeeded, isAway: false,
      sessionId: "s1",
      dedup: PushDedupState()))
}

/// Away, blocked, and configured — the case the feature exists for.
@Test func awayAndWaitingPushesOnce() {
  let settings = PushSettings(enabled: true)
  #expect(
    PushDecision.shouldPush(
      settings: settings, hasCredentials: true, kind: .approvalNeeded, isAway: true,
      sessionId: "s1",
      dedup: PushDedupState()))
}

/// A second hook call landing on the same still-open wait is not a new reason to buzz.
@Test func theSameEpisodeIsNotPushedTwice() {
  let settings = PushSettings(enabled: true)
  var dedup = PushDedupState()
  dedup.markPushed(for: "s1")
  #expect(
    !PushDecision.shouldPush(
      settings: settings, hasCredentials: true, kind: .approvalNeeded, isAway: true,
      sessionId: "s1",
      dedup: dedup))
}

/// Once the session stops waiting, the next block is a fresh episode and earns a push of
/// its own.
@Test func aNewEpisodeIsPushedAgain() {
  let settings = PushSettings(enabled: true)
  var dedup = PushDedupState()
  dedup.markPushed(for: "s1")
  dedup.endEpisode(for: "s1")
  #expect(
    PushDecision.shouldPush(
      settings: settings, hasCredentials: true, kind: .approvalNeeded, isAway: true,
      sessionId: "s1",
      dedup: dedup))
}

/// Missing Keychain credentials is "not configured", the same as disabled.
@Test func missingCredentialsNeverPushes() {
  let settings = PushSettings(enabled: true)
  #expect(
    !PushDecision.shouldPush(
      settings: settings, hasCredentials: false, kind: .approvalNeeded, isAway: true,
      sessionId: "s1",
      dedup: PushDedupState()))
}

/// Only the kinds the settings actually opted into are worth a buzz.
@Test func onlyConfiguredKindsPush() {
  let settings = PushSettings(enabled: true, pushedKinds: [.approvalNeeded])
  #expect(
    !PushDecision.shouldPush(
      settings: settings, hasCredentials: true, kind: .questionAsked, isAway: true, sessionId: "s1",
      dedup: PushDedupState()))
  #expect(
    PushDecision.shouldPush(
      settings: settings, hasCredentials: true, kind: .approvalNeeded, isAway: true,
      sessionId: "s1",
      dedup: PushDedupState()))
}

/// Away is either signal: the screen is not something to look at, or nobody has touched
/// the machine in a while.
@Test func awayIsScreenObscuredOrIdleLongEnough() {
  #expect(
    PushDecision.isAway(isScreenObscured: true, idleSeconds: 0, thresholdMinutes: 3))
  #expect(
    !PushDecision.isAway(isScreenObscured: false, idleSeconds: 60, thresholdMinutes: 3))
  #expect(
    PushDecision.isAway(isScreenObscured: false, idleSeconds: 181, thresholdMinutes: 3))
}

/// A threshold too short to survive glancing away, or a blank server, is a broken
/// configuration rather than a valid choice.
@Test func settingsAreSanitisedOnSave() {
  var settings = PushSettings(idleThresholdMinutes: 0)
  settings.server = "  "
  let sanitised = settings.sanitised
  #expect(sanitised.idleThresholdMinutes == 1)
  #expect(sanitised.server == PushSettings().server)
}

/// The server field is hand-edited; a trailing slash must not double up against the
/// `/push` the notifier appends.
@Test func aTrailingSlashOnTheServerIsTrimmed() {
  let settings = PushSettings(server: "https://bark.example.com/")
  #expect(settings.sanitised.server == "https://bark.example.com")
}

@Test func legacyNtfySettingsCannotSendToTheBarkTransport() {
  let settings = PushSettings(enabled: true, server: "https://ntfy.sh").sanitised
  #expect(!settings.enabled)
  #expect(settings.server == "https://api.day.app")
}

/// A corrupt or future-version `pushedKinds` entry must not disable the rest of the
/// settings — only the field it actually broke.
@Test func aBrokenFieldDoesNotDisableTheWholeStruct() throws {
  let json = #"{"enabled":true,"pushedKinds":["approvalNeeded","fromTheFuture"]}"#
  let decoded = try JSONDecoder().decode(PushSettings.self, from: Data(json.utf8))
  #expect(decoded.enabled)
  // The whole set falls back to the default rather than losing only the unknown case —
  // still an isolated failure, not one that reaches `enabled`.
  #expect(decoded.pushedKinds == PushSettings().pushedKinds)
}
