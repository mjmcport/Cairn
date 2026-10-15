import Foundation

/// Reads a path as a person types it in Go to Folder. Pure: nothing here
/// looks at the file system.
public enum TypedPath {
  /// What the text means as a place to go to.
  public static func resolve(_ text: String, relativeTo base: URL, home: URL) -> URL {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return base.standardizedFileURL }
    return standardized(absolute(trimmed, base: base, home: home))
  }

  /// The folder to list for completion and the beginning of the name being
  /// typed in it. `Docu` under the base gives the base and `Docu`; `~/Doc`
  /// gives home and `Doc`; `/usr/` gives `/usr` and an empty name.
  public static func completionContext(
    _ text: String, relativeTo base: URL, home: URL
  ) -> (folder: URL, prefix: String) {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    if trimmed == "~" { return (home, "") }
    guard let slash = trimmed.lastIndex(of: "/") else {
      return (base.standardizedFileURL, trimmed)
    }
    let folderText = String(trimmed[...slash])
    let prefix = String(trimmed[trimmed.index(after: slash)...])
    return (resolve(folderText, relativeTo: base, home: home), prefix)
  }

  /// The text to put in the field for a place: the path, with a closing
  /// slash so that typing goes on inside it.
  public static func text(for folder: URL) -> String {
    let path = folder.path(percentEncoded: false)
    return path.hasSuffix("/") ? path : path + "/"
  }

  private static func absolute(_ text: String, base: URL, home: URL) -> URL {
    if text == "~" { return home }
    if text.hasPrefix("~/") {
      return URL(
        filePath: String(text.dropFirst(2)), directoryHint: .inferFromPath, relativeTo: home)
    }
    if text.hasPrefix("/") { return URL(filePath: text, directoryHint: .inferFromPath) }
    return URL(filePath: text, directoryHint: .inferFromPath, relativeTo: base)
  }

  private static func standardized(_ url: URL) -> URL {
    let path = url.standardizedFileURL.path(percentEncoded: false)
    return URL(filePath: path, directoryHint: .isDirectory)
  }
}
