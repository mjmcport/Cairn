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
  private let settingsWindow = SettingsWindowController()
  private var saver: StateSaver?
  private var content: WindowContentViewController?
  private var isTerminating = false

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
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    let home = FileManager.default.homeDirectoryForCurrentUser
    let location = InitialLocation.resolve(defaults: .standard, fallback: home)
    let store = UserDefaultsStateStore.forLaunch()
    let settings = BrowserSettings()
    let launch = LaunchRestoration(settings: settings, store: store)
    // Column widths are kept by the table, under a name from the same suite.
    BrowserViewController.columnAutosaveName =
      "CairnList" + (launch.suite.map { "-\($0)" } ?? "")
    // The pane, inside the split view, titles the window with the showing
    // tab's folder name.
    let content = WindowContentViewController(
      location: location, restoring: launch.window,
      resolver: launch.isActive ? RestoredLocation(home: home).resolver : nil)
    window.contentViewController = content
    // The list's columns fit 900 points beside a sidebar of about 200.
    window.setContentSize(NSSize(width: 1100, height: 600))
    window.apply(.mainWindow)
    window.toolbar = toolbar.makeToolbar()
    window.toolbarStyle = .unified
    window.isReleasedWhenClosed = false
    let hadSavedFrame =
      launch.isActive
      && WindowFrame.restore(window, named: WindowFrame.autosaveName(suite: launch.suite))
    if !hadSavedFrame { window.center() }
    self.content = content
    startSaving(content, store: store, settings: settings, launch: launch)
    window.makeKeyAndOrderFront(nil)
    self.window = window

    NSApp.activate()
    Log.lifecycle.info("Launched")
  }

  private func startSaving(
    _ content: WindowContentViewController, store: UserDefaultsStateStore,
    settings: BrowserSettings, launch: LaunchRestoration
  ) {
    // A launch with -OpenFolder neither reads nor overwrites saved state.
    guard !launch.hasNamedFolder else { return }
    let saver = StateSaver(
      store: store,
      isEnabled: { settings.restoresWindows },
      capture: { [weak content] in
        content.map { SavedState(windows: [$0.captureState()]) }
      })
    content.onStateChange = { saver.noteChange() }
    settingsWindow.onRestoresWindowsChange = { saver.settingChanged() }
    self.saver = saver
    // A window the person closes is not brought back at the next launch.
    NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, !self.isTerminating else { return }
        self.saver?.windowClosed()
      }
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // Before any window closes: a quit saves what is on screen.
    isTerminating = true
    saver?.flush()
    return .terminateNow
  }

  /// Command-W when no pane is in the responder chain, as with the About
  /// panel in front and the main window closed: closes the key window. A pane
  /// handles the command first.
  @objc func closeTab(_ sender: Any?) {
    NSApp.keyWindow?.performClose(sender)
  }

  /// Cairn > Settings…
  @objc func showSettings(_ sender: Any?) {
    settingsWindow.show()
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
