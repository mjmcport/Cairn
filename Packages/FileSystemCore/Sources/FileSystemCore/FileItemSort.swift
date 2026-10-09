import Foundation

/// How a listing is ordered.
public struct FileItemSort: Sendable, Equatable {
  public enum Key: Sendable, Equatable {
    case name
    case size
    case modificationDate
  }

  public var key: Key
  public var ascending: Bool
  /// Whether folders are grouped ahead of everything else, in either direction.
  public var foldersFirst: Bool

  public init(key: Key = .name, ascending: Bool = true, foldersFirst: Bool = false) {
    self.key = key
    self.ascending = ascending
    self.foldersFirst = foldersFirst
  }

  /// The items in order. Equal keys fall back to the name, then to the full
  /// path, so the result never depends on the input order.
  public func sorted(_ items: [FileItem]) -> [FileItem] {
    items.sorted(by: areInOrder)
  }

  private func areInOrder(_ lhs: FileItem, _ rhs: FileItem) -> Bool {
    if foldersFirst, lhs.isNavigable != rhs.isNavigable {
      return lhs.isNavigable
    }
    let primary: ComparisonResult =
      switch key {
      case .name: .orderedSame
      // A folder has no size and sorts as smaller than any file.
      case .size: Self.compare(lhs.size ?? -1, rhs.size ?? -1)
      case .modificationDate:
        Self.compare(
          lhs.modificationDate ?? .distantPast, rhs.modificationDate ?? .distantPast)
      }
    if primary != .orderedSame {
      return (primary == .orderedAscending) == ascending
    }
    // The same comparison Finder uses: case-insensitive, with numbers in order.
    let byName = lhs.name.localizedStandardCompare(rhs.name)
    if byName != .orderedSame {
      return (byName == .orderedAscending) == ascending
    }
    return lhs.url.path < rhs.url.path
  }

  private static func compare<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
    lhs < rhs ? .orderedAscending : (lhs > rhs ? .orderedDescending : .orderedSame)
  }
}

extension Sequence<FileItem> {
  /// The items a listing shows: all of them, or only those not hidden.
  public func visible(includingHidden: Bool) -> [FileItem] {
    includingHidden ? Array(self) : filter { !$0.isHidden }
  }
}
