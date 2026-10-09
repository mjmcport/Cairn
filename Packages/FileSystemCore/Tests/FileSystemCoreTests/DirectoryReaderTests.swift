import Foundation
import TestSupport
import Testing

@testable import FileSystemCore

@Suite struct DirectoryReaderTests {
  private func names(_ items: [FileItem]) -> [String] { items.map(\.name).sorted() }

  @Test func listsDirectChildrenWithKindSizeAndDate() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.file("notes.txt", size: 1_234)
      FixtureNode.directory("Folder") {
        FixtureNode.file("nested.txt")
      }
      FixtureNode.symlink("link", to: "notes.txt")
      FixtureNode.bundle("Sample")
    }
    defer { try? tree.remove() }

    let items = try await DirectoryReader().items(in: tree.root)
    #expect(names(items) == ["Folder", "Sample.app", "link", "notes.txt"])

    let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
    let file = try #require(byName["notes.txt"])
    #expect(file.kind == .file)
    #expect(file.size == 1_234)
    let modified = try #require(file.modificationDate)
    #expect(abs(modified.timeIntervalSinceNow) < 60)

    #expect(byName["Folder"]?.kind == .directory)
    #expect(byName["Folder"]?.size == nil)
    #expect(byName["link"]?.kind == .symbolicLink)
    #expect(byName["Sample.app"]?.kind == .package)
    #expect(byName["Sample.app"]?.isNavigable == false)
  }

  @Test func reportsHiddenItemsSoTheCallerCanFilterThem() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.file("visible.txt")
      FixtureNode.hiddenFile("dotfile")
      FixtureNode.file("flagged.txt").hiddenFlag()
      FixtureNode.directory(".git")
    }
    defer { try? tree.remove() }

    let items = try await DirectoryReader().items(in: tree.root)
    #expect(names(items) == [".dotfile", ".git", "flagged.txt", "visible.txt"])
    #expect(names(items.visible(includingHidden: false)) == ["visible.txt"])
    #expect(items.visible(includingHidden: true).count == 4)
  }

  @Test func listsAnEmptyFolderAndUnicodeNames() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.directory("Empty")
      FixtureNode.directory("Unicode") {
        for name in FixtureNames.unicode {
          FixtureNode.file(name)
        }
      }
    }
    defer { try? tree.remove() }

    #expect(try await DirectoryReader().items(in: tree.url("Empty")).isEmpty)
    let unicode = try await DirectoryReader().items(in: tree.url("Unicode"))
    #expect(Set(unicode.map(\.name)) == Set(FixtureNames.unicode))
  }

  @Test func lists10000Items() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.files(count: 10_000, in: "Big")
    }
    defer { try? tree.remove() }

    let items = try await DirectoryReader().items(in: tree.url("Big"))
    #expect(items.count == 10_000)
    #expect(Set(items.map(\.url)).count == 10_000)
  }

  @Test func throwsForAMissingFolderAFileAndAnUnreadableFolder() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.file("file.txt")
      FixtureNode.directory("Locked") {
        FixtureNode.file("secret.txt")
      }.permissions(0o000)
    }
    defer { try? tree.remove() }

    await #expect(throws: (any Error).self) {
      try await DirectoryReader().items(in: tree.url("missing"))
    }
    await #expect(throws: DirectoryReadError.notADirectory(tree.url("file.txt"))) {
      try await DirectoryReader().items(in: tree.url("file.txt"))
    }
    await #expect(throws: (any Error).self) {
      try await DirectoryReader().items(in: tree.url("Locked"))
    }
  }

  @Test func listsAFolderReachedThroughASymbolicLink() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.directory("Folder") {
        FixtureNode.file("inside.txt")
      }
      FixtureNode.symlink("link", to: "Folder")
      FixtureNode.file("file.txt")
      FixtureNode.symlink("file-link", to: "file.txt")
      FixtureNode.symlink("broken", to: "missing")
    }
    defer { try? tree.remove() }

    #expect(names(try await DirectoryReader().items(in: tree.url("link"))) == ["inside.txt"])
    // The spelling a launch argument produces, with a trailing slash.
    let hinted = URL(filePath: tree.path("link"), directoryHint: .isDirectory)
    #expect(names(try await DirectoryReader().items(in: hinted)) == ["inside.txt"])

    await #expect(throws: DirectoryReadError.notADirectory(tree.url("file-link"))) {
      try await DirectoryReader().items(in: tree.url("file-link"))
    }
    await #expect(throws: (any Error).self) {
      try await DirectoryReader().items(in: tree.url("broken"))
    }
  }

  @Test func theErrorForAFileSaysSoInWords() {
    let error = DirectoryReadError.notADirectory(URL(filePath: "/fixture/notes.txt"))
    #expect(error.localizedDescription == "notes.txt is not a folder.")
  }

  @Test func aCancelledTaskThrowsCancellationError() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.files(count: 10_000, in: "Big")
    }
    defer { try? tree.remove() }
    let folder = tree.url("Big")

    let task = Task { try await DirectoryReader().items(in: folder) }
    task.cancel()
    await #expect(throws: CancellationError.self) {
      try await task.value
    }
  }

  @Test func cancellationStopsAListingThatIsUnderWay() async throws {
    let interval = DirectoryReader.cancellationInterval
    let tree = try FixtureTree.build {
      FixtureNode.files(count: interval * 4, in: "Many")
    }
    defer { try? tree.remove() }
    let folder = tree.url("Many")

    let checks = Recorded<[Int]>([])
    let task = Task {
      try DirectoryReader.readItems(in: folder) { itemsRead in
        checks.value += [itemsRead]
        // Cancel from inside the listing, once it is under way.
        if itemsRead == interval {
          withUnsafeCurrentTask { $0?.cancel() }
        }
      }
    }
    await #expect(throws: CancellationError.self) {
      try await task.value
    }
    // It stops at the check that follows the cancellation: nothing more is read.
    #expect(checks.value == [0, interval])
  }

  @Test func runsOffTheMainThread() async throws {
    let tree = try FixtureTree.build { FixtureNode.file("a.txt") }
    defer { try? tree.remove() }

    let reader = MainThreadRecordingReader()
    _ = try await Task { @MainActor in try await reader.items(in: tree.root) }.value
    #expect(reader.ranOnMainThread.value == false)
  }
}

/// Records which thread a nonisolated async listing runs on when awaited from
/// the main actor, the way the browser awaits ``DirectoryReader``.
private struct MainThreadRecordingReader: DirectoryReading {
  let ranOnMainThread = Recorded<Bool?>(nil)

  func items(in directory: URL) async throws -> [FileItem] {
    ranOnMainThread.value = Self.isMainThread()
    return try await DirectoryReader().items(in: directory)
  }

  private static func isMainThread() -> Bool { pthread_main_np() != 0 }
}

private final class Recorded<Value: Sendable>: @unchecked Sendable {
  // Guarded by `lock`.
  private var stored: Value
  private let lock = NSLock()

  init(_ value: Value) { stored = value }

  var value: Value {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}
