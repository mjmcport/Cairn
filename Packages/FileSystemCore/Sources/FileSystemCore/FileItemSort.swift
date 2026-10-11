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
    sorted(items, checking: {})
  }

  /// The items a listing shows, in order: ``sorted(_:)`` of the items that
  /// are visible.
  ///
  /// Never runs on the caller's actor, so a large folder can be arranged
  /// from the main actor without holding it. Throws `CancellationError` as
  /// soon as the task is cancelled.
  public func arranged(_ items: [FileItem], includingHidden: Bool) async throws -> [FileItem] {
    try await arranged(items, includingHidden: includingHidden, onCancellationCheck: { _ in })
  }

  /// - Parameter onCancellationCheck: Called with the number of checks made
  ///   so far, just before each cancellation check: one at the start, then
  ///   one for every comparison. Tests use it to see where the work runs and
  ///   to cancel a sort that is under way.
  func arranged(
    _ items: [FileItem], includingHidden: Bool,
    onCancellationCheck: @Sendable (_ checks: Int) -> Void
  ) async throws -> [FileItem] {
    var checks = 0
    func check() throws {
      onCancellationCheck(checks)
      checks += 1
      try Task.checkCancellation()
    }
    try check()
    return try sorted(items.visible(includingHidden: includingHidden), checking: check)
  }

  /// Reads each name from its URL once and sorts positions rather than
  /// items. A comparator that reads both names on every comparison takes
  /// several times as long.
  /// - Parameter check: Called before every comparison. Throwing stops the sort.
  private func sorted(_ items: [FileItem], checking check: () throws -> Void) rethrows
    -> [FileItem]
  {
    let names = items.map(\.name)
    let positions = try items.indices.sorted { lhs, rhs in
      try check()
      return areInOrder(items[lhs], names[lhs], items[rhs], names[rhs])
    }
    return positions.map { items[$0] }
  }

  private func areInOrder(
    _ lhs: FileItem, _ lhsName: String, _ rhs: FileItem, _ rhsName: String
  ) -> Bool {
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
    let byName = lhsName.localizedStandardCompare(rhsName)
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
