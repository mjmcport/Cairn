import AppKit
import BrowserUI

/// The application entry point. Opens one window that lists a folder: the one
/// named by `-OpenFolder <path>` at launch, or the home folder.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow?

  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = MainMenu.make()

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    let location = InitialLocation.resolve(
      defaults: .standard,
      fallback: FileManager.default.homeDirectoryForCurrentUser
    )
    // The window takes its title from the browser, which shows the folder name.
    window.contentViewController = BrowserViewController(location: location)
    window.setContentSize(NSSize(width: 900, height: 600))
    window.identifier = NSUserInterfaceItemIdentifier("main-window")
    window.isReleasedWhenClosed = false
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window

    NSApp.activate()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }
}
