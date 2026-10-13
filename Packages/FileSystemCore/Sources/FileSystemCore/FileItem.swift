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
  /// The bytes the file takes on disk, which can be far from its logical
  /// size (a sparse file, or one on a compressed volume), or `nil` for
  /// anything that is not a plain file.
  public let allocatedSize: Int64?
  /// When the item was added to its folder, which is not when it was
  /// created or changed, or `nil` when the volume does not say.
  public let dateAdded: Date?
  /// Whether the file's contents are not on this Mac: a placeholder that a
  /// cloud service fills in when the file is opened. Anything that reads the
  /// contents, a thumbnail included, can make the system download it, so
  /// nothing reads an online-only file to draw it.
  public let isOnlineOnly: Bool

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
    modificationDate: Date? = nil,
    allocatedSize: Int64? = nil,
    dateAdded: Date? = nil,
    isOnlineOnly: Bool = false
  ) {
    self.url = url
    self.kind = kind
    self.isHidden = isHidden
    self.size = size
    self.modificationDate = modificationDate
    self.allocatedSize = allocatedSize
    self.dateAdded = dateAdded
    self.isOnlineOnly = isOnlineOnly
  }
}

extension FileItem {
  /// The resource keys a listing needs. Enumeration prefetches them, so
  /// building an item never makes another file-system call.
  public static let resourceKeys: Set<URLResourceKey> = [
    .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isHiddenKey,
    .fileSizeKey, .contentModificationDateKey, .totalFileAllocatedSizeKey,
    .addedToDirectoryDateKey,
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
    let size = kind == .file ? values.fileSize.map(Int64.init) : nil
    let allocatedSize = kind == .file ? values.totalFileAllocatedSize.map(Int64.init) : nil
    self.init(
      url: url,
      kind: kind,
      isHidden: values.isHidden ?? false,
      size: size,
      modificationDate: values.contentModificationDate,
      allocatedSize: allocatedSize,
      dateAdded: values.addedToDirectoryDate,
      isOnlineOnly: kind == .file
        && Self.isOnlineOnly(size: size, allocatedSize: allocatedSize, downloadingStatus: nil)
    )
  }

  /// Whether a regular file is online only. A file that a cloud service has
  /// not downloaded reports a logical size and no allocated blocks. A sparse
  /// file looks the same, which is the price of not asking anything more.
  ///
  /// The iCloud downloading status says it outright, but reading it for every
  /// item of a listing multiplied the time to list 10,000 items by nine (0.06
  /// s to 0.53 s) and 100,000 by ten, so the listing does not read it. A
  /// caller that has few items to ask about may pass it.
  static func isOnlineOnly(
    size: Int64?, allocatedSize: Int64?, downloadingStatus: URLUbiquitousItemDownloadingStatus?
  ) -> Bool {
    if downloadingStatus == .notDownloaded { return true }
    guard let size, let allocatedSize else { return false }
    return size > 0 && allocatedSize == 0
  }
}
