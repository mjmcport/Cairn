import Foundation

/// The settings a browser reads while it works. They live in the user
/// defaults, so a change made in the Settings window reaches every window
/// and tab at once, and nothing observes them: each is read when it is
/// needed.
///
/// A test passes a suite of its own, as ``InitialLocation/resolve(defaults:fallback:)``
/// does, so it never reads or writes the app's real settings.
public struct BrowserSettings {
  /// The user defaults key of ``rememberOpenFolders``.
  public static let rememberOpenFoldersKey = "RememberOpenFolders"

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// Whether Back and Forward open again the folders that were open in the
  /// place returned to. On until it is turned off.
  public var rememberOpenFolders: Bool {
    get { defaults.object(forKey: Self.rememberOpenFoldersKey) as? Bool ?? true }
    nonmutating set { defaults.set(newValue, forKey: Self.rememberOpenFoldersKey) }
  }
}
