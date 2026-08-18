import AppKit
import PerchKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = NotchController()
    private lazy var model = AppModel(notch: controller)
    /// Held for the process's lifetime: `UNUserNotificationCenter` keeps its delegate
    /// weakly, and a router that deallocates turns every notification click into nothing.
    private let notifications = NotificationRouter()

    @objc func openSettingsFromMenu() {
        _ = model.showSettings()
    }

    @objc func quitFromMenu() {
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The one line that has to be there whether or not anything goes wrong.
        //
        // Every other call into `PerchLog` is on a failure path, which means a log file
        // that only exists once the app has already broken — and a crash reconstructed
        // from it could not tell "started at 21:03 and died" from "never started". A
        // launch is also the only place the version and the pid are both known, and the
        // pid is what ties a line here to a `.ips` report.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        PerchLog.info(
            "Perch \(version ?? "?") launched, pid \(ProcessInfo.processInfo.processIdentifier)")

        UNUserNotificationCenter.current().delegate = notifications
        model.start()
        controller.start(content: NotchRootView(controller: controller, model: model))
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Paired with the launch line: a log that ends here records a quit, and a log that
        // ends without it records a death. That difference is the whole question being
        // asked of this file after a crash, and nothing else in the app answers it.
        PerchLog.info("Perch is quitting")
        // Leaving a stale runtime.json behind would make every hook wait for a timeout.
        model.stop()
        // After the stop, so anything it logs on the way down is included: an `info` is
        // written on a queue this process is about to stop draining.
        PerchLog.flush()
    }
}

// Before `NSApplication`, not merely before the first window: AppKit resolves the bundle's
// localisation as it starts up, and a language written after that lands one launch late.
// English is the default whatever the Mac is set to.
applyLanguagePreference()

let application = NSApplication.shared

if CommandLine.arguments.contains("--diagnose") {
    Diagnostics.run()
    exit(0)
}

if CommandLine.arguments.contains("--status") {
    exit(Diagnostics.status())
}

if CommandLine.arguments.contains("--codex") {
    exit(Diagnostics.codex())
}

if CommandLine.arguments.contains("--index") {
    exit(Diagnostics.index())
}

if CommandLine.arguments.contains("--report") {
    exit(Diagnostics.report())
}

if CommandLine.arguments.contains("--update") {
    exit(Diagnostics.update(install: CommandLine.arguments.contains("--install")))
}

if CommandLine.arguments.contains("--reveal") {
    exit(Diagnostics.reveal())
}

if CommandLine.arguments.contains("--expand") {
    exit(Diagnostics.expand())
}

if CommandLine.arguments.contains("--settings") {
    exit(Diagnostics.settings())
}

if CommandLine.arguments.contains("--onboarding") {
    exit(Diagnostics.onboarding())
}

if CommandLine.arguments.contains("--forget-login-item") {
    exit(Diagnostics.forgetLoginItem())
}

if let index = CommandLine.arguments.firstIndex(of: "--render") {
    let path =
        CommandLine.arguments.count > index + 1
        ? CommandLine.arguments[index + 1] : "perch-panel.png"
    exit(
        Diagnostics.render(
            path, layout: CommandLine.arguments.contains("--clean") ? .clean : .detailed,
            // `--render x.png --idle` draws the resting strip instead of the panel, and
            // `--phases` draws every state in its own shape, over a menu bar.
            idle: CommandLine.arguments.contains("--idle"),
            phases: CommandLine.arguments.contains("--phases"),
            // `--plan` draws the plan card on its own, at the width the panel gives it.
            plan: CommandLine.arguments.contains("--plan"),
            // `--render x.png --stats opencode` draws the Stats pane for one agent, off
            // this machine's own index. The tabs are the one part of that pane no
            // fabricated scene can stand in for: whether they are right is a question
            // about what was actually indexed here.
            stats: CommandLine.arguments.firstIndex(of: "--stats").map { index in
                CommandLine.arguments.count > index + 1
                    ? UsageStore.Agent(rawValue: CommandLine.arguments[index + 1]) ?? .claude
                    : .claude
            },
            // `--render x.png --settings-pane display --width 1000` draws one Settings
            // pane as the window would at that width, without the window.
            settings: CommandLine.arguments.firstIndex(of: "--settings-pane").flatMap { index in
                CommandLine.arguments.count > index + 1
                    ? SettingsView.Pane.allCases.first {
                        $0.rawValue.lowercased() == CommandLine.arguments[index + 1].lowercased()
                    }
                    : nil
            },
            windowWidth: CommandLine.arguments.firstIndex(of: "--width").flatMap { index in
                CommandLine.arguments.count > index + 1
                    ? Double(CommandLine.arguments[index + 1]).map { CGFloat($0) } : nil
            } ?? 620))
}

if let index = CommandLine.arguments.firstIndex(of: "--tasks") {
    let session = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : ""
    exit(Diagnostics.tasks(session))
}

if let index = CommandLine.arguments.firstIndex(of: "--answer") {
    let labels = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : ""
    exit(Diagnostics.answer(labels))
}

if let index = CommandLine.arguments.firstIndex(of: "--rank") {
    exit(LeaderboardCLI.run(Array(CommandLine.arguments.dropFirst(index + 1))))
}

if let index = CommandLine.arguments.firstIndex(of: "--decide") {
    let decision = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : ""
    exit(Diagnostics.decide(decision, remember: CommandLine.arguments.contains("--remember")))
}

let delegate = AppDelegate()
application.delegate = delegate
application.mainMenu = makeMainMenu(delegate: delegate)
// No Dock icon: Perch lives in the notch. Like Vibe Island, it still exposes the normal
// macOS menu while one of its windows is active.
application.setActivationPolicy(.accessory)
application.run()

@MainActor
private func makeMainMenu(delegate: AppDelegate) -> NSMenu {
    let main = NSMenu()

    let appItem = NSMenuItem()
    let appMenu = NSMenu(title: "Perch")
    let settings = NSMenuItem(
        title: t("Settings…"), action: #selector(AppDelegate.openSettingsFromMenu),
        keyEquivalent: ",")
    settings.target = delegate
    appMenu.addItem(settings)
    appMenu.addItem(.separator())
    let quit = NSMenuItem(
        title: t("Quit Perch"), action: #selector(AppDelegate.quitFromMenu), keyEquivalent: "q")
    quit.target = delegate
    appMenu.addItem(quit)
    appItem.submenu = appMenu
    main.addItem(appItem)

    let editItem = NSMenuItem()
    let editMenu = NSMenu(title: t("Edit"))
    for (title, action, key) in [
        (t("Undo"), Selector(("undo:")), "z"),
        (t("Redo"), Selector(("redo:")), "Z"),
        (t("Cut"), #selector(NSText.cut(_:)), "x"),
        (t("Copy"), #selector(NSText.copy(_:)), "c"),
        (t("Paste"), #selector(NSText.paste(_:)), "v"),
        (t("Select All"), #selector(NSText.selectAll(_:)), "a"),
    ] {
        editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
    }
    editItem.submenu = editMenu
    main.addItem(editItem)

    for title in [t("View"), t("Window"), t("Help")] {
        let item = NSMenuItem()
        item.submenu = NSMenu(title: title)
        main.addItem(item)
    }
    return main
}
