import Foundation

/// A folder offered while a path is typed, or listed in a path bar menu.
public struct FolderSuggestion: Sendable, Equatable {
  public let name: String
  public let url: URL

  public init(name: String, url: URL) {
    self.name = name
    self.url = url
  }
}

/// What is at a typed place.
public enum PathExistence: Sendable, Equatable {
  case folder
  case file
  case missing
}

/// Lists folders for completion and the path bar's menus. Both entry points
/// touch the file system, so callers run them off the main thread.
public protocol FolderCompleting: Sendable {
  /// The folders in `folder` whose names begin with `prefix`, ignoring case,
  /// by name, at most `limit`. Hidden ones only when `prefix` starts with a dot.
  func folders(in folder: URL, prefix: String, limit: Int) throws -> [FolderSuggestion]
  /// What is at `url`, following links.
  func existence(of url: URL) -> PathExistence
}

/// The real thing, over `FileManager`.
public struct DirectoryFolderCompleter: FolderCompleting {
  /// The most suggestions Go to Folder shows.
  public static let suggestionLimit = 20

  public init() {}

  public func folders(in folder: URL, prefix: String, limit: Int) throws -> [FolderSuggestion] {
    MainThreadGuard.assertOffMainThread()
    let entries = try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .isHiddenKey],
      options: [])
    let wantsHidden = prefix.hasPrefix(".")
    var found: [FolderSuggestion] = []
    for entry in entries {
      let name = entry.lastPathComponent
      if !prefix.isEmpty, !name.lowercased().hasPrefix(prefix.lowercased()) { continue }
      if !wantsHidden, name.hasPrefix(".") { continue }
      let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
      var isDirectory = values?.isDirectory ?? false
      if !isDirectory, values?.isDirectory == false {
        // A link to a folder reports as not a directory; follow it.
        var followed: ObjCBool = false
        isDirectory =
          FileManager.default.fileExists(
            atPath: entry.path(percentEncoded: false), isDirectory: &followed)
          && followed.boolValue
      }
      guard isDirectory, values?.isPackage != true else { continue }
      found.append(
        FolderSuggestion(
          name: name,
          url: URL(filePath: entry.path(percentEncoded: false), directoryHint: .isDirectory)))
    }
    found.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    return Array(found.prefix(limit))
  }

  public func existence(of url: URL) -> PathExistence {
    MainThreadGuard.assertOffMainThread()
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(
        atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
    else { return .missing }
    return isDirectory.boolValue ? .folder : .file
  }
}
