import Foundation
import Testing

@testable import FileOperations

@Suite struct FileOperationTests {
  private let a = URL(filePath: "/tmp/a")
  private let b = URL(filePath: "/tmp/b")
  private let folder = URL(filePath: "/tmp/folder", directoryHint: .isDirectory)

  @Test func sourcesListTheItemsAnOperationTouches() {
    #expect(FileOperation.copy(sources: [a, b], destination: folder).sources == [a, b])
    #expect(FileOperation.move(sources: [a], destination: folder).sources == [a])
    #expect(FileOperation.trash(items: [a, b]).sources == [a, b])
    #expect(FileOperation.rename(item: a, newName: "c").sources == [a])
    #expect(FileOperation.newFolder(parent: folder, name: "New").sources.isEmpty)
  }

  @Test func everythingExceptCopyIsUndoable() {
    #expect(!FileOperation.copy(sources: [a], destination: folder).isUndoable)
    #expect(FileOperation.move(sources: [a], destination: folder).isUndoable)
    #expect(FileOperation.trash(items: [a]).isUndoable)
    #expect(FileOperation.rename(item: a, newName: "c").isUndoable)
    #expect(FileOperation.newFolder(parent: folder, name: "New").isUndoable)
  }
}
