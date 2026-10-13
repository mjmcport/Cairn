import Foundation
import TestSupport
import Testing

@testable import FileSystemCore

@Suite struct FileItemSortTests {
  private func item(
    _ name: String, kind: FileItem.Kind = .file, size: Int64? = nil, modified: TimeInterval? = nil,
    onDisk: Int64? = nil, added: TimeInterval? = nil
  ) -> FileItem {
    FileItem(
      url: URL(filePath: "/fixture/\(name)"),
      kind: kind,
      size: size,
      modificationDate: modified.map(Date.init(timeIntervalSince1970:)),
      allocatedSize: onDisk,
      dateAdded: added.map(Date.init(timeIntervalSince1970:))
    )
  }

  private func names(_ items: [FileItem]) -> [String] { items.map(\.name) }

  @Test func sortsNamesLikeFinderWithNumbersInOrderAndCaseIgnored() {
    let items = ["file10.txt", "File2.txt", "file1.txt", "apple", "Banana", "éclair", "zebra"]
      .map { item($0) }
    #expect(
      names(FileItemSort().sorted(items))
        == ["apple", "Banana", "éclair", "file1.txt", "File2.txt", "file10.txt", "zebra"])
  }

  @Test func descendingReversesTheOrder() {
    let items = ["b", "a", "c"].map { item($0) }
    #expect(names(FileItemSort(ascending: false).sorted(items)) == ["c", "b", "a"])
  }

  @Test func sortsBySizeWithFoldersSmallestAndNameBreakingTies() {
    let items = [
      item("big.bin", size: 900),
      item("b-same.bin", size: 10),
      item("a-same.bin", size: 10),
      item("Folder", kind: .directory),
      item("empty.txt", size: 0),
    ]
    #expect(
      names(FileItemSort(key: .size).sorted(items))
        == ["Folder", "empty.txt", "a-same.bin", "b-same.bin", "big.bin"])
    #expect(names(FileItemSort(key: .size, ascending: false).sorted(items)).first == "big.bin")
  }

  @Test func sortsByModificationDateWithMissingDatesOldest() {
    let items = [
      item("new", modified: 3_000),
      item("undated"),
      item("old", modified: 1_000),
      item("middle", modified: 2_000),
    ]
    #expect(
      names(FileItemSort(key: .modificationDate).sorted(items))
        == ["undated", "old", "middle", "new"])
  }

  @Test func sortsBySizeOnDiskNotByLogicalSize() {
    let items = [
      // Large on paper and almost nothing on disk, like a sparse file.
      item("sparse.img", size: 1_000_000, onDisk: 4_096),
      item("packed.bin", size: 100, onDisk: 8_192),
      item("Folder", kind: .directory),
      item("b-tie.bin", size: 1, onDisk: 4_096),
    ]
    #expect(
      names(FileItemSort(key: .sizeOnDisk).sorted(items))
        == ["Folder", "b-tie.bin", "sparse.img", "packed.bin"])
    #expect(
      names(FileItemSort(key: .sizeOnDisk, ascending: false).sorted(items))
        == ["packed.bin", "sparse.img", "b-tie.bin", "Folder"])
  }

  @Test func sortsByDateAddedWithMissingDatesOldestAndNameBreakingTies() {
    let items = [
      item("new", added: 3_000),
      item("unknown"),
      item("b-same", added: 2_000),
      item("a-same", added: 2_000),
      item("old", added: 1_000),
    ]
    #expect(
      names(FileItemSort(key: .dateAdded).sorted(items))
        == ["unknown", "old", "a-same", "b-same", "new"])
  }

  @Test func dateAddedIsNotTheModificationDate() {
    let items = [
      item("a", modified: 1_000, added: 3_000),
      item("b", modified: 3_000, added: 1_000),
    ]
    #expect(names(FileItemSort(key: .modificationDate).sorted(items)) == ["a", "b"])
    #expect(names(FileItemSort(key: .dateAdded).sorted(items)) == ["b", "a"])
  }

  @Test func foldersFirstGroupsFoldersInEitherDirection() {
    let items = [
      item("b.txt"), item("Zeta", kind: .directory), item("a.txt"), item("Alpha", kind: .directory),
      item("App.app", kind: .package),
    ]
    #expect(
      names(FileItemSort(foldersFirst: true).sorted(items))
        == ["Alpha", "Zeta", "a.txt", "App.app", "b.txt"])
    #expect(
      names(FileItemSort(ascending: false, foldersFirst: true).sorted(items))
        == ["Zeta", "Alpha", "b.txt", "App.app", "a.txt"])
  }

  @Test func theResultDoesNotDependOnInputOrder() {
    let items =
      (0..<200).map { item("file\($0 % 20).txt", size: Int64($0 % 7)) }
      + [item("Dir", kind: .directory)]
    let sort = FileItemSort(key: .size)
    let expected = sort.sorted(items).map(\.url)
    for _ in 0..<5 {
      #expect(sort.sorted(items.shuffled()).map(\.url) == expected)
    }
  }

  // MARK: The same order as a plain comparator

  /// The order as `sorted(_:)` documents it, written the plain way: every
  /// comparison reads both names from their URLs.
  private func referenceOrder(_ items: [FileItem], by sort: FileItemSort) -> [FileItem] {
    func compare<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
      lhs < rhs ? .orderedAscending : (lhs > rhs ? .orderedDescending : .orderedSame)
    }
    return items.sorted { lhs, rhs in
      if sort.foldersFirst, lhs.isNavigable != rhs.isNavigable {
        return lhs.isNavigable
      }
      let primary: ComparisonResult =
        switch sort.key {
        case .name: .orderedSame
        case .size: compare(lhs.size ?? -1, rhs.size ?? -1)
        case .sizeOnDisk: compare(lhs.allocatedSize ?? -1, rhs.allocatedSize ?? -1)
        case .modificationDate:
          compare(lhs.modificationDate ?? .distantPast, rhs.modificationDate ?? .distantPast)
        case .dateAdded: compare(lhs.dateAdded ?? .distantPast, rhs.dateAdded ?? .distantPast)
        }
      if primary != .orderedSame {
        return (primary == .orderedAscending) == sort.ascending
      }
      let byName = lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent)
      if byName != .orderedSame {
        return (byName == .orderedAscending) == sort.ascending
      }
      return lhs.url.path < rhs.url.path
    }
  }

  @Test func everyKeyAndDirectionGivesTheOrderOfAPlainComparator() {
    var items = FixtureNames.unicode.enumerated().map { index, name in
      // Sizes and dates repeat, so the name has ties to break.
      item(
        name, size: Int64(index % 3), modified: TimeInterval(index % 4),
        onDisk: Int64(index % 5), added: TimeInterval(index % 6))
    }
    items += [
      item("Folder", kind: .directory),
      // The same name in two folders: only the path tells them apart.
      FileItem(url: URL(filePath: "/fixture/b/same.txt"), kind: .file, size: 1),
      FileItem(url: URL(filePath: "/fixture/a/same.txt"), kind: .file, size: 1),
    ]
    for key in [FileItemSort.Key.name, .size, .sizeOnDisk, .modificationDate, .dateAdded] {
      for ascending in [true, false] {
        for foldersFirst in [false, true] {
          let sort = FileItemSort(key: key, ascending: ascending, foldersFirst: foldersFirst)
          #expect(
            sort.sorted(items.shuffled()).map(\.url) == referenceOrder(items, by: sort).map(\.url),
            "\(sort)")
        }
      }
    }
  }

  // MARK: Arranging a whole folder off the caller's actor

  private var mixed: [FileItem] {
    [
      item("b.txt"),
      FileItem(url: URL(filePath: "/fixture/.hidden"), kind: .file, isHidden: true),
      item("a.txt"),
      item("Folder", kind: .directory),
    ]
  }

  @Test func arrangingDropsHiddenItemsUnlessAskedAndSorts() async throws {
    let sort = FileItemSort(ascending: false, foldersFirst: true)
    let visible = try await sort.arranged(mixed, includingHidden: false)
    #expect(names(visible) == ["Folder", "b.txt", "a.txt"])
    #expect(visible == sort.sorted(mixed.visible(includingHidden: false)))

    let all = try await sort.arranged(mixed, includingHidden: true)
    #expect(names(all) == ["Folder", "b.txt", "a.txt", ".hidden"])
    #expect(all == sort.sorted(mixed.visible(includingHidden: true)))
  }

  @Test func arrangingRunsOffTheMainThreadWhenAwaitedOnTheMainActor() async throws {
    let items = mixed
    let ranOnMainThread = Recorded<[Bool]>([])
    let arranged = try await Task { @MainActor in
      try await FileItemSort().arranged(items, includingHidden: false) { checks in
        if checks == 0 {
          ranOnMainThread.value += [pthread_main_np() != 0]
        }
      }
    }.value
    #expect(arranged.count == 3)
    #expect(ranOnMainThread.value == [false])
  }

  @Test func arrangingInACancelledTaskThrowsCancellationError() async throws {
    let items = mixed
    let cancelledBefore = Task {
      try await FileItemSort().arranged(items, includingHidden: false)
    }
    cancelledBefore.cancel()
    await #expect(throws: CancellationError.self) {
      try await cancelledBefore.value
    }

    let checks = Recorded<[Int]>([])
    let cancelledAtTheStart = Task {
      try await FileItemSort().arranged(items, includingHidden: false) {
        checks.value += [$0]
        withUnsafeCurrentTask { $0?.cancel() }
      }
    }
    await #expect(throws: CancellationError.self) {
      try await cancelledAtTheStart.value
    }
    // Nothing was compared.
    #expect(checks.value == [0])
  }

  @Test func cancellationStopsASortThatIsUnderWay() async throws {
    let items = (0..<64).map { item("file\($0).txt") }.shuffled()
    let checks = Recorded<[Int]>([])
    let task = Task {
      try await FileItemSort().arranged(items, includingHidden: false) {
        checks.value += [$0]
        // Cancel from inside the sort, once it is comparing.
        if $0 == 3 {
          withUnsafeCurrentTask { $0?.cancel() }
        }
      }
    }
    await #expect(throws: CancellationError.self) {
      try await task.value
    }
    // It stops at the check that follows the cancellation: nothing more is compared.
    #expect(checks.value == [0, 1, 2, 3])
  }

  // MARK: Comparing two listings off the caller's actor

  @Test func listingsOfEqualItemsInTheSameOrderDoNotDiffer() async {
    let listing = [item("a.txt", size: 1, modified: 10), item("Folder", kind: .directory)]
    let same = [item("a.txt", size: 1, modified: 10), item("Folder", kind: .directory)]
    #expect(await !listing.differs(from: same))
    #expect(await ![FileItem]().differs(from: []))
  }

  @Test func aDifferentOrderOneItemMoreOrFewerOrAChangedItemEachDiffer() async {
    let a = item("a.txt", size: 1, modified: 10)
    let b = item("b.txt", size: 2, modified: 20)
    let listing = [a, b]
    #expect(await listing.differs(from: [b, a]))
    #expect(await listing.differs(from: [a, b, item("c.txt")]))
    #expect(await listing.differs(from: [a]))
    #expect(await listing.differs(from: []))
    #expect(await listing.differs(from: [a, item("b.txt", size: 3, modified: 20)]))
    #expect(await listing.differs(from: [a, item("b.txt", size: 2, modified: 20, onDisk: 4_096)]))
    #expect(await listing.differs(from: [a, item("b.txt", size: 2, modified: 20, added: 5)]))
    #expect(await listing.differs(from: [a, item("b.txt", size: 2, modified: 21)]))
  }

  @Test func comparingRunsOffTheMainThreadWhenAwaitedOnTheMainActor() async {
    let items = mixed
    let ranOnMainThread = Recorded<[Bool]>([])
    let differs = await Task { @MainActor in
      await items.differs(from: items) {
        ranOnMainThread.value += [pthread_main_np() != 0]
      }
    }.value
    #expect(!differs)
    #expect(ranOnMainThread.value == [false])
  }
}
