import Foundation

/// Decides at launch whether saved state is read and kept (R13, R15, R16).
///
/// - A launch with `-OpenFolder` ignores saved state and leaves it as it
///   is: such a launch is for a test or a script, not a session.
/// - With the setting off nothing is read and nothing is kept.
/// - State that cannot be read is ignored, and left in place until a good
///   save replaces it.
public struct LaunchRestoration {
  /// Whether this launch reads and writes saved state.
  public let isActive: Bool
  /// Whether the launch names a folder with `-OpenFolder`. Such a launch
  /// leaves the saved state alone.
  public let hasNamedFolder: Bool
  /// The window to restore, if any.
  public let window: SavedWindow?
  /// The suite name from `-StateSuite`, if given.
  public let suite: String?

  /// - Parameter arguments: The defaults that hold the launch arguments.
  /// - Parameter settings: The person's settings.
  public init(
    arguments: UserDefaults = .standard, settings: BrowserSettings, store: any StateStoring
  ) {
    let name = arguments.string(forKey: UserDefaultsStateStore.suiteArgument)
    suite = (name?.isEmpty ?? true) ? nil : name
    let openFolder = arguments.string(forKey: InitialLocation.argumentKey)
    let namedFolder = !(openFolder?.isEmpty ?? true)
    hasNamedFolder = namedFolder
    isActive = settings.restoresWindows && !namedFolder
    if isActive, let data = store.load(), let state = SavedState.decode(data) {
      window = state.windows.first
    } else {
      window = nil
    }
  }
}
