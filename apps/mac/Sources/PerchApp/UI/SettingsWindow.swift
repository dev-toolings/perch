import AppKit
import SwiftUI

/// Hosts the settings window.
///
/// Perch is an accessory app with no Dock icon and no menu bar, so there is nothing that
/// would normally bring a window forward — the app has to activate itself, and the window
/// has to be reused rather than stacked up one per click.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    /// Reports what actually happened, so `--settings` can be verified from a terminal on
    /// a machine where nothing is allowed to enumerate windows.
    var isVisible: Bool { window?.isVisible ?? false }

    @discardableResult
    func show(model: AppModel) -> Bool {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return window.isVisible
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        // Vibe's settings window has no accessible or visible title; the selected pane
        // supplies the heading inside the content instead.
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        // Vibe keeps the native traffic lights over its full-size sidebar. The zoom
        // control is visible but disabled; close and minimise remain ordinary controls.
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.minSize = NSSize(width: 620, height: 620)
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.isReleasedWhenClosed = false
        window.center()

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window.isVisible
    }
}
