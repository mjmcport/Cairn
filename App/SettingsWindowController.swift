import AppKit
import BrowserUI
import SwiftUI

/// The Settings window. There is one: showing it again brings it to the
/// front instead of making another.
@MainActor
final class SettingsWindowController {
  private var window: NSWindow?

  func show() {
    let window = window ?? makeWindow()
    self.window = window
    window.makeKeyAndOrderFront(nil)
  }

  private func makeWindow() -> NSWindow {
    let hosting = NSHostingController(rootView: SettingsView())
    hosting.view.apply(.settingsContent)
    let window = NSWindow(contentViewController: hosting)
    window.title = "Settings"
    window.styleMask = [.titled, .closable]
    // Kept for the next time it is shown.
    window.isReleasedWhenClosed = false
    window.apply(.settingsWindow)
    window.center()
    return window
  }
}
