import FileSystemCore
import Foundation

/// The place of a folder under the one being shown: the names from the
/// shown folder down to it. The shown folder itself is ``root``.
///
/// A key is made of names, not URLs, because a listing spells a folder
/// differently from the location that was opened (a location under `/var`
/// lists its items under `/private/var`). Names are what both spellings
/// agree on.
public struct FolderKey: Hashable, Sendable {
  public let names: [String]

  /// The folder being shown.
  public static let root = FolderKey(names: [])

  public init(names: [String]) {
    self.names = names
  }

  public var isRoot: Bool { names.isEmpty }
  public var depth: Int { names.count }

  /// The folder this one is directly inside, or nil for ``root``.
  public var parent: FolderKey? {
    isRoot ? nil : FolderKey(names: Array(names.dropLast()))
  }

  /// The key of the item called `name` in this folder.
  public func appending(_ name: String) -> FolderKey {
    FolderKey(names: names + [name])
  }

  /// Whether this key is `other` or lies anywhere beneath it.
  func isInside(_ other: FolderKey) -> Bool {
    names.count >= other.names.count && names.starts(with: other.names)
  }
}

/// A folder that is open in place: what it holds and how far its listing has
/// got.
struct OpenFolder: Sendable {
  enum Listing: Equatable, Sendable {
    /// Opened, and its first listing has not arrived.
    case listing
    case listed
    /// The folder could not be listed; the text explains why. It stays open
    /// so that a later change can list it.
    case failed(String)
  }

  /// The folder's items after filtering and sorting, once it is listed.
  var items: [FileItem] = []
  var listing = Listing.listing
  /// Tells one opening of a folder from the next, so a listing that was
  /// started for a folder that has since been closed and opened again cannot
  /// publish into the new opening.
  let token: Int
}
