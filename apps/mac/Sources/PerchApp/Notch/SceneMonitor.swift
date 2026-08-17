import AppKit
import CoreGraphics
import Foundation
import Observation
import PerchKit

/// Watches what the machine is doing that Perch should not interrupt: the screen locked
/// or asleep, a screen recording or share in progress, a Focus mode on.
///
/// All three are read rather than subscribed to where macOS gives no notification, which
/// is why the value is recomputed on demand instead of pushed.
@MainActor
@Observable
final class SceneMonitor {
    private(set) var scene = Scene()

    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    func start() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            observers.append(
                center.addObserver(forName: .init(name), object: nil, queue: .main) {
                    [weak self] _ in
                    Task { @MainActor in self?.scene.isScreenObscured = true }
                })
        }
        for name in ["com.apple.screenIsUnlocked", "com.apple.screensaver.didstop"] {
            observers.append(
                center.addObserver(forName: .init(name), object: nil, queue: .main) {
                    [weak self] _ in
                    Task { @MainActor in self?.scene.isScreenObscured = false }
                })
        }

        // Display and system sleep are not lock events, but they mean the same thing to
        // Perch: nobody is watching the screen. These live on the workspace centre, not the
        // distributed one, and drive the same field the lock observers do.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification,
        ] {
            workspaceObservers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    Task { @MainActor in self?.scene.isScreenObscured = true }
                })
        }
        for name in [
            NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification,
        ] {
            workspaceObservers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    Task { @MainActor in self?.scene.isScreenObscured = false }
                })
        }

        refresh()
    }

    func stop() {
        for observer in observers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    /// Called before anything that would take the screen.
    func refresh() {
        scene.isScreenShared = Self.isScreenBeingCaptured()
        scene.isFocusActive = Self.isFocusActive()
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        scene.frontmostBundleId = frontmost
        scene.frontmostSurfaceIds = frontmost == Self.cmuxBundleId ? Self.cmuxFocusedIds() : []
    }

    private static let cmuxBundleId = "com.cmuxterm.app"

    /// Which pane cmux has in front, asked of its own CLI over its local socket — about
    /// 18 ms, and only ever when cmux is the frontmost app. Empty when the CLI is not
    /// where the app installs it, or does not answer in time; the scene then falls back
    /// to the bundle id alone, which is what it always had.
    private static func cmuxFocusedIds() -> Set<String> {
        let candidates = [
            "/Applications/cmux.app/Contents/Resources/bin/cmux",
            NSHomeDirectory() + "/Applications/cmux.app/Contents/Resources/bin/cmux",
        ]
        guard let cli = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = ["--id-format", "uuids", "identify", "--no-caller"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        // Bounded: a hung socket must not hold the hook that is waiting on this answer.
        let deadline = Date().addingTimeInterval(0.25)
        while process.isRunning, Date() < deadline { usleep(5_000) }
        guard !process.isRunning else {
            process.terminate()
            return []
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return CmuxFocus.surfaceIds(fromIdentifyJSON: data)
    }

    /// Whether the frontmost app owns a normal window that fills a display exactly.
    /// Maximised windows leave room for the menu bar or Dock; native fullscreen windows
    /// cover the display frame, so this does not mistake one for the other.
    static func frontmostAppIsFullscreen() -> Bool {
        guard
            let processId = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return false }

        return windows.contains { window in
            guard
                (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processId,
                (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                let bounds = window[kCGWindowBounds as String] as? [String: Any],
                let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return false }

            return NSScreen.screens.contains { screen in
                abs(frame.origin.x - screen.frame.origin.x) <= 2
                    && abs(frame.origin.y - screen.frame.origin.y) <= 2
                    && abs(frame.width - screen.frame.width) <= 2
                    && abs(frame.height - screen.frame.height) <= 2
            }
        }
    }

    /// `NSScreen.isCaptured` is the only public signal for "someone else is seeing this",
    /// and it covers both recording and sharing.
    private static func isScreenBeingCaptured() -> Bool {
        NSScreen.screens.contains { screen in
            (screen.value(forKey: "isCaptured") as? Bool) ?? false
        }
    }

    /// macOS has no API for "is a Focus on", so this reads the same assertion file the
    /// system writes. Absent or unreadable means not focused, which is the safe reading:
    /// Perch stays useful rather than silently muting itself forever.
    private static func isFocusActive() -> Bool {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(
                "Library/DoNotDisturb/DB/Assertions.json")
        guard let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let records = root["data"] as? [[String: Any]]
        else { return false }

        return records.contains { record in
            guard let details = record["storeAssertionRecords"] as? [[String: Any]] else {
                return false
            }
            return !details.isEmpty
        }
    }
}
