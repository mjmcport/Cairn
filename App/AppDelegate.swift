import AppKit
import BrowserUI
import FileSystemCore

/// The application entry point. Opens one window whose pane starts with one
/// tab on a folder: the one named by `-OpenFolder <path>` at launch, or the
/// home folder.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow?
  private let diagnostics = DiagnosticsSubscriber()
  private let toolbar = BrowserToolbar()

  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Tabs are drawn inside the pane. With the system's window tabbing left
    // on, it would add tab commands of its own under the same shortcuts and
    // could merge windows into tabs the pane knows nothing about.
    NSWindow.allowsAutomaticWindowTabbing = false
    NSApp.mainMenu = MainMenu.make()
    diagnostics.start()

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
    // The pane titles the window with the showing tab's folder name.
    window.contentViewController = PaneViewController(location: location)
    window.setContentSize(NSSize(width: 900, height: 600))
    window.apply(.mainWindow)
    window.toolbar = toolbar.makeToolbar()
    window.toolbarStyle = .unified
    window.isReleasedWhenClosed = false
    window.center()
    window.makeKeyAndOrderFront(nil)
    self.window = window

    NSApp.activate()
    Log.lifecycle.info("Launched")
  }

  /// Command-W when no pane is in the responder chain, as with the About
  /// panel in front and the main window closed: closes the key window. A pane
  /// handles the command first.
  @objc func closeTab(_ sender: Any?) {
    NSApp.keyWindow?.performClose(sender)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }
}

extension AppDelegate: NSUserInterfaceValidations {
  /// Close Tab needs a window to close.
  func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    switch item.action {
    case #selector(closeTab(_:)): NSApp.keyWindow != nil
    default: true
    }
  }
}
