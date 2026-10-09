import os

/// The app's log categories. View them in Console, or with
/// `log stream --predicate 'subsystem == "com.mjmcport.cairn"'`.
///
/// Logs stay on the Mac. Interpolated strings are private by default, so file
/// names and paths are redacted unless a message marks them `.public`. Do not
/// mark a path or file name public.
public enum Log {
  public static let subsystem = "com.mjmcport.cairn"

  /// Listing folders, watching for changes, volumes.
  public static let fileSystem = Logger(subsystem: subsystem, category: "filesystem")
  /// Reading sizes, dates, tags and other metadata.
  public static let metadata = Logger(subsystem: subsystem, category: "metadata")
  /// Copy, move, trash, rename and undo.
  public static let operations = Logger(subsystem: subsystem, category: "operations")
  /// Windows, panes, views and user actions.
  public static let ui = Logger(subsystem: subsystem, category: "ui")
  /// Launch, termination and state restoration.
  public static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
  /// Main-thread violations, hangs and crash reports.
  public static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")

  /// Every category name, for tests and documentation.
  public static let categories = [
    "filesystem", "metadata", "operations", "ui", "lifecycle", "diagnostics",
  ]
}
