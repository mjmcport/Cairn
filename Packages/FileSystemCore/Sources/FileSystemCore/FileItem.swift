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
  /// The logical size in bytes, or `nil` for anything that is not a plain file.
  public let size: Int64?
  public let modificationDate: Date?

  public var id: URL { url }

  /// The last path component, as stored on disk.
  public var name: String { url.lastPathComponent }

  /// Whether opening the item navigates into it.
  public var isNavigable: Bool { kind == .directory }

  public init(
    url: URL,
    kind: Kind,
    isHidden: Bool = false,
    size: Int64? = nil,
    modificationDate: Date? = nil
  ) {
    self.url = url
    self.kind = kind
    self.isHidden = isHidden
    self.size = size
    self.modificationDate = modificationDate
  }
}

extension FileItem {
  /// The resource keys a listing needs. Enumeration prefetches them, so
  /// building an item never makes another file-system call.
  public static let resourceKeys: Set<URLResourceKey> = [
    .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isHiddenKey,
    .fileSizeKey, .contentModificationDateKey,
  ]

  /// Builds an item from resource values read for ``resourceKeys``.
  public init(url: URL, resourceValues values: URLResourceValues) {
    let kind: Kind =
      if values.isSymbolicLink == true {
        .symbolicLink
      } else if values.isPackage == true {
        .package
      } else if values.isDirectory == true {
        .directory
      } else {
        .file
      }
    self.init(
      url: url,
      kind: kind,
      isHidden: values.isHidden ?? false,
      size: kind == .file ? values.fileSize.map(Int64.init) : nil,
      modificationDate: values.contentModificationDate
    )
  }
}
