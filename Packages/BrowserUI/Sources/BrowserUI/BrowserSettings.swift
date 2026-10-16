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

  /// The user defaults key of ``restoresWindows``.
  public static let restoresWindowsKey = "RestoreWindows"

  private let defaults: UserDefaults

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// Whether Cairn reopens its windows and tabs at launch. On until it is
  /// turned off.
  public var restoresWindows: Bool {
    get { defaults.object(forKey: Self.restoresWindowsKey) as? Bool ?? true }
    nonmutating set { defaults.set(newValue, forKey: Self.restoresWindowsKey) }
  }

  /// Whether Back and Forward open again the folders that were open in the
  /// place returned to. On until it is turned off.
  public var rememberOpenFolders: Bool {
    get { defaults.object(forKey: Self.rememberOpenFoldersKey) as? Bool ?? true }
    nonmutating set { defaults.set(newValue, forKey: Self.rememberOpenFoldersKey) }
  }
}
