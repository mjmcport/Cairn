import Foundation

/// One entry in a folder: a file, a folder, a symbolic link or a package.
///
/// A `FileItem` is a snapshot. It does not track later changes on disk.
public struct FileItem: Sendable, Hashable, Identifiable {
  /// What an item is, as far as browsing is concerned.
  public enum Kind: Sendable, Hashable {
    case file
    case directory
    case symbolicLink
    /// A folder the system shows as a single file, such as an app bundle.
    case package
  }

  public let url: URL
  public let kind: Kind
  public let isHidden: Bool

  public var id: URL { url }

  /// The last path component, as stored on disk.
  public var name: String { url.lastPathComponent }

  /// Whether double-clicking the item navigates into it.
  public var isNavigable: Bool { kind == .directory }

  public init(url: URL, kind: Kind, isHidden: Bool = false) {
    self.url = url
    self.kind = kind
    self.isHidden = isHidden
  }
}
