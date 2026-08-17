import Foundation
import Testing

@testable import PerchKit

private var calendar: Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  return calendar
}

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
  calendar.date(from: DateComponents(year: 2026, month: 7, day: 25, hour: hour, minute: minute))!
}

/// The case that matters most: a permission card opening mid-demo puts a stranger's
/// command on a projector.
@Test func screenSharingSilencesEvenBlockingRequests() {
  let scene = Scene(isScreenShared: true)
  let decision = InterruptionPolicy.decide(
    .approvalNeeded, scene: scene, settings: QuietSettings(whenScreenShared: true))

  #expect(decision == .quiet)
  #expect(
    !InterruptionPolicy.playsSound(
      .approvalNeeded, scene: scene, settings: QuietSettings(whenScreenShared: true)))
}

@Test func aLockedScreenAndFocusModeAlsoSilence() {
  #expect(
    InterruptionPolicy.decide(
      .approvalNeeded, scene: Scene(isScreenObscured: true),
      settings: QuietSettings(whenScreenObscured: true))
      == .quiet)
  #expect(
    InterruptionPolicy.decide(
      .approvalNeeded, scene: Scene(isFocusActive: true),
      settings: QuietSettings(duringFocus: true))
      == .quiet)
}

/// Each quiet scene can be enabled individually.
@Test func silencingIsOptInPerScene() {
  var settings = QuietSettings()
  settings.whenScreenShared = true

  #expect(
    InterruptionPolicy.decide(
      .approvalNeeded, scene: Scene(isScreenShared: true), settings: settings) == .quiet)
}

/// Nothing in the way: a blocked session always earns the panel.
@Test func blockingRequestsTakeTheScreenByDefault() {
  #expect(
    InterruptionPolicy.decide(.approvalNeeded, scene: Scene(), settings: QuietSettings())
      == .full)
  #expect(
    InterruptionPolicy.decide(.questionAsked, scene: Scene(), settings: QuietSettings())
      == .full)
}

/// Vibe shows completed turns by default, and the setting can reduce them to a glow.
@Test func completionsOpenUnlessSilenced() {
  #expect(
    InterruptionPolicy.decide(.taskComplete, scene: Scene(), settings: QuietSettings())
      == .full)

  var quiet = QuietSettings()
  quiet.autoExpandOnComplete = false
  #expect(
    InterruptionPolicy.decide(.taskComplete, scene: Scene(), settings: quiet) == .quiet)
}

/// Heads-down mutes the chatter to a dot but must never hold a blocked session hostage.
@Test func manualQuietMutesChatterButNotApprovals() {
  let heads = QuietSettings(manualQuiet: true)

  // Non-blocking drops to a dot, even the ones that would otherwise take the screen.
  #expect(
    InterruptionPolicy.decide(.taskError, scene: Scene(), settings: heads) == .quiet)
  #expect(
    InterruptionPolicy.decide(
      .taskComplete, scene: Scene(),
      settings: QuietSettings(autoExpandOnComplete: true, manualQuiet: true)) == .quiet)

  // Blocking still earns the panel — being muted is not being stuck.
  #expect(
    InterruptionPolicy.decide(.approvalNeeded, scene: Scene(), settings: heads) == .full)
  #expect(
    InterruptionPolicy.decide(.questionAsked, scene: Scene(), settings: heads) == .full)
}

/// Heads-down also silences Notification Center, or "quiet" would still bark completions.
@Test func manualQuietSilencesNotificationsToo() {
  #expect(
    !InterruptionPolicy.notifies(
      .taskComplete, scene: anywhere, settings: QuietSettings(manualQuiet: true),
      host: "com.googlecode.iterm2"))
}

/// A `quiet.json` written before heads-down existed must still decode, defaulting off.
@Test func manualQuietDefaultsOffForOlderSettings() throws {
  let raw = #"{"duringFocus": true}"#.data(using: .utf8)!
  let settings = try JSONDecoder().decode(QuietSettings.self, from: raw)
  #expect(!settings.manualQuiet)
}

/// `22:00 → 07:00` is a real range. Agents running overnight is the whole use case.
@Test func quietHoursCrossMidnight() {
  let night = QuietHours(start: 22 * 60, end: 7 * 60)

  #expect(night.contains(at(23), calendar: calendar))
  #expect(night.contains(at(2), calendar: calendar))
  #expect(night.contains(at(22, 0), calendar: calendar))
  #expect(!night.contains(at(7, 0), calendar: calendar))
  #expect(!night.contains(at(12), calendar: calendar))
}

@Test func quietHoursWithinOneDayAreOrdinary() {
  let lunch = QuietHours(start: 12 * 60, end: 14 * 60)

  #expect(lunch.contains(at(13), calendar: calendar))
  #expect(!lunch.contains(at(11, 59), calendar: calendar))
  #expect(!lunch.contains(at(14), calendar: calendar))
}

/// An empty range must not silence the whole day.
@Test func anEmptyRangeSilencesNothing() {
  let empty = QuietHours(start: 9 * 60, end: 9 * 60)
  #expect(!empty.contains(at(9), calendar: calendar))
  #expect(!empty.contains(at(3), calendar: calendar))
}

@Test func quietHoursSilenceEvenApprovals() {
  var settings = QuietSettings()
  settings.quietHours = QuietHours(start: 22 * 60, end: 7 * 60)

  #expect(
    InterruptionPolicy.decide(
      .approvalNeeded, scene: Scene(), settings: settings, at: at(23),
      calendar: calendar) == .quiet)
  #expect(
    InterruptionPolicy.decide(
      .approvalNeeded, scene: Scene(), settings: settings, at: at(10),
      calendar: calendar) == .full)
}

@Test func soundCanBeOffWithoutChangingWhatIsShown() {
  var settings = QuietSettings()
  settings.soundEnabled = false

  #expect(
    InterruptionPolicy.decide(.approvalNeeded, scene: Scene(), settings: settings) == .full)
  #expect(!InterruptionPolicy.playsSound(.approvalNeeded, scene: Scene(), settings: settings))
}

/// You are already looking at the terminal that is asking. Taking the screen to tell you
/// what is on it would be a step backwards.
@Test func aFocusedHostSuppressesItsOwnRequests() {
  let scene = Scene(frontmostBundleId: "com.mitchellh.ghostty")

  #expect(
    InterruptionPolicy.decide(
      .approvalNeeded, scene: scene, settings: QuietSettings(),
      host: "com.mitchellh.ghostty") == .quiet)

  // A different terminal's request still earns the panel.
  #expect(
    InterruptionPolicy.decide(
      .approvalNeeded, scene: scene, settings: QuietSettings(),
      host: "com.googlecode.iterm2") == .full)

  // And so does one whose host we could not identify.
  #expect(
    InterruptionPolicy.decide(
      .approvalNeeded, scene: scene, settings: QuietSettings(), host: nil) == .full)
}

@Test func smartSuppressionCanBeTurnedOff() {
  var settings = QuietSettings()
  settings.smartSuppression = false

  #expect(
    InterruptionPolicy.decide(
      .approvalNeeded, scene: Scene(frontmostBundleId: "x"), settings: settings,
      host: "x") == .full)
}

/// A `quiet.json` written before smart suppression existed must still decode.
@Test func settingsWrittenByAnOlderVersionStillDecode() throws {
  let raw = #"{"duringFocus": false, "soundEnabled": false}"#.data(using: .utf8)!
  let settings = try JSONDecoder().decode(QuietSettings.self, from: raw)

  #expect(!settings.duringFocus)
  #expect(!settings.soundEnabled)
  // Absent keys take the current Vibe-compatible defaults.
  #expect(!settings.whenScreenShared)
  #expect(settings.smartSuppression)
}

@Test func onlyBlockingKindsAreMarkedAsSuch() {
  let blocking = InterruptionKind.allCases.filter(\.isBlocking)
  #expect(Set(blocking) == [.approvalNeeded, .questionAsked])
}

// MARK: - Notifications

private let anywhere = Scene(frontmostBundleId: "com.apple.finder")

/// The case the notification exists for: a turn ends while you are in another app, and the
/// panel chose not to take the screen. The panel decision and this one are deliberately
/// different — `.quiet` there does not mean silent everywhere.
@Test func aFinishedTurnElsewhereIsWorthANotification() {
  let settings = QuietSettings(autoExpandOnComplete: false)
  #expect(
    InterruptionPolicy.decide(
      .taskComplete, scene: anywhere, settings: settings, host: "com.googlecode.iterm2")
      == .quiet)
  #expect(
    InterruptionPolicy.notifies(
      .taskComplete, scene: anywhere, settings: settings, host: "com.googlecode.iterm2"))
}

/// You are already looking at the terminal that finished. Telling you about it is the
/// definition of noise.
@Test func noNotificationForTheTerminalYouAreLookingAt() {
  let scene = Scene(frontmostBundleId: "com.googlecode.iterm2")
  #expect(
    !InterruptionPolicy.notifies(
      .taskComplete, scene: scene, settings: QuietSettings(),
      host: "com.googlecode.iterm2"))
}

/// A quiet scene silences everything, and a notification banner during a screen share is
/// exactly the kind of thing quiet scenes exist to stop.
@Test func quietScenesAndQuietHoursAlsoSilenceNotifications() {
  let shared = Scene(isScreenShared: true, frontmostBundleId: "com.apple.finder")
  #expect(
    !InterruptionPolicy.notifies(
      .taskComplete, scene: shared, settings: QuietSettings(whenScreenShared: true)))

  let overnight = QuietSettings(quietHours: QuietHours(start: 22 * 60, end: 7 * 60))
  let night = Date(timeIntervalSince1970: 1_700_000_000)
  let calendar = Calendar(identifier: .gregorian)
  var atOne = DateComponents()
  atOne.year = 2026
  atOne.month = 1
  atOne.day = 5
  atOne.hour = 1
  let oneAM = calendar.date(from: atOne) ?? night
  #expect(
    !InterruptionPolicy.notifies(
      .taskComplete, scene: anywhere, settings: overnight, at: oneAM, calendar: calendar))
}

/// An approval owns the panel. A notification racing it would be a second place to answer
/// the same question, and the answer would be in only one of them.
@Test func blockingKindsAreNeverNotified() {
  #expect(!InterruptionPolicy.notifies(.approvalNeeded, scene: anywhere, settings: QuietSettings()))
  #expect(!InterruptionPolicy.notifies(.questionAsked, scene: anywhere, settings: QuietSettings()))
}

@Test func theNotificationSettingTurnsItOff() {
  #expect(
    !InterruptionPolicy.notifies(
      .taskComplete, scene: anywhere, settings: QuietSettings(notifiesOnComplete: false)))
}
