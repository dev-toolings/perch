import Foundation
import Testing

@testable import PerchKit

/// Disabled is disabled, regardless of how away or how blocking the event is.
@Test func disabledSettingsNeverPush() {
    var settings = PushSettings(enabled: false, topic: "me")
    #expect(
        !PushDecision.shouldPush(
            settings: settings, kind: .approvalNeeded, isAway: true, sessionId: "s1",
            dedup: PushDedupState()))

    settings.enabled = true
    settings.topic = ""
    #expect(
        !PushDecision.shouldPush(
            settings: settings, kind: .approvalNeeded, isAway: true, sessionId: "s1",
            dedup: PushDedupState()))
}

/// The one rule this whole function exists to enforce: nothing goes out while someone is
/// at the machine.
@Test func anActiveUserNeverGetsPushed() {
    let settings = PushSettings(enabled: true, topic: "me")
    #expect(
        !PushDecision.shouldPush(
            settings: settings, kind: .approvalNeeded, isAway: false, sessionId: "s1",
            dedup: PushDedupState()))
}

/// Away, blocked, and configured — the case the feature exists for.
@Test func awayAndWaitingPushesOnce() {
    let settings = PushSettings(enabled: true, topic: "me")
    #expect(
        PushDecision.shouldPush(
            settings: settings, kind: .approvalNeeded, isAway: true, sessionId: "s1",
            dedup: PushDedupState()))
}

/// A second hook call landing on the same still-open wait is not a new reason to buzz.
@Test func theSameEpisodeIsNotPushedTwice() {
    let settings = PushSettings(enabled: true, topic: "me")
    var dedup = PushDedupState()
    dedup.markPushed(for: "s1")
    #expect(
        !PushDecision.shouldPush(
            settings: settings, kind: .approvalNeeded, isAway: true, sessionId: "s1",
            dedup: dedup))
}

/// Once the session stops waiting, the next block is a fresh episode and earns a push of
/// its own.
@Test func aNewEpisodeIsPushedAgain() {
    let settings = PushSettings(enabled: true, topic: "me")
    var dedup = PushDedupState()
    dedup.markPushed(for: "s1")
    dedup.endEpisode(for: "s1")
    #expect(
        PushDecision.shouldPush(
            settings: settings, kind: .approvalNeeded, isAway: true, sessionId: "s1",
            dedup: dedup))
}

/// A blank topic is "not configured", the same as disabled — there is nowhere to publish.
@Test func anEmptyTopicNeverPushes() {
    let settings = PushSettings(enabled: true, topic: "   ")
    #expect(
        !PushDecision.shouldPush(
            settings: settings, kind: .approvalNeeded, isAway: true, sessionId: "s1",
            dedup: PushDedupState()))
}

/// Only the kinds the settings actually opted into are worth a buzz.
@Test func onlyConfiguredKindsPush() {
    let settings = PushSettings(enabled: true, topic: "me", pushedKinds: [.approvalNeeded])
    #expect(
        !PushDecision.shouldPush(
            settings: settings, kind: .questionAsked, isAway: true, sessionId: "s1",
            dedup: PushDedupState()))
    #expect(
        PushDecision.shouldPush(
            settings: settings, kind: .approvalNeeded, isAway: true, sessionId: "s1",
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
/// `/<topic>` the notifier appends.
@Test func aTrailingSlashOnTheServerIsTrimmed() {
    let settings = PushSettings(server: "https://ntfy.example.com/")
    #expect(settings.sanitised.server == "https://ntfy.example.com")
}

/// A topic with a stray space or slash addresses a *different* URL once escaped — the
/// person reading the settings pane would never know their push went somewhere else.
@Test func aTopicWithDisallowedCharactersIsStripped() {
    let settings = PushSettings(topic: " my topic/with-slash ")
    #expect(settings.sanitised.topic == "mytopicwith-slash")
}

/// A corrupt or future-version `pushedKinds` entry must not disable the rest of the
/// settings — only the field it actually broke.
@Test func aBrokenFieldDoesNotDisableTheWholeStruct() throws {
    let json = #"{"enabled":true,"topic":"me","pushedKinds":["approvalNeeded","fromTheFuture"]}"#
    let decoded = try JSONDecoder().decode(PushSettings.self, from: Data(json.utf8))
    #expect(decoded.enabled)
    #expect(decoded.topic == "me")
    // The whole set falls back to the default rather than losing only the unknown case —
    // still an isolated failure, not one that reaches `enabled` or `topic`.
    #expect(decoded.pushedKinds == PushSettings().pushedKinds)
}
