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
  }
}
