import Foundation
import Testing

@testable import FileSystemCore

@Suite struct FileItemTests {
  @Test func nameIsTheLastPathComponent() {
    let item = FileItem(url: URL(filePath: "/tmp/Projects/notes.txt"), kind: .file)
    #expect(item.name == "notes.txt")
    #expect(item.id == item.url)
  }

  @Test(arguments: [
    (FileItem.Kind.directory, true),
    (.file, false),
    (.symbolicLink, false),
    (.package, false),
  ])
  func onlyPlainFoldersAreNavigable(kind: FileItem.Kind, expected: Bool) {
    let item = FileItem(url: URL(filePath: "/tmp/item"), kind: kind)
    #expect(item.isNavigable == expected)
  }

  @Test func itemsAreNotHiddenByDefault() {
    #expect(!FileItem(url: URL(filePath: "/tmp/a"), kind: .file).isHidden)
  }

  @Test func sizeAndDateAreAbsentUnlessGiven() {
    let item = FileItem(url: URL(filePath: "/tmp/a"), kind: .file)
    #expect(item.size == nil)
    #expect(item.modificationDate == nil)
    #expect(item.allocatedSize == nil)
    #expect(item.dateAdded == nil)
  }

  @Test func theListingKeysCoverEveryValueAnItemHolds() {
    let keys = FileItem.resourceKeys
    #expect(keys.contains(.totalFileAllocatedSizeKey))
    #expect(keys.contains(.addedToDirectoryDateKey))
  }

  @Test func itemsThatDifferOnlyInTheNewValuesAreNotEqual() {
    let url = URL(filePath: "/tmp/a")
    let base = FileItem(url: url, kind: .file, size: 1)
    #expect(base != FileItem(url: url, kind: .file, size: 1, allocatedSize: 4_096))
    #expect(
      base != FileItem(url: url, kind: .file, size: 1, dateAdded: Date(timeIntervalSince1970: 1)))
  }
}
