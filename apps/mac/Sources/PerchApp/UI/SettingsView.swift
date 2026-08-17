import AppKit
import CoreImage.CIFilterBuiltins
import PerchKit
import SwiftUI

/// Everything Perch can be told, in one window.
///
/// Until now the quiet scenes, the admission filters and the sounds lived in JSON files
/// under `~/.perch`, which is fine for a tool you wrote and useless for one you install.
struct SettingsView: View {
  let model: AppModel

  enum Pane: String, CaseIterable, Identifiable {
    case general = "General"
    case integrations = "Integrations"
    case notifications = "Notifications"
    case display = "Display"
    case sound = "Sound"
    case usage = "Usage"
    case shortcuts = "Shortcuts"
    case remote = "Remote SSH"
    case labs = "Labs"
    case pass = "Pass"
    case about = "About"

    var id: String { rawValue }

    var symbol: String {
      switch self {
      case .general: return "gearshape.fill"
      case .integrations: return "puzzlepiece.extension.fill"
      case .notifications: return "bell.badge.fill"
      case .display: return "textformat.size"
      case .sound: return "speaker.wave.2.fill"
      case .usage: return "gauge.with.dots.needle.67percent"
      case .shortcuts: return "keyboard.fill"
      case .remote: return "network"
      case .labs: return "flask.fill"
      case .pass: return "wallet.bifold.fill"
      case .about: return "info.circle.fill"
      }
    }

    var tint: Color {
      switch self {
      case .general: return Color(hex: 0xA7ADB1)
      case .integrations: return Color(hex: 0x42C5E8)
      case .notifications: return Color(hex: 0xFF5A66)
      case .display: return Color(hex: 0x8F78F8)
      case .sound: return Color(hex: 0x45D96D)
      case .usage: return Color(hex: 0xFF4F7D)
      case .shortcuts: return Color(hex: 0xE551EE)
      case .remote: return Color(hex: 0x36C5D5)
      case .labs: return Color(hex: 0xF5A03A)
      case .pass: return Color(hex: 0x30D5C8)
      case .about: return Color(hex: 0x3498F5)
      }
    }
  }

  @State private var pane: Pane = .general

  var body: some View {
    HStack(spacing: 0) {
      sidebar
        // Vibe's sidebar is a fixed 188 pt column. A custom split avoids the
        // automatic NavigationSplitView toolbar button that Vibe does not expose.
        .frame(width: 188)
      detail
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(SettingsStyle.canvas)
    .preferredColorScheme(.dark)
    .toggleStyle(VibeToggleStyle())
    .frame(minWidth: 620, minHeight: 620)
    .ignoresSafeArea(.container, edges: .top)
  }

  private var sidebar: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 3) {
        ForEach(primaryPanes) { sidebarButton($0) }
        sidebarGroup(t("Advanced"))
        ForEach(advancedPanes) { sidebarButton($0) }
        sidebarGroup("Perch")
        sidebarButton(.pass)
        sidebarButton(.about)
      }
      .padding(.horizontal, 6)
      .padding(.top, 55)
      .padding(.bottom, 16)
    }
    .background(SettingsStyle.sidebar)
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .stroke(Color.white.opacity(0.10), lineWidth: 1)
    }
  }

  private var detail: some View {
    VStack(spacing: 0) {
      SettingsPaneHeader(pane: pane)
      ScrollView {
        Group {
          switch pane {
          case .general: GeneralPane(model: model, scope: .general)
          case .integrations:
            IntegrationsPane(model: model, scope: .integrations)
          case .notifications: NotificationsPane(model: model)
          case .display: GeneralPane(model: model, scope: .display)
          case .sound: SoundPane(model: model)
          case .usage: IntegrationsPane(model: model, scope: .usage)
          case .shortcuts: GeneralPane(model: model, scope: .shortcuts)
          case .remote: RemotePane(model: model)
          case .labs: GeneralPane(model: model, scope: .labs)
          case .pass: PassPane()
          case .about: AboutPane(model: model)
          }
        }
        // Vibe's scrollbar overlays the content instead of reserving a 16 pt lane.
        // Extending the trailing edge under that lane keeps cards at the measured
        // 391 pt width while leaving the same 20 pt leading gutter.
        .padding(.leading, 24)
        .padding(.trailing, 4)
        .padding(.bottom, 24)
        .frame(width: 419, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .background(SettingsStyle.canvas)
  }

  private var primaryPanes: [Pane] {
    [.general, .integrations, .notifications, .display, .sound, .usage]
  }

  private var advancedPanes: [Pane] { [.shortcuts, .remote, .labs] }

  @ViewBuilder
  private func sidebarButton(_ item: Pane) -> some View {
    Button {
      pane = item
    } label: {
      HStack(spacing: 10) {
        Image(systemName: item.symbol)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 22, height: 22)
          .background(RoundedRectangle(cornerRadius: 6).fill(item.tint))
        Text(t(item.rawValue))
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.primary)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .frame(height: 31)
      .background(
        RoundedRectangle(cornerRadius: 7)
          .fill(pane == item ? Color.white.opacity(0.14) : .clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.leading, 8)
  }

  private func sidebarGroup(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(Color.white.opacity(0.38))
      .padding(.leading, 20)
      .padding(.trailing, 9)
      .padding(.top, 16)
      .padding(.bottom, 4)
  }
}

private enum SettingsStyle {
  static let canvas = Color(hex: 0x202A2D)
  static let sidebar = Color(hex: 0x1C272A)
  static let card = Color.white.opacity(0.055)
  static let cardBorder = Color.white.opacity(0.035)
}

private struct VibeToggleStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack(spacing: 10) {
        configuration.label
        Spacer(minLength: 8)
        ZStack {
          Capsule()
            .fill(
              configuration.isOn
                ? Color.white.opacity(0.18)
                : Color.white.opacity(0.11))
          Circle()
            .fill(Color.white.opacity(0.94))
            .frame(width: 13, height: 13)
            .offset(x: configuration.isOn ? 9 : -9)
        }
        .frame(width: 36, height: 16)
      }
      .frame(minHeight: 20)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .animation(.easeOut(duration: 0.12), value: configuration.isOn)
  }
}

// MARK: - Pass

private struct PassPane: View {
  @State private var showsUnavailable = false

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "wallet.bifold")
        .font(.system(size: 34, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.14))
      Text(t("Activate a license to unlock your Pass"))
        .font(Theme.mono(12))
        .foregroundStyle(.secondary)
      Button(t("Activate")) { showsUnavailable = true }
        .buttonStyle(.borderedProminent)
        .tint(Color.white.opacity(0.16))
        .foregroundStyle(.white)
        .controlSize(.small)
        .padding(.horizontal, 4)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 42)
    .alert(t("License activation is not configured for Perch."), isPresented: $showsUnavailable) {
      Button(t("OK"), role: .cancel) {}
    }
  }
}

private struct SettingsPaneHeader: View {
  let pane: SettingsView.Pane

  var body: some View {
    HStack(spacing: 9) {
      Image(systemName: pane.symbol)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 22, height: 22)
        .background(RoundedRectangle(cornerRadius: 6).fill(pane.tint))
      Text(t(pane.rawValue))
        .font(.system(size: 17, weight: .bold))
      Spacer()
    }
    .padding(.horizontal, 24)
    .padding(.top, 18)
    .padding(.bottom, 18)
  }
}

// MARK: - General

private struct GeneralPane: View {
  enum Scope { case general, notifications, display, shortcuts, labs }

  let model: AppModel
  let scope: Scope

  private var quiet: QuietSettings { model.quiet }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if scope == .general {
        Section(t("System"), note: nil, verticalPadding: 5) {
          Toggle(t("Open at login"), isOn: launchAtLogin)
          Divider().overlay(Color.white.opacity(0.07))
          HStack {
            Text(t("App language"))
            Spacer()
            VibeMenuPicker(
              title: t("App language"), selection: language,
              options: AppLanguage.allCases.map {
                VibePickerOption(value: $0, title: t($0.title))
              })
          }
        }
        .padding(.bottom, 10)

        Section(t("Deployment"), note: nil, verticalPadding: 13) {
          Toggle(t("Expand notch on hover"), isOn: expandsOnHover)
        }
        .padding(.bottom, 14)

        Section(t("Visibility"), note: nil, verticalPadding: 13) {
          Toggle(t("Hide in fullscreen"), isOn: hidesInFullscreen)
          Toggle(
            t("Hide automatically when there is no active session"),
            isOn: hidesWhenNoSessions)
        }
        .padding(.bottom, 12)

        Section(t("Closing"), note: nil) {
          Toggle(t("Collapse automatically on mouse exit"), isOn: collapsesOnHoverExit)
          Divider().overlay(Color.white.opacity(0.07))
          HStack {
            Text(t("Auto-display duration"))
            Spacer()
            VibeMenuPicker(
              title: t("Auto-display duration"), selection: autoDisplayDuration,
              options: [3, 5, 8, 10, 15].map {
                VibePickerOption(value: TimeInterval($0), title: "\($0)s")
              })
          }
          Text(
            t(
              "Time the panel stays open for completion and warning notifications. Press Escape to close sooner."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          Toggle(
            t("Close auto-display on outside click"),
            isOn: closesAutoDisplayOnOutsideClick)
          Text(
            t(
              "Clicking anywhere outside the panel immediately closes completion and warning notifications, ignoring the remaining time."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          Divider().overlay(Color.white.opacity(0.07))
          HStack {
            Text(t("Inactive session cleanup"))
            Spacer()
            VibeMenuPicker(
              title: t("Inactive session cleanup"), selection: idleTimeout,
              options: [
                VibePickerOption(value: TimeInterval(0), title: t("Never")),
                VibePickerOption(value: TimeInterval(30 * 60), title: t("30 minutes")),
                VibePickerOption(value: TimeInterval(3_600), title: t("1 hour")),
                VibePickerOption(value: TimeInterval(2 * 3_600), title: t("2 hours (Default)")),
                VibePickerOption(value: TimeInterval(8 * 3_600), title: t("8 hours")),
                VibePickerOption(value: TimeInterval(24 * 3_600), title: t("24 hours")),
              ])
          }
          Text(
            t(
              "Only applies to sessions without a clear closing signal (Codex, OpenCode, Cursor)."
            )
          )
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section(t("Interaction"), note: nil) {
          Toggle(t("Disable click-to-jump"), isOn: disablesSessionJump)
          Text(
            t(
              "When enabled, clicking a session does not switch to its terminal or IDE.")
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      if scope == .notifications {
        Section(
          t("Quiet scenes"),
          note: t(
            "Perch stays silent while any of these is true — no panel, no sound, "
              + "approvals included. Requests still queue and the session is still held; "
              + "a dot marks them.")
        ) {
          Toggle(t("A Focus mode is on"), isOn: binding(\.duringFocus))
          Toggle(t("The screen is locked or asleep"), isOn: binding(\.whenScreenObscured))
          Toggle(
            t("The screen is being recorded or shared"),
            isOn: binding(\.whenScreenShared))
        }

        Section(
          t("Heads-down"),
          note: t(
            "A mode you switch on yourself. Completions and other chatter drop to a "
              + "dot, no sound, no panel — but an approval still opens, so nothing "
              + "stays blocked while you focus.")
        ) {
          Toggle(t("Heads-down mode"), isOn: binding(\.manualQuiet))
        }

        Section(
          t("Quiet hours"),
          note: t("Crosses midnight when the end is earlier than the start.")
        ) {
          Toggle(t("Silence during a time range"), isOn: quietHoursEnabled)
          if let hours = quiet.quietHours {
            HStack(spacing: 12) {
              TimeField(label: t("From"), minutes: quietHourBinding(\.start))
              TimeField(label: t("Until"), minutes: quietHourBinding(\.end))
              Text(rangeSummary(hours))
                .font(.callout)
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      if scope == .shortcuts {
        Section(t("Modifier key"), note: nil) {
          HStack {
            Text(t("Modifier key"))
            Spacer()
            VibeMenuPicker(
              title: t("Modifier key"), selection: switcherModifier,
              options: [
                VibePickerOption(value: UInt32(4096), title: "⌃ Control"),
                VibePickerOption(value: UInt32(2048), title: "⌥ Option"),
                VibePickerOption(value: UInt32(256), title: "⌘ Command"),
                VibePickerOption(value: UInt32(4096 | 2048), title: "⌃⌥ Control + Option"),
              ])
          }
        }
        .padding(.bottom, 12)
        Section(
          t("Global shortcuts"),
          note: nil
        ) {
          Toggle(isOn: switcherEnabled) {
            VStack(alignment: .leading, spacing: 2) {
              Text(t("Enable keyboard shortcuts"))
              Text(t("Disables all Perch shortcuts without clearing your configured keys."))
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          Divider().overlay(Color.white.opacity(0.07))
          HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
              Text(t("Open switcher"))
              Text(
                t(
                  "Tap to open and pick with ↑↓ + Return; hold and press again to cycle, then release the modifier to join."
                )
              )
              .font(.caption).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            ShortcutRecorder(
              keyCode: model.preferences.switcherKeyCode,
              modifiers: model.preferences.switcherModifiers
            ) { keyCode, modifiers in
              var next = model.preferences
              next.switcherKeyCode = keyCode
              next.switcherModifiers = modifiers
              model.updatePreferences(next)
            }
          }
          .disabled(!model.preferences.switcherEnabled)
          Divider().overlay(Color.white.opacity(0.07))
          Toggle(isOn: reverseSwitcherEnabled) {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 6) {
                Text(t("Reverse switcher"))
                Text("⌃⇧G")
                  .font(.system(size: 11, weight: .semibold, design: .rounded))
                  .padding(.horizontal, 5).padding(.vertical, 2)
                  .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.2)))
              }
              Text(t("Adds Shift to the switcher shortcut to cycle backwards."))
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          Divider().overlay(Color.white.opacity(0.07))
          ShortcutLegendRow(
            title: t("Collapse panel"),
            keys: "esc",
            caption: t("Only active while the panel is expanded."))
        }

        Section(
          t("Panel shortcuts"),
          note: t("All shortcuts below are active while the panel is expanded. Hold your modifier key to show hints on every button.")) {
          ShortcutLegendRow(title: t("Approve"), keys: "⌃ + Y")
          Divider().overlay(Color.white.opacity(0.07))
          ShortcutLegendRow(title: t("Deny"), keys: "⌃ + N")
          Divider().overlay(Color.white.opacity(0.07))
          ShortcutLegendRow(title: t("Always allow"), keys: "⌃ + A")
          Divider().overlay(Color.white.opacity(0.07))
          ShortcutLegendRow(title: t("Bypass permissions"), keys: "⌃ + B")
          Divider().overlay(Color.white.opacity(0.07))
          ShortcutLegendRow(title: t("Join terminal"), keys: "⌃ + T")
          Divider().overlay(Color.white.opacity(0.07))
          ShortcutLegendRow(title: t("Select option"), keys: "⌃ + 1–9")
          Divider().overlay(Color.white.opacity(0.07))
          ShortcutLegendRow(title: t("Submit multi-select"), keys: "⌃ + ↵")
          Divider().overlay(Color.white.opacity(0.07))
          ShortcutLegendRow(title: t("Navigate sessions"), keys: "↑  ↓")
        }
      }

      if scope == .display {
        Section(
          t("Notch"),
          note: nil
        ) {
          NotchSettingsPreview()
          PanelLayoutPreview(selection: layout)
          Divider().overlay(Color.white.opacity(0.07))
          HStack {
            Text(t("Screen"))
            Spacer()
            VibeMenuPicker(
              title: t("Screen"), selection: targetDisplayName,
              options: [VibePickerOption(value: "", title: t("Main display"))]
                + NSScreen.screens.map {
                  VibePickerOption(value: $0.localizedName, title: $0.localizedName)
                })
          }
        }

        Section(t("Panel size"), note: nil) {
          HStack {
            Text(t("Content font size"))
            Spacer()
            VibeMenuPicker(
              title: t("Content font size"), selection: contentFontSize,
              options: [
                VibePickerOption(value: 9, title: "9pt"),
                VibePickerOption(value: 10, title: "10pt"),
                VibePickerOption(value: 11, title: "11pt (\(t("Default")))"),
                VibePickerOption(value: 12, title: "12pt"),
                VibePickerOption(value: 13, title: "13pt"),
              ])
          }
          Divider().overlay(Color.white.opacity(0.07))
          SettingsValueSlider(
            title: t("Completion card height"), value: completionCardHeight,
            // Thumb positions reconstructed from Vibe's 90 pt reference capture.
            range: 70...170, suffix: "pt")
          .padding(.top, 3)
          SettingsValueSlider(
            title: t("Maximum panel height"), value: panelMaximumHeight,
            range: 320...720, suffix: "pt")
          SettingsValueSlider(
            title: t("Maximum panel width"), value: panelMaximumWidth,
            range: 420...820, suffix: "pt")
        }

        Section(t("Session Card"), note: nil) {
          Toggle(t("Show project name"), isOn: showsProjectName)
          Toggle(t("Show worktree"), isOn: showsWorktree)
          Toggle(t("Show AI model"), isOn: showsAIModel)
          Toggle(t("Show reasoning effort"), isOn: showsReasoningEffort)
          VStack(alignment: .leading, spacing: 4) {
            Toggle(t("Show tasks"), isOn: showsTasks)
            Text(t("Shows the task list in each session card."))
              .font(.caption).foregroundStyle(.secondary)
          }
          VStack(alignment: .leading, spacing: 4) {
            Toggle(t("Show subagents"), isOn: showsSubagents)
            Text(
              t(
                "Shows subagent details in session cards. When hidden, an active-agent count replaces them; approvals and questions remain visible."
              )
            )
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }
          Toggle(
            t("Show agent activity details"),
            isOn: showsActivityDetails)
          SessionCardSettingsPreview(preferences: model.preferences)
        }
      }

      if scope == .display {
        Section(
          t("Adjustment"),
          note: t(
            "Fine-tune only when the panel does not sit exactly over the cutout. Zero uses the dimensions detected by macOS."
          )
        ) {
          Slider(value: notchWidth, in: -60...60, step: 1) {
            Text(t("Notch width") + "  \(Int(model.preferences.notchWidthAdjustment)) pt")
              .monospacedDigit()
          }
          .vibeSliderTrack(
            value: model.preferences.notchWidthAdjustment, in: -60...60)
          Slider(value: notchHeight, in: -12...24, step: 1) {
            Text(t("Notch height") + "  \(Int(model.preferences.notchHeightAdjustment)) pt")
              .monospacedDigit()
          }
          .vibeSliderTrack(
            value: model.preferences.notchHeightAdjustment, in: -12...24)
          Button(t("Reset to what macOS reports")) {
            var next = model.preferences
            next.notchWidthAdjustment = 0
            next.notchHeightAdjustment = 0
            model.updatePreferences(next)
          }
          Toggle(
            t("Show the plan beside the cutout when nothing is running"),
            isOn: restingQuota)
        }
      }

      if scope == .labs {
        Section(t("Beta Updates"), note: nil) {
          Toggle(isOn: beta) {
            VStack(alignment: .leading, spacing: 2) {
              Text(t("Beta Updates"))
              Text(t("Get early access to new features. Beta builds may be less stable."))
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        Section(t("Stability"), note: nil) {
          Toggle(isOn: memorySafetyRestart) {
            VStack(alignment: .leading, spacing: 2) {
              Text(t("Restart if memory is high"))
              Text(t("Optional safety net. Relaunches only if memory stays high and every session is idle."))
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        Section(t("Claude Code"), note: nil) {
          Toggle(isOn: claudeAutoModeOverride) {
            VStack(alignment: .leading, spacing: 2) {
              Text(t("Use Auto Mode instead of Bypass"))
              Text(t("Replace Bypass with Auto Mode. Claude Code decides the safety of each action."))
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          Toggle(isOn: ignoresClaudeApprovals) {
            VStack(alignment: .leading, spacing: 2) {
              Text(t("Use native Claude Code approvals"))
              Text(t("Ignore Perch approval cards and notifications, and let Claude Code handle approvals in the terminal."))
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        Section(t("Codex"), note: nil) {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
              Text(t("When Codex needs your approval"))
              Text(t("Auto-reviewed requests are always silent"))
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VibeMenuPicker(
              title: t("When Codex needs your approval"), selection: codexAutoReviewPolicy,
              options: [
                VibePickerOption(value: .followFocus, title: t("Follow focus")),
                VibePickerOption(value: .alwaysSilent, title: t("Stay silent")),
                VibePickerOption(value: .alwaysShow, title: t("Notify me")),
              ])
          }
          Toggle(isOn: opensCodexThreadsInApp) {
            VStack(alignment: .leading, spacing: 2) {
              Text(t("Open app-server sessions in Codex"))
              Text(
                t(
                  "Clicking a session run through codex app-server opens its thread in the Codex app instead of the terminal. The thread may not appear there if the tool uses a separate backend."
                )
              )
              .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        Section(t("Other CLIs"), note: nil) {
          HStack {
            Text(t("Cursor Sandbox Approval"))
            Spacer()
            VibeMenuPicker(
              title: t("Cursor Sandbox Approval"), selection: cursorYoloPolicy,
              options: [
                VibePickerOption(value: .automatic, title: t("Auto-detect")),
                VibePickerOption(value: .enabled, title: t("Enabled")),
                VibePickerOption(value: .disabled, title: t("Disabled")),
              ])
          }
          Text(t("Auto reads Cursor's YOLO config to decide."))
            .font(.caption).foregroundStyle(.secondary)
        }
      }

      if scope == .notifications {
        Section(t("Completion notifications"), note: nil) {
          Toggle(
            t("Stay quiet when the asking terminal is already in front"),
            isOn: binding(\.smartSuppression))
          Toggle(t("Play sounds"), isOn: binding(\.soundEnabled))
          Toggle(
            t("Notify me when a turn ends somewhere I cannot see"),
            isOn: binding(\.notifiesOnComplete))
          Text(
            t(
              "A macOS notification, silent — Perch already owns the sound. It "
                + "stays quiet in a quiet scene, during quiet hours, and while "
                + "you are looking at the terminal that raised it. Clicking it "
                + "jumps there.")
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          Toggle(
            t("Open the panel when a task finishes"),
            isOn: binding(\.autoExpandOnComplete))
          Text(t("Off by default — a chime per finished turn is how people end up muting an app."))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(
      .top,
      scope == .general ? 8 : (scope == .display || scope == .labs ? 6 : scope == .shortcuts ? 4 : 0))
  }

  private func binding(_ path: WritableKeyPath<QuietSettings, Bool>) -> Binding<Bool> {
    Binding(
      get: { model.quiet[keyPath: path] },
      set: { value in
        var settings = model.quiet
        settings[keyPath: path] = value
        model.updateQuiet(settings)
      })
  }

  private var quietHoursEnabled: Binding<Bool> {
    Binding(
      get: { model.quiet.quietHours != nil },
      set: { value in
        var settings = model.quiet
        settings.quietHours = value ? QuietHours(start: 22 * 60, end: 7 * 60) : nil
        model.updateQuiet(settings)
      })
  }

  private func quietHourBinding(_ path: WritableKeyPath<QuietHours, Int>) -> Binding<Int> {
    Binding(
      get: { model.quiet.quietHours?[keyPath: path] ?? 0 },
      set: { value in
        var settings = model.quiet
        settings.quietHours?[keyPath: path] = value
        model.updateQuiet(settings)
      })
  }

  private func rangeSummary(_ hours: QuietHours) -> String {
    hours.start > hours.end ? t("crosses midnight") : ""
  }

  private var switcherEnabled: Binding<Bool> {
    Binding(
      get: { model.preferences.switcherEnabled },
      set: { value in
        var next = model.preferences
        next.switcherEnabled = value
        model.updatePreferences(next)
      })
  }

  private var switcherModifier: Binding<UInt32> {
    Binding(
      get: { model.preferences.switcherModifiers },
      set: { value in
        var next = model.preferences
        next.switcherModifiers = value
        model.updatePreferences(next)
      })
  }

  private var reverseSwitcherEnabled: Binding<Bool> {
    preferenceBinding(\.reverseSwitcherEnabled)
  }

  private var notchWidth: Binding<Double> {
    Binding(
      get: { model.preferences.notchWidthAdjustment },
      set: { value in
        var next = model.preferences
        next.notchWidthAdjustment = value
        model.updatePreferences(next)
      })
  }

  private var notchHeight: Binding<Double> {
    Binding(
      get: { model.preferences.notchHeightAdjustment },
      set: { value in
        var next = model.preferences
        next.notchHeightAdjustment = value
        model.updatePreferences(next)
      })
  }

  private var panelMaximumWidth: Binding<Double> {
    Binding(
      get: { model.preferences.panelMaximumWidth },
      set: { value in
        var next = model.preferences
        next.panelMaximumWidth = value
        model.updatePreferences(next)
      })
  }

  private var panelMaximumHeight: Binding<Double> {
    Binding(
      get: { model.preferences.panelMaximumHeight },
      set: { value in
        var next = model.preferences
        next.panelMaximumHeight = value
        model.updatePreferences(next)
      })
  }

  private var contentFontSize: Binding<Double> {
    preferenceBinding(\.contentFontSize)
  }

  private var completionCardHeight: Binding<Double> {
    preferenceBinding(\.completionCardHeight)
  }

  private var showsProjectName: Binding<Bool> { preferenceBinding(\.showsProjectName) }
  private var showsWorktree: Binding<Bool> { preferenceBinding(\.showsWorktree) }
  private var showsAIModel: Binding<Bool> { preferenceBinding(\.showsAIModel) }
  private var showsReasoningEffort: Binding<Bool> {
    preferenceBinding(\.showsReasoningEffort)
  }
  private var showsTasks: Binding<Bool> { preferenceBinding(\.showsTasks) }
  private var showsSubagents: Binding<Bool> { preferenceBinding(\.showsSubagents) }
  private var showsActivityDetails: Binding<Bool> {
    preferenceBinding(\.showsActivityDetails)
  }

  private var targetDisplayName: Binding<String> {
    Binding(
      get: { model.preferences.targetDisplayName ?? "" },
      set: { value in
        var next = model.preferences
        next.targetDisplayName = value.isEmpty ? nil : value
        model.updatePreferences(next)
      })
  }

  private func preferenceBinding(_ path: WritableKeyPath<Preferences, Double>) -> Binding<Double> {
    Binding(
      get: { model.preferences[keyPath: path] },
      set: { value in
        var next = model.preferences
        next[keyPath: path] = value
        model.updatePreferences(next)
      })
  }

  private var layout: Binding<PanelLayout> {
    Binding(
      get: { model.preferences.layout },
      set: { value in
        var next = model.preferences
        next.layout = value
        model.updatePreferences(next)
      })
  }

  private var restingQuota: Binding<Bool> {
    Binding(
      get: { model.preferences.restingQuota },
      set: { value in
        var next = model.preferences
        next.restingQuota = value
        model.updatePreferences(next)
      })
  }

  private var language: Binding<AppLanguage> {
    Binding(
      get: { model.preferences.language },
      set: { value in
        var next = model.preferences
        next.language = value
        model.updatePreferences(next)
        // Written to `AppleLanguages` now rather than at the next launch, so a
        // relaunch — by the button beside it or by hand — comes back in the right
        // language whichever way it happens.
        applyLanguagePreference(next)
      })
  }

  /// Reads the preference, not `SMAppService`, even though macOS is what actually
  /// decides: the preference is squared with the system at launch, and it is the only
  /// one of the two that SwiftUI can observe — a toggle reading the service directly
  /// would flip and then redraw itself back, because nothing told the view to update.
  private var launchAtLogin: Binding<Bool> {
    Binding(
      get: { model.preferences.launchAtLogin },
      set: { value in
        var next = model.preferences
        next.launchAtLogin = value
        model.updatePreferences(next)
      })
  }

  private var expandsOnHover: Binding<Bool> {
    preferenceBinding(\.expandsOnHover)
  }

  private var collapsesOnHoverExit: Binding<Bool> {
    preferenceBinding(\.collapsesOnHoverExit)
  }

  private var hidesWhenNoSessions: Binding<Bool> {
    preferenceBinding(\.hidesWhenNoSessions)
  }

  private var hidesInFullscreen: Binding<Bool> {
    preferenceBinding(\.hidesInFullscreen)
  }

  private var autoDisplayDuration: Binding<TimeInterval> {
    Binding(
      get: { model.preferences.autoDisplayDuration },
      set: { value in
        var next = model.preferences
        next.autoDisplayDuration = value
        model.updatePreferences(next)
      })
  }

  private var closesAutoDisplayOnOutsideClick: Binding<Bool> {
    preferenceBinding(\.closesAutoDisplayOnOutsideClick)
  }

  private var disablesSessionJump: Binding<Bool> {
    preferenceBinding(\.disablesSessionJump)
  }

  private func preferenceBinding(_ path: WritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
    Binding(
      get: { model.preferences[keyPath: path] },
      set: { value in
        var next = model.preferences
        next[keyPath: path] = value
        model.updatePreferences(next)
      })
  }

  private var beta: Binding<Bool> {
    Binding(
      get: { model.preferences.betaUpdates },
      set: { value in
        var next = model.preferences
        next.betaUpdates = value
        model.updatePreferences(next)
      })
  }

  private var memorySafetyRestart: Binding<Bool> {
    preferenceBinding(\.memorySafetyRestart)
  }
  private var claudeAutoModeOverride: Binding<Bool> {
    preferenceBinding(\.claudeAutoModeOverride)
  }
  private var ignoresClaudeApprovals: Binding<Bool> {
    preferenceBinding(\.ignoresClaudeApprovals)
  }
  private var opensCodexThreadsInApp: Binding<Bool> {
    preferenceBinding(\.opensCodexThreadsInApp)
  }
  private var codexAutoReviewPolicy: Binding<AutoReviewPolicy> {
    Binding(
      get: { model.preferences.codexAutoReviewPolicy },
      set: { value in
        var next = model.preferences
        next.codexAutoReviewPolicy = value
        model.updatePreferences(next)
      })
  }
  private var cursorYoloPolicy: Binding<DetectionPolicy> {
    Binding(
      get: { model.preferences.cursorYoloPolicy },
      set: { value in
        var next = model.preferences
        next.cursorYoloPolicy = value
        model.updatePreferences(next)
      })
  }

  private var idleTimeout: Binding<TimeInterval> {
    Binding(
      get: { model.preferences.idleTimeout },
      set: { value in
        var next = model.preferences
        next.idleTimeout = value
        model.updatePreferences(next)
      })
  }
}

/// Records a shortcut by listening for one key press while focused.
///
/// The recorder deliberately refuses a bare letter: a global shortcut with no modifier
/// would swallow that key in every app on the machine.
private struct ShortcutRecorder: View {
  let keyCode: UInt32
  let modifiers: UInt32
  let onRecord: (UInt32, UInt32) -> Void

  @State private var isRecording = false
  @State private var monitor: Any?
  @State private var rejected = false

  var body: some View {
    HStack(spacing: 8) {
      Button {
        isRecording ? stop() : start()
      } label: {
        Text(
          isRecording
            ? t("Press a shortcut…")
            : ShortcutFormatter.describe(keyCode: keyCode, modifiers: modifiers)
        )
        .frame(minWidth: 42)
      }
      if !isRecording && (keyCode != 0 || modifiers != 0) {
        Button {
          onRecord(0, 0)
        } label: {
          Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
      }
      if rejected {
        Text(t("Needs ⌃, ⌥ or ⌘"))
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }
    .onDisappear(perform: stop)
  }

  private func start() {
    isRecording = true
    rejected = false
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let carbon = ShortcutFormatter.carbonModifiers(
        fromCocoa: UInt(event.modifierFlags.rawValue))
      let code = UInt32(event.keyCode)
      if ShortcutFormatter.isUsable(keyCode: code, modifiers: carbon) {
        onRecord(code, carbon)
        stop()
      } else {
        rejected = true
      }
      // Swallow it either way: the point of recording is that the key does not act.
      return nil
    }
  }

  private func stop() {
    isRecording = false
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }
}

private struct TimeField: View {
  let label: String
  @Binding var minutes: Int

  var body: some View {
    HStack(spacing: 6) {
      Text(label).foregroundStyle(.secondary)
      Stepper(value: $minutes, in: 0...(24 * 60 - 15), step: 15) {
        Text(String(format: "%02d:%02d", minutes / 60, minutes % 60))
          .monospacedDigit()
      }
      .fixedSize()
    }
  }
}

// MARK: - Sound

private struct SoundPane: View {
  let model: AppModel

  private var sounds: SoundSettings { model.sounds }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 10) {
        Toggle(t("Enable sound effects"), isOn: enabled)
        if sounds.enabled {
          Text(
            t(
              "A source is a chiptune jingle synthesised on the spot, a macOS system "
                + "sound, a file you picked, or nothing at all.")
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
        if sounds.enabled {
          HStack {
            Text(t("Volume")).foregroundStyle(.secondary)
            Slider(value: volume, in: 0...1)
              .vibeSliderTrack(value: sounds.volume, in: 0...1)
            Text(String(format: "%.0f%%", sounds.volume * 100))
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(SettingsStyle.card)
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(SettingsStyle.cardBorder, lineWidth: 1)))

      if sounds.enabled {
        Section(
          t("Packs"),
          note: t(
            "A pack is a folder of audio files with a manifest. Applying one points "
              + "the events it covers at its files and leaves the rest alone.")
        ) {
          HStack {
            Button(t("Import a pack…")) { importPack() }
            if packs.isEmpty {
              Text(t("No packs installed."))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
          }
          ForEach(packs, id: \.name) { pack in
            HStack {
              VStack(alignment: .leading, spacing: 1) {
                Text(pack.name)
                Text(
                  pack.author.map { "\($0) · \(pack.sounds.count) sounds" }
                    ?? "\(pack.sounds.count) sounds"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
              }
              Spacer()
              Button(t("Apply")) {
                var next = model.sounds
                next.apply(pack)
                model.updateSounds(next)
              }
            }
          }
        }
      }

      if sounds.enabled {
        Section(
          t("Per event"),
          note: t(
            "The noisy ones start silent: a chime for every finished turn is how an "
              + "app gets muted for good.")
        ) {
          ForEach(InterruptionKind.allCases, id: \.rawValue) { kind in
            HStack(spacing: 8) {
              Text(t(kind.title))
                .frame(width: 170, alignment: .leading)

              Picker("", selection: source(for: kind)) {
                Text(t("Off")).tag(SoundSource.off)
                // The 8-bit voices first: they are the ones that belong to the
                // instrument, and the ones a fresh install already uses.
                ForEach(ChipTune.names, id: \.self) { name in
                  Text("\(name) · 8-bit").tag(SoundSource.synth(name))
                }
                ForEach(SoundSettings.systemNames, id: \.self) { name in
                  Text(name).tag(SoundSource.system(name))
                }
                // A picked file is not in the list, so it needs its own row or
                // the selection would silently fall back to Off.
                if case .file(let path) = sounds.source(for: kind) {
                  Text(URL(fileURLWithPath: path).lastPathComponent)
                    .tag(SoundSource.file(path))
                }
              }
              .labelsHidden()
              .frame(width: 160)

              Button(t("Choose…")) { chooseFile(for: kind) }
              Button(t("Preview")) {
                SoundPlayer.preview(sounds.source(for: kind), volume: sounds.volume)
              }
              .disabled(sounds.source(for: kind) == .off)

              Spacer()
            }
            .disabled(!sounds.enabled)
          }
        }
      }
    }
    .padding(.top, 5)
  }

  private var enabled: Binding<Bool> {
    Binding(
      get: { model.sounds.enabled },
      set: { value in
        var next = model.sounds
        next.enabled = value
        model.updateSounds(next)
      })
  }

  private var volume: Binding<Double> {
    Binding(
      get: { model.sounds.volume },
      set: { value in
        var next = model.sounds
        next.volume = value
        model.updateSounds(next)
      })
  }

  private func source(for kind: InterruptionKind) -> Binding<SoundSource> {
    Binding(
      get: { model.sounds.source(for: kind) },
      set: { value in
        var next = model.sounds
        next.setSource(value, for: kind)
        model.updateSounds(next)
        // Play it as it is picked: choosing a sound you cannot hear is guesswork.
        SoundPlayer.preview(value, volume: next.volume)
      })
  }

  @State private var packs: [SoundPack] = SoundPack.installed()

  /// Copies the folder in rather than referencing it where it sits: a pack imported from
  /// Downloads should survive the Downloads folder being cleared.
  private func importPack() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.prompt = t("Import a pack…")
    guard panel.runModal() == .OK, let source = panel.url else { return }

    guard SoundPack.load(from: source) != nil else {
      let alert = NSAlert()
      alert.messageText = t("That folder is not a sound pack")
      alert.informativeText = t(
        "A pack needs a pack.json naming which file plays for which event, and the "
          + "files it names have to be there.")
      alert.runModal()
      return
    }

    let destination = SoundPack.installedDirectory
      .appendingPathComponent(source.lastPathComponent)
    try? FileManager.default.createDirectory(
      at: SoundPack.installedDirectory, withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: destination)
    try? FileManager.default.copyItem(at: source, to: destination)
    packs = SoundPack.installed()
  }

  private func chooseFile(for kind: InterruptionKind) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.audio]
    panel.prompt = t("Choose…")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    var next = model.sounds
    next.setSource(.file(url.path), for: kind)
    model.updateSounds(next)
    SoundPlayer.preview(.file(url.path), volume: next.volume)
  }
}

// MARK: - Filters

private struct FiltersPane: View {
  let model: AppModel

  @State private var directoryDraft = ""
  @State private var promptDraft = ""
  @State private var showsPresetDetails = true

  private var policy: AdmissionPolicy { model.activity.admission }

  /// How many sessions on screen right now the draft would hide. Shown live so nobody
  /// commits to a rule that silences everything.
  private func previewCount(
    pattern: String, field: AdmissionRule.Field, match: AdmissionRule.Match
  ) -> Int {
    guard !pattern.isEmpty else { return 0 }
    let rule = AdmissionRule(field: field, match: match, pattern: pattern)
    return policy.matchCount(
      of: rule,
      in: model.activity.activeSessions.map { ($0.cwd, $0.prompt) })
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Section(
        t("Built-in Filters"),
        note: t("Preset folder and prompt filters appear in their matching sections below.")
      ) {
        Toggle(t("Preset filter details"), isOn: $showsPresetDetails)
      }

      Section(
        t("Blocked launcher apps"),
        note: t("Use this for background probes and helper apps. Normal project filters belong under Directory or First prompt.")
      ) {
        Button { chooseApp() } label: {
          Label(t("Add an app…"), systemImage: "plus.circle")
        }
        if model.preferences.blockedLaunchers.isEmpty {
          Text(t("No custom launcher apps are blocked."))
            .font(.caption).foregroundStyle(.secondary)
        } else {
          ForEach(model.preferences.blockedLaunchers, id: \.self) { bundleId in
            HStack {
              Text(bundleId).font(.callout)
              Spacer()
              Button(t("Unblock")) {
                var next = model.preferences
                next.blockedLaunchers.removeAll { $0 == bundleId }
                model.updatePreferences(next)
              }
            }
          }
        }
      }

      Section(
        t("Custom filters: directory"),
        note: t("Tip: right-click a session card to add its directory as a filter.")
      ) {
        Text(t("Hide any session whose working directory contains:"))
          .font(.caption).foregroundStyle(.secondary)
        HStack(spacing: 8) {
          TextField("e.g. /chronicle/dev-experiments", text: $directoryDraft)
            .textFieldStyle(.roundedBorder)
          Button(t("Add a pattern")) {
            addRule(field: .directory, match: .contains, pattern: directoryDraft)
            directoryDraft = ""
          }
          .disabled(directoryDraft.isEmpty)
        }
        preview(pattern: directoryDraft, field: .directory, match: .contains)
        ForEach(policy.rules.filter { $0.field == .directory }) { rule in
          filterRow(rule)
        }
      }

      Section(
        t("Custom filters: first prompt"),
        note: t("Tip: right-click a session card to add its first prompt as a filter.")
      ) {
        Text(t("Hide any session whose first user prompt starts with:"))
          .font(.caption).foregroundStyle(.secondary)
        HStack(spacing: 8) {
          TextField("e.g. ## Memory Writing Agent", text: $promptDraft)
            .textFieldStyle(.roundedBorder)
          Button(t("Add a pattern")) {
            addRule(field: .prompt, match: .prefix, pattern: promptDraft)
            promptDraft = ""
          }
          .disabled(promptDraft.isEmpty)
        }
        preview(pattern: promptDraft, field: .prompt, match: .prefix)
        ForEach(policy.rules.filter { $0.field == .prompt }) { rule in
          filterRow(rule)
        }
      }
    }
  }

  /// Typing a bundle identifier from memory is a good way to block nothing at all.
  private func chooseApp() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.prompt = t("Block")
    guard panel.runModal() == .OK, let url = panel.url,
      let bundleId = Bundle(url: url)?.bundleIdentifier
    else { return }
    var next = model.preferences
    guard !next.blockedLaunchers.contains(bundleId) else { return }
    next.blockedLaunchers.append(bundleId)
    model.updatePreferences(next)
  }

  private func addRule(
    field: AdmissionRule.Field, match: AdmissionRule.Match, pattern: String
  ) {
    var updated = policy
    updated.add(AdmissionRule(field: field, match: match, pattern: pattern))
    model.activity.updateAdmission(updated)
  }

  @ViewBuilder
  private func preview(
    pattern: String, field: AdmissionRule.Field, match: AdmissionRule.Match
  ) -> some View {
    let count = previewCount(pattern: pattern, field: field, match: match)
    Label(
      pattern.isEmpty ? t("Enter a pattern to preview matches") : "\(count) match\(count == 1 ? "" : "es")",
      systemImage: "sparkle.magnifyingglass")
      .font(.caption)
      .foregroundStyle(count > 0 ? Color.orange : Color.secondary)
  }

  private func filterRow(_ rule: AdmissionRule) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: rule.field == .directory ? "folder" : "text.cursor")
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(t(rule.note ?? rule.pattern))
        if rule.isPreset && showsPresetDetails {
          Text(t("Preset"))
            .font(.caption2).foregroundStyle(.secondary)
        }
        Text("\(rule.match == .prefix ? t("Prefix") : t("Contains")) · \(rule.pattern)")
          .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Toggle("", isOn: enabled(rule.id))
        .labelsHidden()
        .frame(width: 36)
      if !rule.isPreset {
        Button(t("Remove")) {
          var updated = policy
          updated.remove(id: rule.id)
          model.activity.updateAdmission(updated)
        }
      }
    }
  }

  private func enabled(_ id: String) -> Binding<Bool> {
    Binding(
      get: { policy.rules.first { $0.id == id }?.enabled ?? false },
      set: { value in
        var updated = policy
        updated.setEnabled(value, id: id)
        model.activity.updateAdmission(updated)
      })
  }
}

// MARK: - Integrations

private struct IntegrationsPane: View {
  enum Scope { case integrations, usage, notifications }

  let model: AppModel
  let scope: Scope

  @State private var isConnectingUsage = false
  @State private var usageOutcome: String?
  @State private var agentConfigurationOutcome: String?
  @State private var addingJumpRule = false
  @State private var configuringBark = false

  /// Projects that install Perch on top of the global hooks. Read here rather than
  /// remembered, so the warning goes away the moment the extra install does.
  private var duplicatedSites: Int { model.activity.health.duplicatedSites }
  private var detectedAgents: [String: DetectedTool] {
    Dictionary(
      uniqueKeysWithValues: EnvironmentScan.run()
        .filter { $0.kind == .agent }
        .map { ($0.name, $0) })
  }

  /// Off is zero rather than a separate flag, so there is one number to read and no way
  /// to be "enabled at 0%". Turning it back on restores the default rather than the last
  /// value: a threshold you disabled is not one you were happy with.
  private var warningEnabled: Binding<Bool> {
    Binding(
      get: { model.preferences.quotaWarningThreshold > 0 },
      set: { value in
        var next = model.preferences
        next.quotaWarningThreshold = value ? 90 : 0
        model.updatePreferences(next)
      })
  }

  private var warningThreshold: Binding<Double> {
    Binding(
      get: { model.preferences.quotaWarningThreshold },
      set: { value in
        var next = model.preferences
        next.quotaWarningThreshold = value
        model.updatePreferences(next)
      })
  }

  private var showsRemaining: Binding<Bool> {
    Binding(
      get: { model.preferences.showsRemainingQuota },
      set: { value in
        var next = model.preferences
        next.showsRemainingQuota = value
        model.updatePreferences(next)
      })
  }

  private var showsUsageLimits: Binding<Bool> {
    Binding(
      get: { model.preferences.showsUsageLimits },
      set: { value in
        var next = model.preferences
        next.showsUsageLimits = value
        model.updatePreferences(next)
      })
  }

  private var showsResetCards: Binding<Bool> {
    Binding(
      get: { model.preferences.showsResetCards },
      set: { value in
        var next = model.preferences
        next.showsResetCards = value
        model.updatePreferences(next)
      })
  }

  private var preferredUsageProvider: Binding<UsageProvider> {
    Binding(
      get: { model.preferences.preferredUsageProvider },
      set: { value in
        var next = model.preferences
        next.preferredUsageProvider = value
        model.updatePreferences(next)
      })
  }

  private var automaticallyConfiguresAgents: Binding<Bool> {
    Binding(
      get: { model.preferences.automaticallyConfiguresAgents },
      set: { value in
        var next = model.preferences
        next.automaticallyConfiguresAgents = value
        model.updatePreferences(next)
      })
  }

  private func agentEnabled(_ agent: Agent) -> Binding<Bool> {
    Binding(
      get: { !model.preferences.disabledAgents.contains(agent) },
      set: { value in
        var next = model.preferences
        next.disabledAgents.removeAll { $0 == agent }
        if !value { next.disabledAgents.append(agent) }
        model.updatePreferences(next)
      })
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if scope == .integrations {
        Section(
          t("Agents"),
          note: t("Manage how Perch connects to each agent.")
        ) {
          AgentIntegrationRow(
            name: "Claude Code", tool: detectedAgents["Claude Code"],
            enabled: agentEnabled(.claude), configure: { configure("Claude Code") })
          AgentIntegrationRow(
            name: "Codex", tool: detectedAgents["Codex"],
            enabled: agentEnabled(.codex), configure: { configure("Codex") })
          AgentIntegrationRow(
            name: "OpenCode", tool: detectedAgents["OpenCode"],
            enabled: agentEnabled(.opencode), configure: { configure("OpenCode") })
          AgentIntegrationRow(
            name: "Gemini CLI", tool: detectedAgents["Gemini CLI"],
            enabled: agentEnabled(.gemini), configure: { configure("Gemini CLI") })
          AgentIntegrationRow(
            name: "Cursor Agent", tool: detectedAgents["Cursor Agent"],
            enabled: agentEnabled(.cursor), configure: { configure("Cursor Agent") })
          AgentIntegrationRow(
            name: "Droid", tool: detectedAgents["Droid"],
            enabled: agentEnabled(.droid), configure: { configure("Droid") })
          AgentIntegrationRow(
            name: "Pi Agent", tool: detectedAgents["Pi Agent"],
            enabled: agentEnabled(.pi), configure: { configure("Pi Agent") })
          AgentIntegrationRow(
            name: "Amp", tool: detectedAgents["Amp"],
            enabled: agentEnabled(.amp), configure: { configure("Amp") })
          if detectedAgents["Kimi"] != nil {
            AgentIntegrationRow(
              name: "Kimi", tool: detectedAgents["Kimi"],
              enabled: agentEnabled(.kimi), configure: { configure("Kimi") })
          }
          if detectedAgents["Kimi Code"] != nil {
            AgentIntegrationRow(
              name: "Kimi Code", tool: detectedAgents["Kimi Code"],
              enabled: agentEnabled(.kimi), configure: { configure("Kimi Code") })
          }
          if detectedAgents["Mistral Vibe"] != nil {
            AgentIntegrationRow(
              name: "Mistral Vibe", tool: detectedAgents["Mistral Vibe"],
              enabled: agentEnabled(.mistralVibe), configure: { configure("Mistral Vibe") })
          }
          if detectedAgents["DeepSeek TUI"] != nil {
            AgentIntegrationRow(
              name: "DeepSeek TUI", tool: detectedAgents["DeepSeek TUI"],
              enabled: agentEnabled(.deepseek), configure: { configure("DeepSeek TUI") })
          }
          if detectedAgents["CodeWhale"] != nil {
            AgentIntegrationRow(
              name: "CodeWhale", tool: detectedAgents["CodeWhale"],
              enabled: agentEnabled(.deepseek), configure: { configure("CodeWhale") })
          }
          if detectedAgents["WorkBuddy"] != nil {
            AgentIntegrationRow(
              name: "WorkBuddy", tool: detectedAgents["WorkBuddy"],
              enabled: agentEnabled(.workbuddy), configure: { configure("WorkBuddy") })
          }
          if detectedAgents["CodeBuddy"] != nil {
            AgentIntegrationRow(
              name: "CodeBuddy", tool: detectedAgents["CodeBuddy"],
              enabled: agentEnabled(.codebuddy), configure: { configure("CodeBuddy") })
          }
          if detectedAgents["Antigravity CLI"] != nil {
            AgentIntegrationRow(
              name: "Antigravity CLI", tool: detectedAgents["Antigravity CLI"],
              enabled: agentEnabled(.antigravity), configure: { configure("Antigravity CLI") })
          }
          if detectedAgents["GitHub Copilot CLI"] != nil {
            AgentIntegrationRow(
              name: "GitHub Copilot CLI", tool: detectedAgents["GitHub Copilot CLI"],
              enabled: agentEnabled(.copilot), configure: { configure("GitHub Copilot CLI") })
          }
          Button {
            RepoScripts.copyToPasteboard(
              "./scripts/install-hooks.sh --global")
          } label: {
            HStack(spacing: 8) {
              Image(systemName: "plus.circle")
              Text(t("Add a CLI branch…"))
            }
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color(hex: 0x3498F5))
          .frame(minHeight: 27)
          .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
          }
          Toggle(isOn: automaticallyConfiguresAgents) {
            VStack(alignment: .leading, spacing: 2) {
              Text(t("Automatically configure new agents"))
              Text(t("Automatically configure newly detected compatible agents."))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .frame(minHeight: 48)
          if let agentConfigurationOutcome {
            Text(agentConfigurationOutcome)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Section(
          t("IDE"),
          note: t("Install extensions to jump directly to the right terminal tab in your IDE.")
        ) {
          HStack {
            Text("Cursor")
            Spacer()
            Button(t("Install")) {
              _ = RepoScripts.run("install-extension.sh")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Color(hex: 0xFF8A34))
            .foregroundStyle(.white)
          }
        }

        Section(
          t("Developer"),
          note: t(
            "Third-party terminal developers can register a URL scheme for precise session jumping."
          )
        ) {
          ForEach(model.preferences.customJumpRules) { rule in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(rule.terminal)
                Text(rule.urlTemplate)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              Spacer()
              Button(t("Remove")) { removeJumpRule(rule) }
            }
          }
          Button(t("Custom Jump Rules")) { addingJumpRule = true }
        }
      }

      if scope == .integrations {
        Section(
          t("Hooks"),
          note: t("Hooks are read when a session starts. Restart existing sessions after setup.")
        ) {
          ForEach(HookSite.discover(), id: \.path) { site in
            HStack {
              Image(systemName: site.isInstalled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(site.isInstalled ? Color.green : Color.secondary)
              VStack(alignment: .leading, spacing: 1) {
                Text(site.title)
                Text(site.path).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Text(site.isInstalled ? "\(site.eventCount) events" : t("not installed"))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          // Installing both scopes is not extra safety: Claude Code runs both, so
          // the session is hooked twice. Perch drops the copies, which is precisely
          // why this has to be said somewhere — otherwise nothing looks wrong.
          if duplicatedSites > 0 {
            HStack(alignment: .top, spacing: 6) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
              Text(
                t(
                  "%lld projects also install Perch on top of the global "
                    + "hooks. Every event fires twice; Perch shows it once. "
                    + "Remove the project copy with "
                    + "./scripts/install-hooks.sh --uninstall <project>.",
                  duplicatedSites)
              )
              .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
          }
          Text(t("Install with ./scripts/install-hooks.sh <project> or --codex."))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if scope == .integrations, let trust = CodexTrust.status() {
        Section(
          t("Codex trust"),
          note: t("Perch reads Codex trust without changing its security store.")
        ) {
          HStack {
            Image(
              systemName: trust.isFullyTrusted
                ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(trust.isFullyTrusted ? Color.green : Color.orange)
            Text(
              trust.isFullyTrusted
                ? "All \(trust.installedPositions) hooks are trusted"
                : "\(trust.trustedPositions) of \(trust.installedPositions) hooks trusted"
            )
            Spacer()
          }
          if trust.needsTrust {
            Text(t("Run /hooks in Codex and approve the Perch entries."))
              .font(.callout)
          }
        }
      }

      if scope == .usage {
        Section(t("Usage limits"), note: nil) {
          Toggle(t("Show usage limits"), isOn: showsUsageLimits)
          Text(t("Show subscription usage limits in the panel header"))
            .font(.caption)
            .foregroundStyle(.secondary)
          HStack {
            Text(t("Displayed value"))
            Spacer()
            VibeMenuPicker(
              title: t("Displayed value"), selection: showsRemaining,
              options: [
                VibePickerOption(value: false, title: t("Used")),
                VibePickerOption(value: true, title: t("Remaining")),
              ])
          }
          HStack {
            Text(t("Preferred provider"))
            Spacer()
            VibeMenuPicker(
              title: t("Preferred provider"), selection: preferredUsageProvider,
              options: [
                VibePickerOption(value: .automatic, title: t("Auto (follows session)")),
                VibePickerOption(value: .claude, title: "Claude"),
                VibePickerOption(value: .codex, title: "Codex"),
              ])
          }
          Toggle(t("Show Reset Cards"), isOn: showsResetCards)
          Text(
            t(
              "Show available Codex Reset Cards and the next expiration in the usage header.")
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      if scope == .usage {
        Section(t("Claude usage bridge"), note: nil) {
          HStack {
            Image(
              systemName: model.usage.bridgeLimits == nil
                ? "circle" : "checkmark.circle.fill"
            )
            .foregroundStyle(
              model.usage.bridgeLimits == nil ? Color.secondary : Color.green)
            Text(
              model.usage.bridgeLimits == nil
                ? t("Statusline bridge not connected — run ./scripts/usage-bridge.sh")
                : t("Statusline bridge connected"))
            Spacer()
            if model.usage.bridgeLimits == nil {
              Button(isConnectingUsage ? t("Connecting…") : t("Connect")) {
                connectUsage()
              }
              .disabled(isConnectingUsage)
            }
          }

          if let usageOutcome {
            Text(usageOutcome)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          if let reading = model.usage.limits {
            ForEach(reading.limits.windows) { window in
              HStack {
                Text(window.title).foregroundStyle(.secondary)
                Spacer()
                Text(
                  window.window.isStale()
                    ? t("waiting")
                    : String(
                      format: t("%.0f%% used"),
                      window.window.utilization ?? 0)
                )
                .monospacedDigit()
              }
              .font(.callout)
            }
          }
        }
      }

      if scope == .notifications {
        Section(
          t("Mobile Notifications"),
          note: t(
            "Alerts can be mirrored to a paired Apple Watch. Approvals and replies remain on your Mac."
          )
        ) {
          Toggle(isOn: pushEnabled) {
            VStack(alignment: .leading, spacing: 2) {
              Text(t("Notify my iPhone"))
              Text(t("Requires the free Bark app on your iPhone."))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          Divider().overlay(Color.white.opacity(0.07))
          HStack {
            Text(t("Connection"))
            Spacer()
            if model.barkCredentials?.isComplete != true {
              Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.orange)
            }
            Text(
              model.barkCredentials?.isComplete == true
                ? t("Configured") : t("Not configured")
            )
            .foregroundStyle(
              model.barkCredentials?.isComplete == true ? Color.secondary : Color.orange)
            Button(t("Configure…")) { configuringBark = true }
          }
        }
      }
    }
    .padding(.top, scope == .notifications ? 0 : 6)
    .sheet(isPresented: $addingJumpRule) {
      CustomJumpRuleSheet { rule in addJumpRule(rule) }
    }
    .sheet(isPresented: $configuringBark) {
      BarkSetupSheet(model: model)
    }
  }

  private func configure(_ name: String) {
    do {
      try AgentConfigurator.configure(name)
      agentConfigurationOutcome = t("%@ configured. Restart running sessions.", name)
    } catch {
      agentConfigurationOutcome = error.localizedDescription
    }
  }

  private func addJumpRule(_ rule: CustomJumpRule) {
    var next = model.preferences
    next.customJumpRules.removeAll { $0.terminal == rule.terminal }
    next.customJumpRules.append(rule)
    model.updatePreferences(next)
    addingJumpRule = false
  }

  private func removeJumpRule(_ rule: CustomJumpRule) {
    var next = model.preferences
    next.customJumpRules.removeAll { $0.id == rule.id }
    model.updatePreferences(next)
  }

  private func connectUsage() {
    isConnectingUsage = true
    usageOutcome = nil
    Task {
      let ok = RepoScripts.run("usage-bridge.sh")
      isConnectingUsage = false
      usageOutcome =
        ok
        ? t(
          "Connected. Restart your open Claude Code sessions — the statusline is read when one starts."
        )
        : t("Could not run the bridge. See ./scripts/usage-bridge.sh --status.")
    }
  }

  private var pushEnabled: Binding<Bool> {
    Binding(
      get: { model.push.enabled },
      set: { value in
        var next = model.push
        next.enabled = value
        model.updatePush(next)
      })
  }

}

private struct BarkSetupSheet: View {
  let model: AppModel

  @Environment(\.dismiss) private var dismiss
  @State private var deviceKey = ""
  @State private var encryptionKey = ""
  @State private var encryptionIV = ""
  @State private var customServer = "https://api.day.app"
  @State private var usesSelfHostedServer = false
  @State private var encryptsNotifications = false
  @State private var outcome: String?

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "bell.badge.fill")
          .font(.system(size: 28))
          .foregroundStyle(Theme.info)
        VStack(alignment: .leading, spacing: 3) {
          Text(t("Configure Bark")).font(.title2.bold())
          Text(
            t(
              "Connect Bark, test delivery, and optionally encrypt notification text.")
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(20)

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Section(t("Destination"), note: nil) {
            Picker(t("Server"), selection: $usesSelfHostedServer) {
              Text(t("Public Bark server")).tag(false)
              Text(t("Self-hosted")).tag(true)
            }
            .pickerStyle(.radioGroup)

            if usesSelfHostedServer {
              TextField("https://bark.example.com", text: $customServer)
                .textFieldStyle(.roundedBorder)
            }

            SecureField(t("Device Key"), text: $deviceKey)
              .textFieldStyle(.roundedBorder)
              .help(t("Copy it from the Bark app"))

            DisclosureGroup(t("Don't have the Bark app?")) {
              HStack(alignment: .center, spacing: 12) {
                BarkAppQRCode()
                VStack(alignment: .leading, spacing: 4) {
                  Text(t("Scan with your iPhone camera to get Bark from the App Store."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                  Link(
                    t("Open Bark in the App Store"),
                    destination: BarkAppQRCode.destination
                  )
                  .font(.caption)
                }
              }
              .padding(.top, 5)
            }
          }

          Section(t("Privacy"), note: nil) {
            Toggle(t("Encrypt notification content on this Mac"), isOn: $encryptsNotifications)
              .toggleStyle(.switch)
            Text(
              t(
                "Encrypts the title, body, and group on this Mac. The Bark server still sees your device key and delivery metadata."
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            DisclosureGroup(t("How notification privacy works")) {
              Text(
                t(
                  "Without encryption, Bark can deliver the notification text directly. With encryption, only your iPhone can read the title and body."
                )
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }

            if encryptsNotifications {
              SecureField(t("32 UTF-8 bytes"), text: $encryptionKey)
                .textFieldStyle(.roundedBorder)
              SecureField(t("16 UTF-8 bytes"), text: $encryptionIV)
                .textFieldStyle(.roundedBorder)
              HStack {
                Button(t("Generate encryption credentials")) { generateCredentials() }
                Button(t("Copy key")) { copy(encryptionKey) }
                  .disabled(encryptionKey.isEmpty)
                Button(t("Copy IV")) { copy(encryptionIV) }
                  .disabled(encryptionIV.isEmpty)
              }
            }
          }

          if let outcome {
            Text(outcome)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
      }

      Divider()
      HStack {
        Button(t("Send a test")) { sendTest() }
          .disabled(!credentials.isComplete || serverURL == nil)
        Spacer()
        Button(t("Cancel")) { dismiss() }
        Button(t("Save")) { save() }
          .keyboardShortcut(.defaultAction)
          .disabled(!credentials.isComplete || serverURL == nil)
      }
      .padding(16)
    }
    .frame(width: 520, height: encryptsNotifications ? 590 : 470)
    .onAppear {
      deviceKey = model.barkCredentials?.deviceKey ?? ""
      encryptionKey = model.barkCredentials?.encryptionKey ?? ""
      encryptionIV = model.barkCredentials?.encryptionIV ?? ""
      encryptsNotifications = model.barkCredentials?.encryptionKey != nil
      customServer = model.push.server
      usesSelfHostedServer = model.push.server != "https://api.day.app"
    }
  }

  private var credentials: BarkCredentials {
    BarkCredentials(
      deviceKey: deviceKey,
      encryptionKey: encryptsNotifications ? encryptionKey : nil,
      encryptionIV: encryptsNotifications ? encryptionIV : nil)
  }

  private var server: String {
    usesSelfHostedServer ? customServer : "https://api.day.app"
  }

  private var serverURL: URL? {
    guard let url = URL(string: server), ["http", "https"].contains(url.scheme?.lowercased())
    else { return nil }
    return url.host == nil ? nil : url
  }

  private func generateCredentials() {
    do {
      let generated = try BarkCredentials.generated(deviceKey: deviceKey)
      encryptionKey = generated.encryptionKey ?? ""
      encryptionIV = generated.encryptionIV ?? ""
      outcome = t("Generated. Copy both values into Bark, then save.")
    } catch {
      outcome = error.localizedDescription
    }
  }

  private func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    outcome =
      NSPasteboard.general.setString(value, forType: .string)
      ? t("Copied.") : t("Could not copy the Bark credential.")
  }

  private func sendTest() {
    var settings = model.push
    settings.server = server
    PushNotifier.send(
      settings: settings, credentials: credentials,
      title: "Perch", body: t("Bark test notification"))
    outcome = t("Test sent. Check your iPhone.")
  }

  private func save() {
    do {
      try model.updateBarkCredentials(credentials)
      var settings = model.push
      settings.server = server
      model.updatePush(settings)
      dismiss()
    } catch {
      outcome = error.localizedDescription
    }
  }
}

private struct BarkAppQRCode: View {
  static let destination = URL(
    string: "https://apps.apple.com/app/bark-customed-notifications/id1403753865")!

  private static let image: NSImage? = {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(destination.absoluteString.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage?.transformed(by: .init(scaleX: 5, y: 5)),
      let cgImage = CIContext().createCGImage(output, from: output.extent)
    else { return nil }
    return NSImage(cgImage: cgImage, size: NSSize(width: 84, height: 84))
  }()

  var body: some View {
    Group {
      if let image = Self.image {
        Image(nsImage: image)
          .interpolation(.none)
          .resizable()
      } else {
        Image(systemName: "qrcode")
          .resizable()
          .padding(12)
          .foregroundStyle(.black)
      }
    }
    .frame(width: 84, height: 84)
    .padding(5)
    .background(RoundedRectangle(cornerRadius: 7).fill(.white))
  }
}

private struct CustomJumpRuleSheet: View {
  let onAdd: (CustomJumpRule) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var terminal = ""
  @State private var bundleId = ""
  @State private var urlTemplate = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(t("Custom Jump Rule")).font(.title2.bold())
      TextField(t("TERM_PROGRAM value"), text: $terminal)
      TextField(t("Bundle identifier"), text: $bundleId)
      TextField(t("URL template"), text: $urlTemplate)
      Text(t("Placeholders: {session}, {tty}, {workspace}"))
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button(t("Cancel")) { dismiss() }
        Button(t("Add")) {
          onAdd(
            CustomJumpRule(
              terminal: terminal, bundleId: bundleId,
              urlTemplate: urlTemplate))
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!isValid)
      }
    }
    .padding(20)
    .frame(width: 420)
  }

  private var isValid: Bool {
    guard !terminal.trimmingCharacters(in: .whitespaces).isEmpty,
      !bundleId.trimmingCharacters(in: .whitespaces).isEmpty
    else { return false }
    var sample = urlTemplate
    for placeholder in ["{session}", "{tty}", "{workspace}"] {
      sample = sample.replacingOccurrences(of: placeholder, with: "sample")
    }
    return URL(string: sample)?.scheme != nil
  }
}

/// Where hooks are installed, read back from disk so the pane reports what is true rather
/// than what Perch believes it did.
struct HookSite {
  var title: String
  var path: String
  var isInstalled: Bool
  var eventCount: Int

  static func discover() -> [HookSite] {
    let home = NSHomeDirectory()
    var candidates: [(String, String)] = [
      (t("Claude Code (global)"), "\(home)/.claude/settings.json"),
      (t("Codex"), "\(home)/.codex/hooks.json"),
    ]

    // Project sites Perch recorded when it installed them.
    let registry = URL(fileURLWithPath: home).appendingPathComponent(".perch/hook-sites.json")
    if let data = try? Data(contentsOf: registry),
      let paths = try? JSONDecoder().decode([String].self, from: data)
    {
      for path in paths where !candidates.contains(where: { $0.1 == path }) {
        let project = URL(fileURLWithPath: path)
          .deletingLastPathComponent()
          .deletingLastPathComponent()
          .lastPathComponent
        candidates.append((project, path))
      }
    }

    return candidates.map { title, path in
      let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
      let events = text.components(separatedBy: "perch-hook").count - 1
      return HookSite(
        title: title, path: path, isInstalled: events > 0, eventCount: events)
    }
  }
}

private struct AgentIntegrationRow: View {
  let name: String
  let tool: DetectedTool?
  @Binding var enabled: Bool
  var configure: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: 8) {
      Text(name)
      Spacer()
      Image(systemName: tool?.isConfigured == true ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(tool?.isConfigured == true ? Color.green : Color.secondary)
      Text(status)
        .font(.caption)
        .foregroundStyle(.secondary)
      if tool?.isConfigured == false, let configure {
        Button(t("Install"), action: configure)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .tint(Color(hex: 0xFF8A34))
          .foregroundStyle(.white)
      } else {
        Toggle("", isOn: tool == nil ? .constant(false) : $enabled)
          .labelsHidden()
          .frame(width: 36)
          .disabled(tool == nil || tool?.isConfigured != true)
      }
    }
    .frame(minHeight: 27)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
    }
  }

  private var status: String {
    guard let tool else { return t("Unavailable") }
    return tool.isConfigured == true ? t("Active") : t("Detected")
  }
}

// MARK: - Composed settings panes

private struct NotificationsPane: View {
  let model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 32) {
      Section(
        t("Completion Notifications"),
        note: t("Approvals and questions are always shown immediately."),
        verticalPadding: 12
      ) {
        Toggle(isOn: quietBinding(\.autoExpandOnComplete)) {
          VStack(alignment: .leading, spacing: 2) {
            Text(t("Show completion notifications"))
            Text(t("Disable to keep the panel collapsed and show a subtle glow."))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Divider().overlay(Color.white.opacity(0.07))

        HStack {
          Text(t("Child agents and Agent Teams"))
          Spacer()
          VibeMenuPicker(
            title: t("Child agents and Agent Teams"), selection: childCompletionTiming,
            options: [
              VibePickerOption(value: .withMainReply, title: t("When main agent replies")),
              VibePickerOption(value: .immediately, title: t("Immediately")),
              VibePickerOption(value: .never, title: t("Never")),
            ])
        }
      }

      Section(t("Follow-up Reminders"), note: nil, verticalPadding: 12) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(t("Remind me after"))
            Text(t("A single reminder is sent after the selected delay. A state change cancels it; a foreground session stays silent."))
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer()
          VibeMenuPicker(
            title: t("Remind me after"), selection: followUpDelay,
            options: [
              VibePickerOption(value: .off, title: t("Off")),
              VibePickerOption(value: .fiveMinutes, title: t("5 minutes")),
              VibePickerOption(value: .tenMinutes, title: t("10 minutes")),
              VibePickerOption(value: .fifteenMinutes, title: t("15 minutes")),
              VibePickerOption(value: .thirtyMinutes, title: t("30 minutes")),
            ])
        }
        Divider().overlay(Color.white.opacity(0.07))
        Text(t("When enabled, include"))
          .font(.caption)
          .foregroundStyle(.secondary)
        Toggle(isOn: preferenceBinding(\.followUpApprovals)) {
          VStack(alignment: .leading, spacing: 2) {
            Text(t("Your response is required"))
            Text(t("Approvals and questions"))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .toggleStyle(.checkbox)
        .tint(Color.gray)
        .disabled(model.preferences.followUpDelay == .off)
        Toggle(isOn: preferenceBinding(\.followUpCompletedTasks)) {
          VStack(alignment: .leading, spacing: 2) {
            Text(t("Completed tasks"))
            Text(t("Only while unread"))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .toggleStyle(.checkbox)
        .tint(Color.gray)
        .disabled(model.preferences.followUpDelay == .off)
      }

      IntegrationsPane(model: model, scope: .notifications)

      Section(t("Quiet Scenes"), note: nil) {
        Toggle(t("A Focus mode is on"), isOn: quietBinding(\.duringFocus))
        Toggle(t("The screen is locked or asleep"), isOn: quietBinding(\.whenScreenObscured))
        Toggle(
          t("The screen is being recorded or shared"),
          isOn: quietBinding(\.whenScreenShared))
      }

      FiltersPane(model: model)
    }
    .padding(.top, 6)
  }

  private var childCompletionTiming: Binding<ChildCompletionTiming> {
    Binding(
      get: { model.preferences.childCompletionTiming },
      set: { value in
        var next = model.preferences
        next.childCompletionTiming = value
        model.updatePreferences(next)
      })
  }

  private var followUpDelay: Binding<FollowUpDelay> {
    Binding(
      get: { model.preferences.followUpDelay },
      set: { value in
        var next = model.preferences
        next.followUpDelay = value
        model.updatePreferences(next)
      })
  }

  private func preferenceBinding(_ path: WritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
    Binding(
      get: { model.preferences[keyPath: path] },
      set: { value in
        var next = model.preferences
        next[keyPath: path] = value
        model.updatePreferences(next)
      })
  }

  private func quietBinding(_ path: WritableKeyPath<QuietSettings, Bool>) -> Binding<Bool> {
    Binding(
      get: { model.quiet[keyPath: path] },
      set: { value in
        var next = model.quiet
        next[keyPath: path] = value
        model.updateQuiet(next)
      })
  }
}

private struct RemotePane: View {
  let model: AppModel
  @State private var addingHost = false
  @State private var editingHost: RemoteHost?
  @State private var codexHost: RemoteHost?
  @State private var removingHost: RemoteHost?
  @State private var outcome: String?
  @State private var showsDocker = false
  @State private var showsManual = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(
        t(
          "Monitor and approve remote AI CLI sessions from the notch. Add a host → Configure → Connect. Requires public-key SSH authentication (or ControlMaster for MFA)."
        )
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(SettingsStyle.card)
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(SettingsStyle.cardBorder, lineWidth: 1)))
      .padding(.bottom, 14)

      Section(t("Hosts"), note: nil, verticalPadding: 8) {
        if model.preferences.remoteHosts.isEmpty {
          HStack(spacing: 8) {
            Image(systemName: "network")
              .foregroundStyle(.secondary)
            Text(t("No hosts configured yet"))
              .foregroundStyle(.secondary)
          }
          Divider().overlay(Color.white.opacity(0.07))
          Button { addingHost = true } label: {
            Label(t("Add Host"), systemImage: "plus.circle.fill")
          }
          .buttonStyle(.plain)
        } else {
          ForEach(model.preferences.remoteHosts) { host in
            HStack(spacing: 10) {
              VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                HStack(spacing: 5) {
                  Circle()
                    .fill(statusColor(model.remoteTunnels.status(for: host)))
                    .frame(width: 6, height: 6)
                  Text(host.destination)
                  Text(model.remoteTunnels.status(for: host).title)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let error = host.lastDeployError {
                  Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                } else if let version = host.deployedHookVersion {
                  Text(t("Hook protocol v%lld", version))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                HStack(spacing: 6) {
                  Label(
                    t("%lld Codex roots", host.additionalCodexConfigRoots.count + 1),
                    systemImage: "folder.badge.gearshape")
                  Text("·")
                  Text(remoteCodexTrustLabel(host.remoteCodexHookTrust.state))
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
              }
              Spacer()
              if model.remoteTunnels.status(for: host) == .connected
                || model.remoteTunnels.status(for: host) == .connecting
              {
                Button(t("Disconnect")) { model.remoteTunnels.disconnect(host) }
              } else {
                Button(t("Connect")) {
                  model.remoteTunnels.connect(host, port: model.preferences.remotePort)
                }
              }
              Menu {
                Button(t("Edit")) { editingHost = host }
                Button(t("Configure")) { run("deploy", host: host) }
                Button(t("Codex roots…")) { codexHost = host }
                Divider()
                Button(t("Remove"), role: .destructive) { removingHost = host }
              } label: {
                Image(systemName: "ellipsis.circle")
              }
              .menuStyle(.borderlessButton)
              .fixedSize()
            }
          }
          Button(t("Add Host")) { addingHost = true }
        }
        Divider().overlay(Color.white.opacity(0.07))
        HStack {
          Text(t("TCP port"))
          Spacer()
          TextField("17891", value: remotePort, format: .number)
            .textFieldStyle(.roundedBorder)
            .frame(width: 72)
          Text(t("restart to apply"))
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      .padding(.bottom, -6)

      DisclosureGroup(isExpanded: $showsDocker) {
        Button(t("Copy Docker bridge command")) {
          RepoScripts.copyToPasteboard("./scripts/remote.sh docker")
        }
      } label: {
        Label(t("Docker Container"), systemImage: "shippingbox")
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(RoundedRectangle(cornerRadius: 10).fill(SettingsStyle.card))
      .padding(.bottom, -5)

      DisclosureGroup(isExpanded: $showsManual) {
        Button(t("Copy manual installation command")) {
          RepoScripts.copyToPasteboard("./scripts/remote.sh manual")
        }
      } label: {
        Label(t("Manual Installation (Restricted Networks)"), systemImage: "lock.shield")
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(RoundedRectangle(cornerRadius: 10).fill(SettingsStyle.card))

      if let outcome {
        Label(outcome, systemImage: "checkmark.circle.fill")
          .font(.caption)
          .foregroundStyle(Color.green)
      }
    }
    .sheet(isPresented: $addingHost) {
      AddRemoteHostSheet { host in add(host) }
    }
    .sheet(item: $editingHost) { host in
      AddRemoteHostSheet(host: host) { updated in update(updated) }
    }
    .sheet(item: $codexHost) { host in
      RemoteCodexRootsSheet(host: host) { roots, trust in
        updateCodexRoots(hostID: host.id, roots: roots, trust: trust)
        codexHost = nil
      }
    }
    .alert(
      t("Remove Remote Setup?"),
      isPresented: Binding(
        get: { removingHost != nil },
        set: { if !$0 { removingHost = nil } })
    ) {
      Button(t("Cancel"), role: .cancel) { removingHost = nil }
      Button(t("Remove"), role: .destructive) {
        guard let host = removingHost else { return }
        remove(host)
        removingHost = nil
      }
    } message: {
      Text(t("This removes Perch hooks and the tunnel configuration from the remote host."))
    }
    .padding(.top, 5)
  }

  private var remotePort: Binding<UInt16> {
    Binding(
      get: { model.preferences.remotePort },
      set: { value in
        var next = model.preferences
        next.remotePort = value
        model.updatePreferences(next)
      })
  }

  private func add(_ host: RemoteHost) {
    var next = model.preferences
    next.remoteHosts.append(host)
    model.updatePreferences(next)
    addingHost = false
    Task.detached {
      _ = RepoScripts.run(
        "remote.sh", ["add", host.name, host.destination, host.sshOptions],
        environment: ["PERCH_REMOTE_PORT": String(next.remotePort)])
    }
  }

  private func remove(_ host: RemoteHost) {
    model.remoteTunnels.disconnect(host)
    var next = model.preferences
    next.remoteHosts.removeAll { $0.id == host.id }
    model.updatePreferences(next)
    let port = next.remotePort
    Task.detached {
      _ = RepoScripts.run(
        "remote.sh", ["remove", host.name],
        environment: ["PERCH_REMOTE_PORT": String(port)])
    }
  }

  private func update(_ host: RemoteHost) {
    var next = model.preferences
    guard let index = next.remoteHosts.firstIndex(where: { $0.id == host.id }) else { return }
    next.remoteHosts[index] = host
    model.updatePreferences(next)
    editingHost = nil
    Task.detached {
      _ = RepoScripts.run(
        "remote.sh", ["add", host.name, host.destination, host.sshOptions],
        environment: ["PERCH_REMOTE_PORT": String(next.remotePort)])
    }
  }

  private func updateCodexRoots(
    hostID: UUID, roots: [String], trust: RemoteCodexHookTrustSnapshot
  ) {
    var next = model.preferences
    guard let index = next.remoteHosts.firstIndex(where: { $0.id == hostID }) else { return }
    next.remoteHosts[index].additionalCodexConfigRoots = roots
    next.remoteHosts[index].remoteCodexHookTrust = trust
    model.updatePreferences(next)
    outcome = t("Codex roots saved. Configure the host to apply them.")
  }

  private func updateRemoteCodexTrust(
    hostID: UUID, snapshot: RemoteCodexHookTrustSnapshot
  ) {
    var next = model.preferences
    guard let index = next.remoteHosts.firstIndex(where: { $0.id == hostID }) else { return }
    next.remoteHosts[index].remoteCodexHookTrust = snapshot
    model.updatePreferences(next)
  }

  private func remoteCodexTrustLabel(_ state: RemoteCodexHookTrustState) -> String {
    switch state {
    case .trusted: return t("Codex trusted")
    case .needsManualTrust: return t("Codex needs trust")
    case .unverified: return t("Codex trust unverified")
    }
  }

  private func run(_ action: String, host: RemoteHost) {
    outcome = t("%@ started for %@", action.capitalized, host.name)
    let port = model.preferences.remotePort
    Task {
      let success = await Task.detached {
        let deployed = RepoScripts.run(
          "remote.sh", [action, host.name],
          environment: ["PERCH_REMOTE_PORT": String(port)])
        guard deployed, action == "deploy" else { return deployed }
        let codexRoots = [RemoteCodexConfigRoot.defaultHome.path]
          + host.additionalCodexConfigRoots
        let encodedRoots = codexRoots.map { Data($0.utf8).base64EncodedString() }
        guard RepoScripts.run(
          "remote.sh", ["codex-setup", host.name] + encodedRoots,
          environment: ["PERCH_REMOTE_PORT": String(port)])
        else { return false }
        guard host.remoteClaudeUsageRelayEnabled else {
          return deployed
        }
        return RepoScripts.run(
          "remote.sh", ["usage", host.name],
          environment: ["PERCH_REMOTE_PORT": String(port)])
      }.value
      if action == "deploy" {
        model.recordRemoteDeployment(hostID: host.id, succeeded: success)
        if success {
          let verification = await RemoteCodexHookTrustService.verify(host: host)
          updateRemoteCodexTrust(hostID: host.id, snapshot: verification.snapshot)
        }
      }
      outcome = success
        ? t("%@ completed for %@", action.capitalized, host.name)
        : t("%@ failed for %@", action.capitalized, host.name)
    }
  }

  private func statusColor(_ status: RemoteTunnelStatus) -> Color {
    switch status {
    case .connected: return .green
    case .connecting: return .orange
    case .failed: return .red
    case .disconnected: return .secondary
    }
  }
}

private struct RemoteCodexRootsSheet: View {
  let host: RemoteHost
  let onSave: ([String], RemoteCodexHookTrustSnapshot) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var setup: RemoteCodexRootSetupModel
  @State private var manualPath = ""
  @State private var isDiscovering = false
  @State private var discoveryError: String?
  @State private var manualPathError: String?
  @State private var trust: RemoteCodexHookTrustSnapshot
  @State private var isCheckingTrust = false
  @State private var trustError: String?

  init(
    host: RemoteHost,
    onSave: @escaping ([String], RemoteCodexHookTrustSnapshot) -> Void
  ) {
    self.host = host
    self.onSave = onSave
    _setup = State(
      initialValue: RemoteCodexRootSetupModel(
        discovered: [], previouslySelected: host.additionalCodexConfigRoots))
    _trust = State(initialValue: host.remoteCodexHookTrust)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "folder.badge.gearshape")
          .font(.title2)
          .foregroundStyle(Color(hex: 0x60A5FA))
        VStack(alignment: .leading, spacing: 2) {
          Text(t("Codex configuration roots")).font(.title2.bold())
          Text(host.name).font(.caption).foregroundStyle(.secondary)
        }
      }
      .padding(20)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          Text(
            t(
              "Perch always monitors ~/.codex. Select additional Codex homes used by remote workspaces or Paperclip."
            )
          )
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

          VStack(spacing: 0) {
            ForEach(setup.rows) { row in
              Button {
                if row.path != RemoteCodexConfigRoot.defaultHome.path { setup.toggle(row.path) }
              } label: {
                HStack(spacing: 9) {
                  Image(
                    systemName: isSelected(row.path)
                      ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected(row.path) ? Color.blue : Color.secondary)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(row.path).font(.system(.body, design: .monospaced))
                    Text(sourceLabel(row.source)).font(.caption).foregroundStyle(.secondary)
                  }
                  Spacer(minLength: 8)
                  if row.path == RemoteCodexConfigRoot.defaultHome.path {
                    Text(t("Default")).font(.caption).foregroundStyle(.secondary)
                  }
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
              }
              .buttonStyle(.plain)
              if row.id != setup.rows.last?.id { Divider().padding(.leading, 42) }
            }
          }
          .background(RoundedRectangle(cornerRadius: 10).fill(SettingsStyle.card))
          .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(SettingsStyle.cardBorder, lineWidth: 1))

          HStack(spacing: 8) {
            TextField("/srv/agent/.codex", text: $manualPath)
              .textFieldStyle(.roundedBorder)
            Button(t("Add path")) { addManualPath() }
              .disabled(manualPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
          if let manualPathError {
            Text(manualPathError).font(.caption).foregroundStyle(.red)
          }

          HStack(spacing: 8) {
            Button {
              discover()
            } label: {
              if isDiscovering {
                ProgressView().controlSize(.small)
              } else {
                Label(t("Scan Paperclip roots"), systemImage: "arrow.clockwise")
              }
            }
            .disabled(isDiscovering)
            if let discoveryError {
              Text(discoveryError).font(.caption).foregroundStyle(.red)
            }
          }

          VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
              Image(
                systemName: trust.state == .trusted
                  ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
              Text(trustLabel).font(.callout.weight(.semibold))
              Spacer(minLength: 8)
              Button {
                checkTrust()
              } label: {
                if isCheckingTrust {
                  ProgressView().controlSize(.small)
                } else {
                  Text(t("Check Again"))
                }
              }
              .disabled(isCheckingTrust)
            }
            if trust.state == .needsManualTrust {
              Text(
                t(
                  "Open Codex on %@, run /hooks, trust the Perch hooks, then check again.",
                  host.name))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if trust.state == .unverified {
              Text(t("Codex hook trust could not be verified"))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let trustError {
              Text(trustError).font(.caption).foregroundStyle(.red)
            }
          }
          .foregroundStyle(trust.state == .trusted ? Color.green : Color.orange)
          .padding(12)
          .background(RoundedRectangle(cornerRadius: 10).fill(SettingsStyle.card))
          .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(SettingsStyle.cardBorder, lineWidth: 1))
        }
        .padding(20)
      }

      Divider()
      HStack {
        Spacer()
        Button(t("Cancel")) { dismiss() }
        Button(t("Save")) { onSave(setup.selectedAdditionalRoots, trust) }
          .keyboardShortcut(.defaultAction)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
    }
    .frame(width: 560, height: 580)
  }

  private func isSelected(_ path: String) -> Bool {
    path == RemoteCodexConfigRoot.defaultHome.path || setup.selectedPaths.contains(path)
  }

  private func sourceLabel(_ source: RemoteCodexConfigRootSource) -> String {
    switch source {
    case .paperclip: return t("Discovered from Paperclip")
    case .manual: return t("Added manually")
    case .saved: return t("Saved configuration")
    }
  }

  private var trustLabel: String {
    switch trust.state {
    case .trusted: return t("Remote Codex hook trusted")
    case .needsManualTrust: return t("Remote Codex hook needs manual trust")
    case .unverified: return t("Remote Codex hook trust has not been checked")
    }
  }

  private func checkTrust() {
    isCheckingTrust = true
    trustError = nil
    var probeHost = host
    probeHost.additionalCodexConfigRoots = setup.selectedAdditionalRoots
    Task {
      let result = await RemoteCodexHookTrustService.verify(host: probeHost)
      trust = result.snapshot
      trustError = result.error
      isCheckingTrust = false
    }
  }

  private func addManualPath() {
    guard setup.addManualPath(manualPath) else {
      manualPathError = t("Enter an absolute remote path.")
      return
    }
    manualPath = ""
    manualPathError = nil
  }

  private func discover() {
    isDiscovering = true
    discoveryError = nil
    let alias = host.name
    Task {
      let result = await Task.detached {
        RepoScripts.runCapturing("remote.sh", ["codex-roots", alias])
      }.value
      isDiscovering = false
      guard result.succeeded else {
        discoveryError = result.failure
        return
      }
      do {
        let discovered = try JSONDecoder().decode(
          [RemoteCodexConfigRootCandidate].self, from: Data(result.stdout.utf8))
        setup = RemoteCodexRootSetupModel(
          discovered: discovered,
          previouslySelected: Array(setup.selectedPaths))
      } catch {
        discoveryError = t("The remote Codex scan returned invalid data.")
      }
    }
  }
}

private struct AddRemoteHostSheet: View {
  let host: RemoteHost?
  let onAdd: (RemoteHost) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var alias: String
  @State private var remoteHost: String
  @State private var remoteUser: String
  @State private var sshOptions: String
  @State private var manualConnectionOnly: Bool
  @State private var autoUpdateHooks: Bool
  @State private var remoteClaudeUsageRelayEnabled: Bool
  @State private var remoteCodexUsageProbeEnabled: Bool

  init(host: RemoteHost? = nil, onAdd: @escaping (RemoteHost) -> Void) {
    self.host = host
    self.onAdd = onAdd
    let destination = host?.destination ?? ""
    let parts = destination.split(separator: "@", maxSplits: 1).map(String.init)
    _alias = State(initialValue: host?.name ?? "")
    _remoteUser = State(initialValue: parts.count == 2 ? parts[0] : "")
    _remoteHost = State(initialValue: parts.count == 2 ? parts[1] : destination)
    _sshOptions = State(initialValue: host?.sshOptions ?? "")
    _manualConnectionOnly = State(initialValue: host?.manualConnectionOnly ?? false)
    _autoUpdateHooks = State(initialValue: host?.autoUpdateHooks ?? true)
    _remoteClaudeUsageRelayEnabled = State(
      initialValue: host?.remoteClaudeUsageRelayEnabled ?? true)
    _remoteCodexUsageProbeEnabled = State(
      initialValue: host?.remoteCodexUsageProbeEnabled ?? false)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "network")
          .foregroundStyle(Color(hex: 0x32C8D8))
          .font(.title2)
        Text(t(host == nil ? "Add Host" : "Edit Host"))
          .font(.title2.bold())
      }
      .padding(.horizontal, 20)
      .padding(.top, 18)
      .padding(.bottom, 14)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Section(t("Connection"), note: nil, verticalPadding: 9) {
            SettingsTextFieldRow(title: t("Alias"), prompt: "build-box", text: $alias)
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 5) {
                Text(t("User")).font(.caption).foregroundStyle(.secondary)
                TextField("deploy", text: $remoteUser)
                  .textFieldStyle(.roundedBorder)
              }
              VStack(alignment: .leading, spacing: 5) {
                Text(t("Host")).font(.caption).foregroundStyle(.secondary)
                TextField("10.0.0.5", text: $remoteHost)
                  .textFieldStyle(.roundedBorder)
              }
            }
          }

          Section(t("Advanced SSH Options"), note: nil, verticalPadding: 9) {
            TextField("-p 2222 -i ~/.ssh/id_work", text: $sshOptions)
              .textFieldStyle(.roundedBorder)
            Text(t("Common options: identity key, non-standard port, jump host, ProxyCommand, or ControlMaster for MFA."))
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }

          Section(t("Behaviour"), note: nil, verticalPadding: 9) {
            Toggle(isOn: $manualConnectionOnly) {
              VStack(alignment: .leading, spacing: 2) {
                Text(t("Connect manually only"))
                Text(t("Disable automatic connection and reconnection for this host."))
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
            Divider().overlay(Color.white.opacity(0.07))
            Toggle(isOn: $autoUpdateHooks) {
              VStack(alignment: .leading, spacing: 2) {
                Text(t("Keep remote hooks up to date"))
                Text(t("Redeploy the hook after an app update when this host reconnects."))
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
          }

          Section(t("Remote usage (optional)"), note: nil, verticalPadding: 9) {
            Toggle(isOn: $remoteClaudeUsageRelayEnabled) {
              VStack(alignment: .leading, spacing: 2) {
                Text(t("Relay Claude usage"))
                Text(t("Relay Claude limits from this host's statusline."))
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
            Divider().overlay(Color.white.opacity(0.07))
            Toggle(isOn: $remoteCodexUsageProbeEnabled) {
              VStack(alignment: .leading, spacing: 2) {
                Text(t("Probe Codex usage"))
                Text(t("Probe this host's Codex account only when Codex activity is seen."))
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
        .padding(20)
      }

      Divider()

      HStack {
        Spacer()
        Button(t("Cancel")) { dismiss() }
        Button(t(host == nil ? "Add Host" : "Save")) {
          onAdd(
            RemoteHost(
              id: host?.id ?? UUID(), name: alias.trimmingCharacters(in: .whitespaces),
              destination: destination, sshOptions: sshOptions,
              manualConnectionOnly: manualConnectionOnly, autoUpdateHooks: autoUpdateHooks,
              remoteClaudeUsageRelayEnabled: remoteClaudeUsageRelayEnabled,
              remoteCodexUsageProbeEnabled: remoteCodexUsageProbeEnabled,
              deployed: host?.deployed ?? false,
              lastDeployedAt: host?.lastDeployedAt,
              lastDeployError: host?.lastDeployError,
              deployedHookVersion: host?.deployedHookVersion,
              remoteCodexHookTrust: host?.remoteCodexHookTrust ?? .init(),
              additionalCodexConfigRoots: host?.additionalCodexConfigRoots ?? []))
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!canSubmit)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 14)
    }
    .frame(width: 520, height: 620)
  }

  private var destination: String {
    let user = remoteUser.trimmingCharacters(in: .whitespaces)
    let hostname = remoteHost.trimmingCharacters(in: .whitespaces)
    return user.isEmpty ? hostname : "\(user)@\(hostname)"
  }

  private var canSubmit: Bool {
    !alias.trimmingCharacters(in: .whitespaces).isEmpty
      && !remoteHost.trimmingCharacters(in: .whitespaces).isEmpty
  }
}

private struct SettingsTextFieldRow: View {
  let title: String
  let prompt: String
  @Binding var text: String

  var body: some View {
    HStack {
      Text(title)
      Spacer()
      TextField(prompt, text: $text)
        .textFieldStyle(.roundedBorder)
        .frame(width: 250)
    }
  }
}

private struct SettingsActionRow: View {
  let symbol: String
  let title: String
  let detail: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .foregroundStyle(Color.white.opacity(0.58))
          .frame(width: 18)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).foregroundStyle(.primary)
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer()
        Image(systemName: "doc.on.doc")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - About

private struct AboutPane: View {
  var model: AppModel?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(spacing: 8) {
        Image(nsImage: NSApplication.shared.applicationIconImage)
          .resizable()
          .scaledToFit()
          .frame(width: 64, height: 64)
        Text("Perch")
          .font(.system(size: 17, weight: .bold))
        Text("v\(version)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.top, 10)
      .padding(.bottom, 4)

      Section("", note: nil, verticalPadding: 0) {
        if let updates = model?.updates, let item = updates.available {
          HStack {
            Text(t("Version %@ is available", item.version))
            Spacer()
            Button(t("Update and relaunch")) {
              Task { await updates.install(item) }
            }
            .disabled(updates.isInstalling)
            if updates.isInstalling { ProgressView().controlSize(.small) }
          }
        } else {
          Button {
            guard let updates = model?.updates else { return }
            Task { await updates.check() }
          } label: {
            Label(t("Check for Updates"), systemImage: "arrow.triangle.2.circlepath")
          }
          .buttonStyle(.plain)
          .disabled(model?.updates.isConfigured != true)
          Divider().overlay(Color.white.opacity(0.07))
          Link(destination: URL(string: "https://github.com/dev-toolings/perch/releases")!) {
            HStack {
              Label(t("Release Notes"), systemImage: "doc.text")
              Spacer()
              Text("v\(version)").foregroundStyle(.secondary)
              Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
          }
        }
        Divider().overlay(Color.white.opacity(0.07))
        Toggle(isOn: automaticUpdateChecks) {
          VStack(alignment: .leading, spacing: 2) {
            Text(t("Automatically check for updates"))
            Text(t("When disabled, new versions are checked only with Check for Updates."))
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        Divider().overlay(Color.white.opacity(0.07))
        Toggle(isOn: automaticUpdateInstalls) {
          VStack(alignment: .leading, spacing: 2) {
            Text(t("Install updates automatically"))
            Text(t("When disabled, an update button appears in the panel when a release is ready."))
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        if let error = model?.updates.lastError {
          Text(error).font(.callout).foregroundStyle(.orange)
        }
      }

      Section("", note: nil, verticalPadding: 8) {
        AboutLinkRow(
          title: t("Website"), symbol: "globe", trailing: "github.com/dev-toolings/perch",
          destination: URL(string: "https://github.com/dev-toolings/perch")!)
        aboutDivider
        AboutLinkRow(
          title: t("Creator"), symbol: "person", trailing: "dev-toolings",
          destination: URL(string: "https://github.com/dev-toolings")!)
        aboutDivider
        AboutLinkRow(
          title: t("Join the Community"), symbol: "bubble.left.and.bubble.right",
          destination: URL(string: "https://github.com/dev-toolings/perch/discussions")!)
        aboutDivider
        AboutLinkRow(
          title: t("Report a Bug"), symbol: "ladybug", trailing: "GitHub",
          destination: URL(string: "https://github.com/dev-toolings/perch/issues")!)
        aboutDivider
        AboutLinkRow(
          title: t("Send Feedback"), symbol: "envelope", trailing: "GitHub",
          destination: URL(string: "https://github.com/dev-toolings/perch/discussions/new/choose")!)
      }

      Section("", note: nil) {
        Button(t("Export Diagnostic Report")) { exportDiagnosticReport() }
          .disabled(model == nil)
        Text(
          t(
            "Includes system information and diagnostic logs. Review the report before sharing it.")
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        Divider().overlay(Color.white.opacity(0.07))
        Button(t("Acknowledgements")) { showAcknowledgements() }
        Divider().overlay(Color.white.opacity(0.07))
        UninstallRow()
        Divider().overlay(Color.white.opacity(0.07))
        Button(t("Quit Perch")) { NSApplication.shared.terminate(nil) }
      }
    }
  }

  private var version: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
  }

  private var aboutDivider: some View {
    Divider().overlay(Color.white.opacity(0.07))
  }

  private var automaticUpdateChecks: Binding<Bool> {
    Binding(
      get: { model?.preferences.automaticallyChecksForUpdates ?? true },
      set: { value in
        guard var next = model?.preferences else { return }
        next.automaticallyChecksForUpdates = value
        model?.updatePreferences(next)
      })
  }

  private var automaticUpdateInstalls: Binding<Bool> {
    Binding(
      get: { model?.preferences.automaticallyInstallsUpdates ?? true },
      set: { value in
        guard var next = model?.preferences else { return }
        next.automaticallyInstallsUpdates = value
        model?.updatePreferences(next)
      })
  }

  private func exportDiagnosticReport() {
    guard let model else { return }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Perch-diagnostic.txt"
    guard panel.runModal() == .OK, let destination = panel.url else { return }
    do {
      try model.diagnosticReport().write(
        to: destination, atomically: true, encoding: .utf8)
    } catch {
      let alert = NSAlert(error: error)
      alert.messageText = t("Could not export the diagnostic report")
      alert.runModal()
    }
  }

  private func showAcknowledgements() {
    let alert = NSAlert()
    alert.messageText = t("Acknowledgements")
    alert.informativeText = "Swift, SwiftUI, SQLite, Sparkle-compatible updates, Departure Mono"
    alert.runModal()
  }
}

private struct AboutLinkRow: View {
  let title: String
  let symbol: String
  var trailing: String? = nil
  let destination: URL

  var body: some View {
    Link(destination: destination) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .frame(width: 17)
        Text(title)
          .foregroundStyle(.primary)
        Spacer(minLength: 8)
        if let trailing {
          Text(trailing)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Image(systemName: "arrow.up.right")
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(.tertiary)
      }
      .frame(minHeight: 24)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// Uninstalling, from inside the app, because that is where someone looks for it.
///
/// Dragging Perch to the Trash removes the app and nothing else: fourteen hook entries go
/// on pointing at a binary that is no longer there, the statusline bridge goes on wrapping
/// your statusline, and the uninstaller that would have fixed both went into the Trash with
/// the bundle it lives in. The order that works — uninstall, *then* delete — is the
/// opposite of the macOS reflex, so the button is the one place it can be offered at the
/// right moment.
private struct UninstallRow: View {
  @State private var outcome: String?

  private var script: URL? {
    let stashed = RepoScripts.stashedUninstaller
    // The copy outside the bundle first: the script deletes Perch.app, and a shell
    // reading itself out of a directory being removed is not something to rely on.
    if FileManager.default.isExecutableFile(atPath: stashed.path) { return stashed }
    return RepoScripts.url(of: "uninstall.sh")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Button(t("Uninstall Perch…")) { confirm() }
          .disabled(script == nil)
        Text(
          t(
            "Removes the hooks, restores your statusline, and deletes Perch. "
              + "Dragging the app to the Trash does none of that.")
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      if let outcome {
        Text(outcome).font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func confirm() {
    guard let script else { return }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = t("Uninstall Perch?")
    // What it will do, in the order it will do it, rather than "are you sure".
    alert.informativeText = t(
      "Perch will quit, its hooks will be removed from Claude Code and Codex, your "
        + "original statusline will be restored, and the app will be deleted.\n\n"
        + "Your token history is kept, and every settings file is backed up before "
        + "it is changed.\n\n%@",
      script.path)
    alert.addButton(withTitle: t("Uninstall"))
    alert.addButton(withTitle: t("Cancel"))
    alert.addButton(withTitle: t("Copy the command"))

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      let log = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("perch-uninstall.log")
      // Detached: the script quits Perch a second from now, and waiting for it would
      // be waiting from inside the process it is about to kill.
      if RepoScripts.start(script, ["--yes"], log: log) {
        outcome = t("Uninstalling — Perch will quit. Output: %@", log.path)
      } else {
        outcome = t("Could not start the uninstaller. Run it yourself: %@", script.path)
      }
    case .alertThirdButtonReturn:
      RepoScripts.copyToPasteboard("\(script.path) --yes")
      outcome = t("Copied. Run it in a terminal.")
    default:
      break
    }
  }
}

// MARK: - Shared

private struct NotchSettingsPreview: View {
  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .top) {
        wallpaper
          .frame(width: proxy.size.width, height: 100)
          .clipped()

        HStack(spacing: 4) {
          VibePet(status: .idle)
            .frame(width: 24, height: 12)
          Text("Recopier la vibe Island dans Perch")
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
          Text("2")
            .foregroundStyle(.white)
        }
        .font(Theme.mono(9))
        .lineLimit(1)
        .padding(.horizontal, 7)
        .frame(width: 194, height: 28)
        .background(
          UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: 8,
            bottomTrailingRadius: 8, topTrailingRadius: 0
          )
          .fill(Color.black))
      }
    }
    .frame(height: 100)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  @ViewBuilder
  private var wallpaper: some View {
    if let path = Bundle.main.path(forResource: "onboarding-wallpaper", ofType: "jpg"),
      let image = NSImage(contentsOfFile: path)
    {
      Image(nsImage: image)
        .resizable()
        .scaledToFill()
    } else {
      Color.black
    }
  }
}

private struct SessionCardSettingsPreview: View {
  let preferences: Preferences

  private var session: SessionSnapshot {
    var value = SessionSnapshot(
      id: "settings-preview", cwd: "/tmp/vibe-island/worktrees/chat-ui",
      lastEvent: .now, lastDetail: "Editing chatEndpoint.ts · 12s",
      status: .runningTool, subagents: 2,
      startedAt: .now.addingTimeInterval(-12))
    value.aiTitle = "Refactor auth flow"
    value.agent = .claude
    value.client = ClientInfo(terminal: "ghostty")
    value.prompt = "extract chatEndpoint into a transport-agnostic layer"
    return value
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      if preferences.showsWorktree {
        Text("vibe-island  ⎇  chat-ui")
          .font(Theme.mono(preferences.contentFontSize - 2))
          .foregroundStyle(Theme.tertiary)
      }
      if preferences.showsReasoningEffort {
        Text(t("Reasoning: High"))
          .font(Theme.mono(preferences.contentFontSize - 2))
          .foregroundStyle(Theme.tertiary)
      }
      SessionCardView(
        session: session,
        layout: .detailed,
        contentFontSize: preferences.contentFontSize,
        showsProjectName: preferences.showsProjectName,
        showsAIModel: preferences.showsAIModel,
        showsTasks: preferences.showsTasks,
        showsSubagents: preferences.showsSubagents,
        showsActivityDetails: preferences.showsActivityDetails,
        isActive: true,
        isCollapsed: false)
    }
    .padding(.top, 2)
  }
}

private struct SettingsValueSlider: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let suffix: String

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(title)
        Spacer()
        Text("\(Int(value))\(suffix)")
          .font(Theme.mono(10))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(
            RoundedRectangle(cornerRadius: 7)
              .stroke(Color.white.opacity(0.14), lineWidth: 1))
      }
      Slider(value: $value, in: range, step: 10)
        .vibeSliderTrack(value: value, in: range)
    }
    // Vibe gives each sizing control a full row, with the extra breathing room below
    // the track. Keeping it on the bottom preserves the measured title/track alignment
    // while matching the 73pt cadence between successive slider labels.
    .padding(.bottom, 21)
  }
}

private struct VibeSliderTrack: ViewModifier {
  let value: Double
  let range: ClosedRange<Double>

  func body(content: Content) -> some View {
    content
      .tint(Color(hex: 0x0A84FF))
      .accentColor(Color(hex: 0x0A84FF))
      .overlay {
        GeometryReader { proxy in
          let raw = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
          let fraction = min(max(raw, 0), 1)
          Capsule()
            .fill(Color(hex: 0x0A84FF))
            .frame(width: max(0, 8 + (proxy.size.width - 16) * fraction), height: 3)
            .offset(y: (proxy.size.height - 3) / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
  }
}

private extension View {
  func vibeSliderTrack(value: Double, in range: ClosedRange<Double>) -> some View {
    modifier(VibeSliderTrack(value: value, range: range))
  }
}

private struct VibePickerOption<Value: Hashable>: Identifiable {
  let value: Value
  let title: String
  var id: Value { value }
}

/// Vibe's settings pop-up control: a plain value followed by one compact circular
/// up/down indicator, instead of AppKit's full-width rounded menu capsule.
private struct VibeMenuPicker<Value: Hashable>: View {
  let title: String
  @Binding var selection: Value
  let options: [VibePickerOption<Value>]

  private var selectedTitle: String {
    options.first(where: { $0.value == selection })?.title ?? ""
  }

  var body: some View {
    Menu {
      ForEach(options) { option in
        Button {
          selection = option.value
        } label: {
          if option.value == selection {
            Label(option.title, systemImage: "checkmark")
          } else {
            Text(option.title)
          }
        }
      }
    } label: {
      HStack(spacing: 7) {
        Text(selectedTitle)
          .foregroundStyle(.primary)
        Color.clear
          .frame(width: 18, height: 18)
          .accessibilityHidden(true)
      }
        .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .overlay(alignment: .trailing) {
      Image(systemName: "chevron.up.chevron.down")
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(.secondary)
        .frame(width: 18, height: 18)
        .background(Circle().fill(Color.white.opacity(0.09)))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    .fixedSize()
    .accessibilityLabel(title)
    .accessibilityValue(selectedTitle)
  }
}

private struct PanelLayoutPreview: View {
  @Binding var selection: PanelLayout

  var body: some View {
    HStack(spacing: 10) {
      preview(.clean)
      preview(.detailed)
    }
    .padding(.top, 10)
    .padding(.bottom, 14)
  }

  private func preview(_ option: PanelLayout) -> some View {
    Button {
      selection = option
    } label: {
      VStack(spacing: 6) {
        PanelDensityMiniature(isDetailed: option == .detailed)
        Text(t(option.title))
          .font(.system(size: 12, weight: .semibold))
        Text(
          option == .clean
            ? t("More room for the menu bar") : t("Session titles and status at a glance")
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 68)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(Color.black.opacity(0.12))
          .overlay(
            RoundedRectangle(cornerRadius: 8)
              .stroke(
                selection == option ? Color.accentColor : Color.white.opacity(0.06),
                lineWidth: selection == option ? 1.5 : 1)))
    }
    .buttonStyle(.plain)
  }
}

/// The two tiny session strips measured in Vibe's density picker. They preview density,
/// rather than using an abstract SF Symbol that says nothing about the resulting panel.
private struct PanelDensityMiniature: View {
  let isDetailed: Bool

  var body: some View {
    HStack(spacing: 3) {
      Circle()
        .fill(Theme.active)
        .frame(width: 4, height: 4)
      RoundedRectangle(cornerRadius: 1)
        .fill(Color.white.opacity(0.22))
        .frame(width: isDetailed ? 48 : 18, height: 3)
      Spacer(minLength: 2)
      Text("2")
        .font(Theme.mono(6, .medium))
        .foregroundStyle(Color.white.opacity(0.42))
    }
    .padding(.horizontal, 5)
    .frame(width: isDetailed ? 88 : 56, height: 16)
    .background(
      RoundedRectangle(cornerRadius: 3)
        .fill(Color.black.opacity(0.18)))
  }
}

private struct ShortcutLegendRow: View {
  let title: String
  let keys: String
  var caption: String? = nil

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        if let caption {
          Text(caption).font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer()
      HStack(spacing: 5) {
        ForEach(Array(keyParts.enumerated()), id: \.offset) { index, key in
          if index > 0 { Text("+").font(.caption).foregroundStyle(.tertiary) }
          Text(key)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
              RoundedRectangle(cornerRadius: 7)
                .fill(Color.black.opacity(0.18)))
        }
      }
    }
  }

  private var keyParts: [String] {
    keys.components(separatedBy: " + ")
  }
}

private struct Section<Content: View>: View {
  let title: String
  let note: String?
  let verticalPadding: CGFloat
  @ViewBuilder let content: Content

  init(
    _ title: String, note: String?, verticalPadding: CGFloat = 10,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.note = note
    self.verticalPadding = verticalPadding
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 13, weight: .bold))
      VStack(alignment: .leading, spacing: 10) {
        content
      }
      .padding(.horizontal, 10)
      .padding(.vertical, verticalPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(SettingsStyle.card)
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .stroke(SettingsStyle.cardBorder, lineWidth: 1)))
      if let note {
        Text(note)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
