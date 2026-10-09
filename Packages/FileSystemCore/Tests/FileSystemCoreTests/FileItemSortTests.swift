import Foundation
import Testing

@testable import FileSystemCore

@Suite struct FileItemSortTests {
  private func item(
    _ name: String, kind: FileItem.Kind = .file, size: Int64? = nil, modified: TimeInterval? = nil
  ) -> FileItem {
    FileItem(
      url: URL(filePath: "/fixture/\(name)"),
      kind: kind,
      size: size,
      modificationDate: modified.map(Date.init(timeIntervalSince1970:))
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
}
