import AppKit

/// The window's frame, kept by the system's own frame autosave and brought
/// back onto a screen when the screen it was on is gone (R1).
@MainActor
public enum WindowFrame {
  /// The autosave name for this launch: the same suite that names the
  /// other saved state, so tests never share a frame with the app.
  public static func autosaveName(suite: String?) -> String {
    "CairnMainWindow" + (suite.map { "-\($0)" } ?? "")
  }

  /// Applies the saved frame under `name` and keeps saving it.
  /// - Returns: Whether a saved frame was found.
  @discardableResult
  public static func restore(_ window: NSWindow, named name: String) -> Bool {
    // `setFrameAutosaveName` says only whether the name was accepted, so the
    // saved frame is asked for first.
    let found = window.setFrameUsingName(name)
    window.setFrameAutosaveName(name)
    if found { moveOntoAScreen(window) }
    return found
  }

  /// Moves the window so it is on a connected screen, keeping its size where
  /// it fits.
  public static func moveOntoAScreen(_ window: NSWindow) {
    let onAScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
    guard !onAScreen, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
    window.setFrame(window.constrainFrameRect(window.frame, to: screen), display: false)
    if !screen.visibleFrame.intersects(window.frame) {
      window.center()
    }
  }
}
