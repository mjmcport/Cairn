import Foundation

/// Chooses the folder a new window opens on.
public enum InitialLocation {
  /// The launch argument that names a folder: `Cairn -OpenFolder /some/path`.
  public static let argumentKey = "OpenFolder"

  /// The folder named by the launch argument, or `fallback` when the argument
  /// is absent or empty. The path is not checked here; a folder that cannot be
  /// listed shows its error in the window.
  public static func resolve(defaults: UserDefaults, fallback: URL) -> URL {
    guard let path = defaults.string(forKey: argumentKey), !path.isEmpty else {
      return fallback
    }
    let expanded = (path as NSString).expandingTildeInPath
    return URL(filePath: expanded, directoryHint: .isDirectory).standardizedFileURL
  }
}
