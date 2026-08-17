import Foundation

/// The settings that are neither about noise nor about what gets in: the shortcut, the
/// notch's own dimensions, how long a silent session survives.
///
/// Kept apart from `QuietSettings` because they change for different reasons — one is
/// "leave me alone", this is "fit my machine".
/// How much of each session the panel spells out.
///
/// Two densities rather than a pile of toggles. They control how much the collapsed strip
/// says; the expanded panel keeps the prompt and plan in either mode.
public enum PanelLayout: String, Codable, Sendable, CaseIterable {
  /// Project, title, and what it is doing. One line of chrome per session.
  case clean
  /// Everything: what you asked, and the plan it is working through.
  case detailed

  public var title: String {
    switch self {
    case .clean: return "Clean"
    case .detailed: return "Detailed"
    }
  }

  /// Expanded content is independent from the compact-strip density.
  public var showsPrompt: Bool { true }
  public var showsTasks: Bool { true }

  /// Detailed adds the current title/activity between the status sprites and count.
  public var showsCompactDetails: Bool { self == .detailed }
}

/// What language Perch speaks, which is not the same question as what language the Mac is
/// set to.
///
/// English is the default even on a French system. Perch is a panel over a CLI whose own
/// output, flags and error messages are in English, and a French label above an English
/// transcript reads worse than either language on its own. Someone who wants French can say
/// so — the translation is there — but nobody has to opt out of a language they did not pick.
public enum AppLanguage: String, Codable, Sendable, CaseIterable {
  case english = "en"
  case french = "fr"
  /// Whatever macOS asks for, which is what an app normally does.
  case system

  /// A language names itself: `Français` rather than `French`, whichever language the rest
  /// of the window happens to be in. Only `System` is a word about the setting, so only
  /// that one is translated.
  public var title: String {
    switch self {
    case .english: return "English"
    case .french: return "Français"
    case .system: return "System Language"
    }
  }

  /// What to put in `AppleLanguages`, or nil to leave the choice to macOS.
  public var localeIdentifiers: [String]? {
    self == .system ? nil : [rawValue]
  }
}

public enum UsageProvider: String, Codable, Sendable, CaseIterable {
  case automatic
  case claude
  case codex
}

public enum AutoReviewPolicy: String, Codable, Sendable, CaseIterable {
  case followFocus
  case alwaysSilent
  case alwaysShow
}

public enum DetectionPolicy: String, Codable, Sendable, CaseIterable {
  case automatic
  case enabled
  case disabled
}

public enum ChildCompletionTiming: String, Codable, Sendable, CaseIterable {
  case withMainReply
  case immediately
  case never
}

public enum FollowUpDelay: Int, Codable, Sendable, CaseIterable {
  case off = 0
  case fiveMinutes = 5
  case tenMinutes = 10
  case fifteenMinutes = 15
  case thirtyMinutes = 30
}

public struct RemoteHost: Codable, Sendable, Equatable, Identifiable {
  public var id: UUID
  public var name: String
  public var destination: String
  public var sshOptions: String
  public var manualConnectionOnly: Bool
  public var autoUpdateHooks: Bool
  public var remoteClaudeUsageRelayEnabled: Bool
  public var remoteCodexUsageProbeEnabled: Bool
  public var deployed: Bool
  public var lastDeployedAt: Date?
  public var lastDeployError: String?
  public var deployedHookVersion: Int?
  public var remoteCodexHookTrust: RemoteCodexHookTrustSnapshot
  public var additionalCodexConfigRoots: [String]

  public init(
    id: UUID = UUID(), name: String, destination: String,
    sshOptions: String = "", manualConnectionOnly: Bool = false,
    autoUpdateHooks: Bool = true, remoteClaudeUsageRelayEnabled: Bool = true,
    remoteCodexUsageProbeEnabled: Bool = false, deployed: Bool = false,
    lastDeployedAt: Date? = nil, lastDeployError: String? = nil,
    deployedHookVersion: Int? = nil,
    remoteCodexHookTrust: RemoteCodexHookTrustSnapshot = .init(),
    additionalCodexConfigRoots: [String] = []
  ) {
    self.id = id
    self.name = name
    self.destination = destination
    self.sshOptions = sshOptions
    self.manualConnectionOnly = manualConnectionOnly
    self.autoUpdateHooks = autoUpdateHooks
    self.remoteClaudeUsageRelayEnabled = remoteClaudeUsageRelayEnabled
    self.remoteCodexUsageProbeEnabled = remoteCodexUsageProbeEnabled
    self.deployed = deployed
    self.lastDeployedAt = lastDeployedAt
    self.lastDeployError = lastDeployError
    self.deployedHookVersion = deployedHookVersion
    self.remoteCodexHookTrust = remoteCodexHookTrust
    self.additionalCodexConfigRoots = additionalCodexConfigRoots
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, destination, sshOptions, manualConnectionOnly, autoUpdateHooks
    case remoteClaudeUsageRelayEnabled, remoteCodexUsageProbeEnabled
    case deployed, lastDeployedAt, lastDeployError, deployedHookVersion
    case remoteCodexHookTrust, additionalCodexConfigRoots
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try container.decode(String.self, forKey: .name)
    destination = try container.decode(String.self, forKey: .destination)
    sshOptions = try container.decodeIfPresent(String.self, forKey: .sshOptions) ?? ""
    manualConnectionOnly =
      try container.decodeIfPresent(Bool.self, forKey: .manualConnectionOnly) ?? false
    autoUpdateHooks = try container.decodeIfPresent(Bool.self, forKey: .autoUpdateHooks) ?? true
    remoteClaudeUsageRelayEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .remoteClaudeUsageRelayEnabled) ?? true
    remoteCodexUsageProbeEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .remoteCodexUsageProbeEnabled) ?? false
    deployed = try container.decodeIfPresent(Bool.self, forKey: .deployed) ?? false
    lastDeployedAt = try container.decodeIfPresent(Date.self, forKey: .lastDeployedAt)
    lastDeployError = try container.decodeIfPresent(String.self, forKey: .lastDeployError)
    deployedHookVersion = try container.decodeIfPresent(Int.self, forKey: .deployedHookVersion)
    remoteCodexHookTrust =
      try container.decodeIfPresent(RemoteCodexHookTrustSnapshot.self, forKey: .remoteCodexHookTrust)
      ?? .init()
    additionalCodexConfigRoots =
      try container.decodeIfPresent([String].self, forKey: .additionalCodexConfigRoots) ?? []
  }

  public func requiresHookDeployment(currentVersion: Int) -> Bool {
    autoUpdateHooks && (!deployed || deployedHookVersion != currentVersion)
  }
}

public struct CustomJumpRule: Codable, Sendable, Equatable, Identifiable {
  public var id: UUID
  public var terminal: String
  public var bundleId: String
  public var urlTemplate: String

  public init(
    id: UUID = UUID(), terminal: String, bundleId: String, urlTemplate: String
  ) {
    self.id = id
    self.terminal = terminal
    self.bundleId = bundleId
    self.urlTemplate = urlTemplate
  }
}

public struct Preferences: Codable, Sendable, Equatable {
  /// Which language the interface is in. Read once, at launch, before anything is drawn.
  public var language: AppLanguage

  /// Virtual key code for the switcher. `kVK_ANSI_P` by default.
  public var switcherKeyCode: UInt32
  /// Carbon modifier mask. Control + Option by default.
  public var switcherModifiers: UInt32
  public var switcherEnabled: Bool

  /// Points added to what macOS reports for the cutout. Zero means "trust the API",
  /// which is right on every Mac it has been measured on and wrong on some it has not.
  public var notchWidthAdjustment: Double
  public var notchHeightAdjustment: Double

  /// A session with no traffic for this long is treated as gone. Zero means never —
  /// which is correct for CLIs that always send `SessionEnd`, and a slow leak for the
  /// ones that do not.
  public var idleTimeout: TimeInterval

  /// Sessions launched by these apps never reach the panel. For background helpers that
  /// drive an agent without a terminal, where a directory or prompt rule cannot bite.
  public var blockedLaunchers: [String]

  /// Take pre-release builds. The beta feed is the release feed's neighbour rather than
  /// a separate service — one file to publish, one key to sign with.
  public var betaUpdates: Bool

  /// How much of each session a card spells out.
  public var layout: PanelLayout

  /// Show what is left rather than what is spent. The same number either way — but
  /// "12% left" and "88% used" are not the same sentence, and people are split on which
  /// one they read without thinking.
  public var showsRemainingQuota: Bool

  /// Reveal the notch when a quota window crosses this percentage. Zero turns it off.
  /// Ninety by default: late enough to be rare, early enough to still change what you
  /// do next.
  public var quotaWarningThreshold: Double

  /// Carry the plan beside the cutout while nothing is running.
  ///
  /// On by default. The state used to draw nothing at all — a Mac doing nothing looked
  /// like a Mac doing nothing — and that is a real position, kept one click away: the
  /// quota is still in the panel's header on every tab, one hover from the notch.
  public var restingQuota: Bool

  /// Come back on its own after a restart.
  ///
  /// On by default, which is unusual for a login item and right for this one: Perch has
  /// no Dock icon and no menu bar item, so an install that quietly stopped running after
  /// a reboot looks exactly like an install that works — until the notch stays empty
  /// through a whole session and you conclude the hooks broke.
  public var launchAtLogin: Bool

  /// Open the full island as soon as the pointer enters it.
  public var expandsOnHover: Bool
  /// Legacy persisted value retained for decoding compatibility. Hover is immediate.
  public var hoverDelay: TimeInterval
  /// Return to the compact island after the pointer leaves the panel.
  public var collapsesOnHoverExit: Bool
  /// Keep the hardware cutout bare when there is no live session.
  public var hidesWhenNoSessions: Bool
  /// Keep session cards informational; terminal switching remains available elsewhere.
  public var disablesSessionJump: Bool
  /// Upper bounds for the expanded island. The transparent host window remains fixed.
  public var panelMaximumWidth: Double
  public var panelMaximumHeight: Double
  public var hidesInFullscreen: Bool
  public var autoDisplayDuration: TimeInterval
  public var closesAutoDisplayOnOutsideClick: Bool
  public var contentFontSize: Double
  public var completionCardHeight: Double
  public var showsProjectName: Bool
  public var showsWorktree: Bool
  public var showsAIModel: Bool
  public var showsReasoningEffort: Bool
  public var showsTasks: Bool
  public var showsSubagents: Bool
  public var showsActivityDetails: Bool
  /// Localized display name, or nil for the display that owns the menu bar.
  public var targetDisplayName: String?
  public var showsUsageLimits: Bool
  public var preferredUsageProvider: UsageProvider
  public var showsResetCards: Bool
  public var automaticallyChecksForUpdates: Bool
  public var automaticallyInstallsUpdates: Bool
  public var showsUpdateIndicator: Bool
  public var memorySafetyRestart: Bool
  public var claudeAutoModeOverride: Bool
  public var ignoresClaudeApprovals: Bool
  public var codexAutoReviewPolicy: AutoReviewPolicy
  public var opensCodexThreadsInApp: Bool
  public var cursorYoloPolicy: DetectionPolicy
  public var disabledAgents: [Agent]
  public var automaticallyConfiguresAgents: Bool
  public var reverseSwitcherEnabled: Bool
  public var remoteHosts: [RemoteHost]
  public var remotePort: UInt16
  public var customJumpRules: [CustomJumpRule]
  public var childCompletionTiming: ChildCompletionTiming
  public var followUpDelay: FollowUpDelay
  public var followUpApprovals: Bool
  public var followUpCompletedTasks: Bool

  public init(
    switcherKeyCode: UInt32 = 5,  // kVK_ANSI_G
    switcherModifiers: UInt32 = 4096,  // controlKey
    switcherEnabled: Bool = true,
    notchWidthAdjustment: Double = 0,
    notchHeightAdjustment: Double = 0,
    idleTimeout: TimeInterval = 2 * 3_600,
    blockedLaunchers: [String] = [],
    betaUpdates: Bool = false,
    // Vibe's narrow/clean card is the fresh-install default. Detailed remains an
    // explicit choice in Display settings and is never inferred for an old file.
    layout: PanelLayout = .clean,
    showsRemainingQuota: Bool = false,
    quotaWarningThreshold: Double = 90,
    language: AppLanguage = .english,
    restingQuota: Bool = true,
    launchAtLogin: Bool = false,
    expandsOnHover: Bool = true,
    hoverDelay: TimeInterval = 0,
    collapsesOnHoverExit: Bool = true,
    hidesWhenNoSessions: Bool = false,
    disablesSessionJump: Bool = false,
    panelMaximumWidth: Double = 640,
    panelMaximumHeight: Double = 560,
    hidesInFullscreen: Bool = true,
    autoDisplayDuration: TimeInterval = 5,
    closesAutoDisplayOnOutsideClick: Bool = false,
    contentFontSize: Double = 11,
    completionCardHeight: Double = 90,
    showsProjectName: Bool = true,
    showsWorktree: Bool = true,
    showsAIModel: Bool = false,
    showsReasoningEffort: Bool = false,
    showsTasks: Bool = true,
    showsSubagents: Bool = true,
    showsActivityDetails: Bool = true,
    targetDisplayName: String? = nil,
    showsUsageLimits: Bool = true,
    preferredUsageProvider: UsageProvider = .automatic,
    showsResetCards: Bool = true,
    automaticallyChecksForUpdates: Bool = true,
    automaticallyInstallsUpdates: Bool = true,
    showsUpdateIndicator: Bool = true,
    memorySafetyRestart: Bool = false,
    claudeAutoModeOverride: Bool = false,
    ignoresClaudeApprovals: Bool = false,
    codexAutoReviewPolicy: AutoReviewPolicy = .followFocus,
    opensCodexThreadsInApp: Bool = false,
    cursorYoloPolicy: DetectionPolicy = .automatic,
    disabledAgents: [Agent] = [],
    automaticallyConfiguresAgents: Bool = true,
    reverseSwitcherEnabled: Bool = true,
    remoteHosts: [RemoteHost] = [],
    remotePort: UInt16 = 17_891,
    customJumpRules: [CustomJumpRule] = [],
    childCompletionTiming: ChildCompletionTiming = .withMainReply,
    followUpDelay: FollowUpDelay = .off,
    followUpApprovals: Bool = true,
    followUpCompletedTasks: Bool = false
  ) {
    self.language = language
    self.restingQuota = restingQuota
    self.launchAtLogin = launchAtLogin
    self.expandsOnHover = expandsOnHover
    self.hoverDelay = hoverDelay
    self.collapsesOnHoverExit = collapsesOnHoverExit
    self.hidesWhenNoSessions = hidesWhenNoSessions
    self.disablesSessionJump = disablesSessionJump
    self.panelMaximumWidth = panelMaximumWidth
    self.panelMaximumHeight = panelMaximumHeight
    self.hidesInFullscreen = hidesInFullscreen
    self.autoDisplayDuration = autoDisplayDuration
    self.closesAutoDisplayOnOutsideClick = closesAutoDisplayOnOutsideClick
    self.contentFontSize = contentFontSize
    self.completionCardHeight = completionCardHeight
    self.showsProjectName = showsProjectName
    self.showsWorktree = showsWorktree
    self.showsAIModel = showsAIModel
    self.showsReasoningEffort = showsReasoningEffort
    self.showsTasks = showsTasks
    self.showsSubagents = showsSubagents
    self.showsActivityDetails = showsActivityDetails
    self.targetDisplayName = targetDisplayName
    self.showsUsageLimits = showsUsageLimits
    self.preferredUsageProvider = preferredUsageProvider
    self.showsResetCards = showsResetCards
    self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    self.automaticallyInstallsUpdates = automaticallyInstallsUpdates
    self.showsUpdateIndicator = showsUpdateIndicator
    self.memorySafetyRestart = memorySafetyRestart
    self.claudeAutoModeOverride = claudeAutoModeOverride
    self.ignoresClaudeApprovals = ignoresClaudeApprovals
    self.codexAutoReviewPolicy = codexAutoReviewPolicy
    self.opensCodexThreadsInApp = opensCodexThreadsInApp
    self.cursorYoloPolicy = cursorYoloPolicy
    self.disabledAgents = disabledAgents
    self.automaticallyConfiguresAgents = automaticallyConfiguresAgents
    self.reverseSwitcherEnabled = reverseSwitcherEnabled
    self.remoteHosts = remoteHosts
    self.remotePort = remotePort
    self.customJumpRules = customJumpRules
    self.childCompletionTiming = childCompletionTiming
    self.followUpDelay = followUpDelay
    self.followUpApprovals = followUpApprovals
    self.followUpCompletedTasks = followUpCompletedTasks
    self.switcherKeyCode = switcherKeyCode
    self.switcherModifiers = switcherModifiers
    self.switcherEnabled = switcherEnabled
    self.notchWidthAdjustment = notchWidthAdjustment
    self.notchHeightAdjustment = notchHeightAdjustment
    self.idleTimeout = idleTimeout
    self.blockedLaunchers = blockedLaunchers
    self.betaUpdates = betaUpdates
    self.layout = layout
    self.showsRemainingQuota = showsRemainingQuota
    self.quotaWarningThreshold = quotaWarningThreshold
  }

  /// Tolerant of keys added later: a file written by an older build must not reset the
  /// settings it did know about.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = Preferences()
    switcherKeyCode =
      try container.decodeIfPresent(UInt32.self, forKey: .switcherKeyCode)
      ?? defaults.switcherKeyCode
    switcherModifiers =
      try container.decodeIfPresent(UInt32.self, forKey: .switcherModifiers)
      ?? defaults.switcherModifiers
    // The original Perch default was ⌃⌥P. It was never Vibe-compatible and existing
    // installs would otherwise keep it forever after the default changed to ⌃G.
    if switcherKeyCode == 35, switcherModifiers == (4096 | 2048) {
      switcherKeyCode = defaults.switcherKeyCode
      switcherModifiers = defaults.switcherModifiers
    }
    switcherEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .switcherEnabled) ?? true
    notchWidthAdjustment =
      try container.decodeIfPresent(Double.self, forKey: .notchWidthAdjustment) ?? 0
    notchHeightAdjustment =
      try container.decodeIfPresent(Double.self, forKey: .notchHeightAdjustment) ?? 0
    idleTimeout =
      try container.decodeIfPresent(TimeInterval.self, forKey: .idleTimeout)
      ?? defaults.idleTimeout
    blockedLaunchers =
      try container.decodeIfPresent([String].self, forKey: .blockedLaunchers) ?? []
    betaUpdates = try container.decodeIfPresent(Bool.self, forKey: .betaUpdates) ?? false
    layout =
      try container.decodeIfPresent(PanelLayout.self, forKey: .layout) ?? defaults.layout
    showsRemainingQuota =
      try container.decodeIfPresent(Bool.self, forKey: .showsRemainingQuota) ?? false
    quotaWarningThreshold =
      try container.decodeIfPresent(Double.self, forKey: .quotaWarningThreshold)
      ?? defaults.quotaWarningThreshold
    // A file written before this setting existed means "never chose", which is English —
    // the same thing a fresh install gets, rather than a silent switch to the system
    // language for the people who already had Perch.
    language =
      try container.decodeIfPresent(AppLanguage.self, forKey: .language)
      ?? defaults.language
    restingQuota =
      try container.decodeIfPresent(Bool.self, forKey: .restingQuota)
      ?? defaults.restingQuota
    // A file written before this setting existed reads as "on", same as a fresh
    // install: someone already running Perch is exactly who wants it back after a
    // reboot, and the toggle is one pane away for anyone who does not.
    launchAtLogin =
      try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin)
      ?? defaults.launchAtLogin
    expandsOnHover =
      try container.decodeIfPresent(Bool.self, forKey: .expandsOnHover)
      ?? defaults.expandsOnHover
    hoverDelay =
      try container.decodeIfPresent(TimeInterval.self, forKey: .hoverDelay)
      ?? defaults.hoverDelay
    collapsesOnHoverExit =
      try container.decodeIfPresent(Bool.self, forKey: .collapsesOnHoverExit)
      ?? defaults.collapsesOnHoverExit
    hidesWhenNoSessions =
      try container.decodeIfPresent(Bool.self, forKey: .hidesWhenNoSessions)
      ?? defaults.hidesWhenNoSessions
    disablesSessionJump =
      try container.decodeIfPresent(Bool.self, forKey: .disablesSessionJump)
      ?? defaults.disablesSessionJump
    panelMaximumWidth =
      try container.decodeIfPresent(Double.self, forKey: .panelMaximumWidth)
      ?? defaults.panelMaximumWidth
    panelMaximumHeight =
      try container.decodeIfPresent(Double.self, forKey: .panelMaximumHeight)
      ?? defaults.panelMaximumHeight
    hidesInFullscreen =
      try container.decodeIfPresent(Bool.self, forKey: .hidesInFullscreen)
      ?? defaults.hidesInFullscreen
    autoDisplayDuration =
      try container.decodeIfPresent(TimeInterval.self, forKey: .autoDisplayDuration)
      ?? defaults.autoDisplayDuration
    closesAutoDisplayOnOutsideClick =
      try container.decodeIfPresent(Bool.self, forKey: .closesAutoDisplayOnOutsideClick)
      ?? defaults.closesAutoDisplayOnOutsideClick
    contentFontSize =
      try container.decodeIfPresent(Double.self, forKey: .contentFontSize)
      ?? defaults.contentFontSize
    completionCardHeight =
      try container.decodeIfPresent(Double.self, forKey: .completionCardHeight)
      ?? defaults.completionCardHeight
    showsProjectName =
      try container.decodeIfPresent(Bool.self, forKey: .showsProjectName)
      ?? defaults.showsProjectName
    showsWorktree =
      try container.decodeIfPresent(Bool.self, forKey: .showsWorktree)
      ?? defaults.showsWorktree
    showsAIModel =
      try container.decodeIfPresent(Bool.self, forKey: .showsAIModel)
      ?? defaults.showsAIModel
    showsReasoningEffort =
      try container.decodeIfPresent(Bool.self, forKey: .showsReasoningEffort)
      ?? defaults.showsReasoningEffort
    showsTasks =
      try container.decodeIfPresent(Bool.self, forKey: .showsTasks)
      ?? defaults.showsTasks
    showsSubagents =
      try container.decodeIfPresent(Bool.self, forKey: .showsSubagents)
      ?? defaults.showsSubagents
    showsActivityDetails =
      try container.decodeIfPresent(Bool.self, forKey: .showsActivityDetails)
      ?? defaults.showsActivityDetails
    targetDisplayName = try container.decodeIfPresent(String.self, forKey: .targetDisplayName)
    showsUsageLimits =
      try container.decodeIfPresent(Bool.self, forKey: .showsUsageLimits)
      ?? defaults.showsUsageLimits
    preferredUsageProvider =
      try container.decodeIfPresent(UsageProvider.self, forKey: .preferredUsageProvider)
      ?? defaults.preferredUsageProvider
    showsResetCards =
      try container.decodeIfPresent(Bool.self, forKey: .showsResetCards)
      ?? defaults.showsResetCards
    automaticallyChecksForUpdates =
      try container.decodeIfPresent(Bool.self, forKey: .automaticallyChecksForUpdates)
      ?? defaults.automaticallyChecksForUpdates
    automaticallyInstallsUpdates =
      try container.decodeIfPresent(Bool.self, forKey: .automaticallyInstallsUpdates)
      ?? defaults.automaticallyInstallsUpdates
    showsUpdateIndicator =
      try container.decodeIfPresent(Bool.self, forKey: .showsUpdateIndicator)
      ?? defaults.showsUpdateIndicator
    memorySafetyRestart =
      try container.decodeIfPresent(Bool.self, forKey: .memorySafetyRestart)
      ?? defaults.memorySafetyRestart
    claudeAutoModeOverride =
      try container.decodeIfPresent(Bool.self, forKey: .claudeAutoModeOverride)
      ?? defaults.claudeAutoModeOverride
    ignoresClaudeApprovals =
      try container.decodeIfPresent(Bool.self, forKey: .ignoresClaudeApprovals)
      ?? defaults.ignoresClaudeApprovals
    codexAutoReviewPolicy =
      try container.decodeIfPresent(AutoReviewPolicy.self, forKey: .codexAutoReviewPolicy)
      ?? defaults.codexAutoReviewPolicy
    opensCodexThreadsInApp =
      try container.decodeIfPresent(Bool.self, forKey: .opensCodexThreadsInApp)
      ?? defaults.opensCodexThreadsInApp
    cursorYoloPolicy =
      try container.decodeIfPresent(DetectionPolicy.self, forKey: .cursorYoloPolicy)
      ?? defaults.cursorYoloPolicy
    disabledAgents =
      try container.decodeIfPresent([Agent].self, forKey: .disabledAgents)
      ?? defaults.disabledAgents
    automaticallyConfiguresAgents =
      try container.decodeIfPresent(Bool.self, forKey: .automaticallyConfiguresAgents)
      ?? defaults.automaticallyConfiguresAgents
    reverseSwitcherEnabled =
      try container.decodeIfPresent(Bool.self, forKey: .reverseSwitcherEnabled)
      ?? defaults.reverseSwitcherEnabled
    remoteHosts =
      try container.decodeIfPresent([RemoteHost].self, forKey: .remoteHosts)
      ?? defaults.remoteHosts
    remotePort =
      try container.decodeIfPresent(UInt16.self, forKey: .remotePort)
      ?? defaults.remotePort
    customJumpRules =
      try container.decodeIfPresent([CustomJumpRule].self, forKey: .customJumpRules)
      ?? defaults.customJumpRules
    childCompletionTiming =
      try container.decodeIfPresent(ChildCompletionTiming.self, forKey: .childCompletionTiming)
      ?? defaults.childCompletionTiming
    followUpDelay =
      try container.decodeIfPresent(FollowUpDelay.self, forKey: .followUpDelay)
      ?? defaults.followUpDelay
    followUpApprovals =
      try container.decodeIfPresent(Bool.self, forKey: .followUpApprovals)
      ?? defaults.followUpApprovals
    followUpCompletedTasks =
      try container.decodeIfPresent(Bool.self, forKey: .followUpCompletedTasks)
      ?? defaults.followUpCompletedTasks
  }

  /// Clamped rather than validated: a tuning slider should never be able to make the
  /// panel unreachable, and a timeout of ten seconds would hide everything.
  public var sanitised: Preferences {
    var copy = self
    copy.notchWidthAdjustment = min(max(notchWidthAdjustment, -60), 60)
    copy.notchHeightAdjustment = min(max(notchHeightAdjustment, -12), 24)
    if idleTimeout != 0 { copy.idleTimeout = min(max(idleTimeout, 60), 24 * 3_600) }
    // Zero is off. Anything else lands in a range where the warning still leaves room
    // to act: a threshold of 5% would fire on a Monday morning and mean nothing.
    if quotaWarningThreshold != 0 {
      copy.quotaWarningThreshold = min(max(quotaWarningThreshold, 50), 100)
    }
    copy.hoverDelay = 0
    copy.panelMaximumWidth = min(max(panelMaximumWidth, 440), 680)
    copy.panelMaximumHeight = min(max(panelMaximumHeight, 360), 620)
    copy.autoDisplayDuration = min(max(autoDisplayDuration, 1), 15)
    copy.contentFontSize = min(max(contentFontSize, 9), 13)
    copy.completionCardHeight = min(max(completionCardHeight, 70), 140)
    return copy
  }

  public func blocks(launcher bundleId: String?) -> Bool {
    guard let bundleId, !bundleId.isEmpty else { return false }
    return blockedLaunchers.contains { $0.caseInsensitiveCompare(bundleId) == .orderedSame }
  }
}

extension Preferences {
  public static var defaultURL: URL {
    URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent(".perch/preferences.json")
  }

  public static func load(from url: URL = defaultURL) -> Preferences {
    guard let data = try? Data(contentsOf: url),
      let decoded = try? JSONDecoder().decode(Preferences.self, from: data)
    else { return Preferences() }
    return decoded.sanitised
  }

  public func save(to url: URL = defaultURL) {
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(sanitised).write(to: url, options: .atomic)
    } catch {
      NSLog("perch: could not save preferences: \(error)")
    }
  }
}

/// Renders a Carbon key code and modifier mask the way a menu would.
public enum ShortcutFormatter {
  private static let names: [UInt32: String] = [
    0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
    38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
    15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
    49: "Space", 36: "Return", 48: "Tab", 53: "Escape", 50: "`",
  ]

  /// Carbon's masks, which are not the same numbers as AppKit's.
  public static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
    var result = ""
    if modifiers & 4096 != 0 { result += "⌃" }
    if modifiers & 2048 != 0 { result += "⌥" }
    if modifiers & 512 != 0 { result += "⇧" }
    if modifiers & 256 != 0 { result += "⌘" }
    result += names[keyCode] ?? "key \(keyCode)"
    return result
  }

  /// AppKit reports modifiers with different bits than Carbon expects, so a recorder has
  /// to translate before anything is registered.
  public static func carbonModifiers(fromCocoa flags: UInt) -> UInt32 {
    var result: UInt32 = 0
    if flags & (1 << 18) != 0 { result |= 4096 }  // control
    if flags & (1 << 19) != 0 { result |= 2048 }  // option
    if flags & (1 << 17) != 0 { result |= 512 }  // shift
    if flags & (1 << 20) != 0 { result |= 256 }  // command
    return result
  }

  /// A shortcut with no modifier would swallow the letter everywhere.
  public static func isUsable(keyCode: UInt32, modifiers: UInt32) -> Bool {
    modifiers & (4096 | 2048 | 256) != 0 && names[keyCode] != nil
  }
}
