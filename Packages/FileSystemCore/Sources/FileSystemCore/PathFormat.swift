import Foundation

/// The ways Copy Path writes a path. Pure string work.
public enum PathFormat: Int, Sendable, CaseIterable {
  /// `/Users/me/My Folder`
  case path
  /// `/Users/me/My\ Folder`, safe to paste into a shell.
  case escapedPath
  /// `file:///Users/me/My%20Folder`
  case fileURL
  /// `~/My Folder`, or the plain path outside the home folder.
  case homeRelativePath

  /// The words the menu shows.
  public var title: String {
    switch self {
    case .path: "Path"
    case .escapedPath: "Escaped Path"
    case .fileURL: "File URL"
    case .homeRelativePath: "Home-Relative Path"
    }
  }

  /// `url` written in this format.
  public func string(for url: URL, home: URL) -> String {
    // A folder's URL spells its path with a closing slash; a path copied
    // from a folder reads without one, as Finder's does.
    var path = url.path(percentEncoded: false)
    if path.count > 1, path.hasSuffix("/") { path.removeLast() }
    switch self {
    case .path:
      return path
    case .escapedPath:
      return Self.shellEscape(path)
    case .fileURL:
      return URL(filePath: path, directoryHint: .inferFromPath).absoluteString
    case .homeRelativePath:
      var homePath = home.path(percentEncoded: false)
      if homePath.count > 1, homePath.hasSuffix("/") { homePath.removeLast() }
      if path == homePath { return "~" }
      let prefix = homePath == "/" ? "/" : homePath + "/"
      if path.hasPrefix(prefix) { return "~/" + path.dropFirst(prefix.count) }
      return path
    }
  }

  private static let safe = Set(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./+,:@%=")

  /// Backslash-escapes every character a shell could read as more than a
  /// name. A name with a control character cannot be backslash-escaped (a
  /// backslash before a newline is a line continuation), so it is written in
  /// the shell's `$'…'` form instead.
  static func shellEscape(_ text: String) -> String {
    if text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
      var out = "$'"
      for scalar in text.unicodeScalars {
        switch scalar {
        case "\\": out += "\\\\"
        case "'": out += "\\'"
        case "\n": out += "\\n"
        case "\t": out += "\\t"
        case "\r": out += "\\r"
        default:
          if scalar.value < 0x20 || scalar.value == 0x7F {
            out += "\\x" + String(scalar.value, radix: 16, uppercase: false).leftPadded(to: 2)
          } else {
            out.unicodeScalars.append(scalar)
          }
        }
      }
      return out + "'"
    }
    var out = ""
    for character in text {
      if safe.contains(character) || !character.isASCII {
        out.append(character)
      } else {
        out.append("\\")
        out.append(character)
      }
    }
    return out
  }
}

extension String {
  fileprivate func leftPadded(to width: Int) -> String {
    count >= width ? self : String(repeating: "0", count: width - count) + self
  }
}
