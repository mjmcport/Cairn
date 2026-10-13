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

  @Test func listsWhatAFileTakesOnDiskAndWhenItWasAddedToItsFolder() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.file("written.bin", size: 100_000)
      FixtureNode.sparseFile("sparse.img", size: 50_000_000)
      FixtureNode.directory("Folder") {
        FixtureNode.file("nested.txt")
      }
      FixtureNode.symlink("link", to: "written.bin")
      FixtureNode.bundle("Sample")
    }
    defer { try? tree.remove() }

    let items = try await DirectoryReader().items(in: tree.root)
    let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })

    let written = try #require(byName["written.bin"])
    // Whole blocks: at least the bytes written.
    #expect(try #require(written.allocatedSize) >= 100_000)
    let added = try #require(written.dateAdded)
    #expect(abs(added.timeIntervalSinceNow) < 60)

    // A sparse file is large on paper and takes almost nothing on disk.
    let sparse = try #require(byName["sparse.img"])
    #expect(sparse.size == 50_000_000)
    #expect(try #require(sparse.allocatedSize) < 1_000_000)

    // Folders, links and packages have no size on disk of their own.
    for name in ["Folder", "link", "Sample.app"] {
      #expect(byName[name]?.allocatedSize == nil, "\(name)")
    }
  }

  @Test func aListingMarksOnlyAFileWithoutBlocksAsOnlineOnly() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.file("written.bin", size: 100_000)
      FixtureNode.file("empty.txt")
      FixtureNode.directory("Folder") {
        FixtureNode.file("nested.txt")
      }
      FixtureNode.bundle("Sample")
    }
    defer { try? tree.remove() }

    let items = try await DirectoryReader().items(in: tree.root)
    // Nothing a person creates here is a placeholder.
    #expect(items.allSatisfy { !$0.isOnlineOnly })
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

  @Test func theStreamIsReadOffTheMainThreadWhenConsumedOnTheMainActor() async throws {
    let tree = try FixtureTree.build { FixtureNode.file("a.txt") }
    defer { try? tree.remove() }
    let folder = tree.root

    let ranOnMainThread = Recorded<[Bool]>([])
    let counts = try await Task { @MainActor in
      var counts: [Int] = []
      let listing = DirectoryReader.listing(in: folder) { _ in
        ranOnMainThread.value += [pthread_main_np() != 0]
      }
      for try await event in listing {
        counts.append(event.count)
      }
      return counts
    }.value
    #expect(counts == [1])
    #expect(ranOnMainThread.value == [false])
  }

  // MARK: First items

  /// The events of a listing, read to its end.
  private func collected(
    _ listing: AsyncThrowingStream<DirectoryListingEvent, any Error>
  ) async throws -> [DirectoryListingEvent] {
    var events: [DirectoryListingEvent] = []
    for try await event in listing {
      events.append(event)
    }
    return events
  }

  @Test func aFolderOfOneBatchYieldsOnlyAllItems() async throws {
    let batch = DirectoryReader.firstBatchSize
    let tree = try FixtureTree.build {
      FixtureNode.files(count: batch, in: "OneBatch")
    }
    defer { try? tree.remove() }

    let events = try await collected(DirectoryReader().listing(in: tree.url("OneBatch")))
    guard case .allItems(let all) = events.first, events.count == 1 else {
      Issue.record("Expected one all-items event, got \(events.map(\.count))")
      return
    }
    #expect(all.count == batch)
  }

  @Test func aFolderOfOneItemMoreYieldsFirstItemsThenAllItems() async throws {
    let batch = DirectoryReader.firstBatchSize
    let tree = try FixtureTree.build {
      FixtureNode.files(count: batch + 1, in: "OneMore")
    }
    defer { try? tree.remove() }

    let events = try await collected(DirectoryReader().listing(in: tree.url("OneMore")))
    guard events.count == 2, case .firstItems(let first) = events[0],
      case .allItems(let all) = events[1]
    else {
      Issue.record("Expected first items then all items, got \(events.map(\.count))")
      return
    }
    #expect(first.count == batch)
    #expect(all.count == batch + 1)
    #expect(Array(all.prefix(batch)) == first)
    #expect(Set(all.map(\.url)).count == batch + 1)
  }

  @Test func theFirstItemsDoNotDependOnHowLargeTheFolderIs() async throws {
    let batch = DirectoryReader.firstBatchSize
    let tree = try FixtureTree.build {
      FixtureNode.files(count: batch, in: "OneBatch")
      FixtureNode.files(count: batch + 1, in: "OneMore")
      FixtureNode.files(count: batch * 3, in: "Large")
    }
    defer { try? tree.remove() }

    /// How many items had been read each time the first items were handed over.
    func handOvers(in folder: String) async throws -> [Int] {
      let url = tree.url(folder)
      return try await Task {
        var counts: [Int] = []
        _ = try DirectoryReader.readItems(in: url, onFirstItems: { counts.append($0.count) })
        return counts
      }.value
    }
    #expect(try await handOvers(in: "OneBatch") == [])
    #expect(try await handOvers(in: "OneMore") == [batch])
    #expect(try await handOvers(in: "Large") == [batch])
  }

  @Test func aFailedListingFailsTheStreamAndYieldsNoEvent() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.file("file.txt")
      FixtureNode.directory("Locked") {
        FixtureNode.file("secret.txt")
      }.permissions(0o000)
    }
    defer { try? tree.remove() }

    /// The events a listing yielded and the error that ended it.
    func outcome(of folder: String) async -> (events: [DirectoryListingEvent], error: (any Error)?)
    {
      var events: [DirectoryListingEvent] = []
      do {
        for try await event in DirectoryReader().listing(in: tree.url(folder)) {
          events.append(event)
        }
        return (events, nil)
      } catch {
        return (events, error)
      }
    }
    let missing = await outcome(of: "missing")
    #expect(missing.events.isEmpty)
    #expect(missing.error != nil)
    let file = await outcome(of: "file.txt")
    #expect(file.events.isEmpty)
    #expect(file.error as? DirectoryReadError == .notADirectory(tree.url("file.txt")))
    let locked = await outcome(of: "Locked")
    #expect(locked.events.isEmpty)
    #expect(locked.error != nil)
  }

  @Test func cancellingAfterTheFirstItemsYieldsNoAllItems() async throws {
    let batch = DirectoryReader.firstBatchSize
    let interval = DirectoryReader.cancellationInterval
    // The first cancellation check after the first items were handed over.
    let checkAfterFirstItems = (batch / interval + 1) * interval
    let tree = try FixtureTree.build {
      FixtureNode.files(count: checkAfterFirstItems + interval * 2, in: "Many")
    }
    defer { try? tree.remove() }

    let checks = Recorded<[Int]>([])
    let listing = DirectoryReader.listing(in: tree.url("Many")) { itemsRead in
      checks.value += [itemsRead]
      // Cancel the listing from inside, once the first items have gone out.
      if itemsRead == checkAfterFirstItems {
        withUnsafeCurrentTask { $0?.cancel() }
      }
    }
    var events: [DirectoryListingEvent] = []
    await #expect(throws: CancellationError.self) {
      for try await event in listing {
        events.append(event)
      }
    }
    guard case .firstItems(let first) = events.first, events.count == 1 else {
      Issue.record("Expected only first items, got \(events.map(\.count))")
      return
    }
    #expect(first.count == batch)
    // It stops at the check that follows the cancellation: nothing more is read.
    #expect(checks.value.last == checkAfterFirstItems)
  }

  @Test func cancellingTheConsumerEndsTheStreamQuietlyAndCancelsTheListing() async throws {
    let interval = DirectoryReader.cancellationInterval
    let tree = try FixtureTree.build {
      FixtureNode.files(count: interval * 4, in: "Many")
    }
    defer { try? tree.remove() }

    let consumer = Recorded<Task<[DirectoryListingEvent], any Error>?>(nil)
    // The listing waits at its first check until the consumer can be cancelled,
    // and at the next until the consumer has ended, so nothing here is a race.
    let consumerIsKnown = DispatchSemaphore(value: 0)
    let consumerHasEnded = DispatchSemaphore(value: 0)
    let (listingWasCancelled, report) = AsyncStream<Bool>.makeStream()
    let listing = DirectoryReader.listing(in: tree.url("Many")) { itemsRead in
      if itemsRead == 0 {
        consumerIsKnown.wait()
      }
      if itemsRead == interval {
        consumer.value?.cancel()
        consumerHasEnded.wait()
        report.yield(withUnsafeCurrentTask { $0?.isCancelled } ?? false)
        report.finish()
      }
    }
    let task = Task { try await collected(listing) }
    consumer.value = task
    consumerIsKnown.signal()

    // The loop over a cancelled stream ends; it does not throw.
    #expect(try await task.value == [])
    #expect(task.isCancelled)
    consumerHasEnded.signal()
    // Ending the stream cancelled the task that reads the folder.
    var reports: [Bool] = []
    for await wasCancelled in listingWasCancelled {
      reports.append(wasCancelled)
    }
    #expect(reports == [true])
  }

  @Test func itemsReturnsWhatTheAllItemsEventCarries() async throws {
    let batch = DirectoryReader.firstBatchSize
    let tree = try FixtureTree.build {
      FixtureNode.files(count: batch + 1, in: "OneMore")
    }
    defer { try? tree.remove() }
    let folder = tree.url("OneMore")

    let events = try await collected(DirectoryReader().listing(in: folder))
    let items = try await DirectoryReader().items(in: folder)
    #expect(events.last == .allItems(items))
  }

  @Test func aListingThatEndsWithoutAllItemsIsAnError() async throws {
    let folder = URL(filePath: "/fixture/folder", directoryHint: .isDirectory)
    await #expect(throws: DirectoryReadError.incomplete(folder)) {
      try await EndingEarlyReader().items(in: folder)
    }
    #expect(
      DirectoryReadError.incomplete(folder).localizedDescription
        == "The contents of folder could not be read.")
  }
}

extension DirectoryListingEvent {
  /// How many items the event carries.
  fileprivate var count: Int {
    switch self {
    case .firstItems(let items), .allItems(let items): items.count
    }
  }
}

/// A listing that hands over first items and then ends.
private struct EndingEarlyReader: DirectoryReading {
  func listing(in directory: URL) -> AsyncThrowingStream<DirectoryListingEvent, any Error> {
    AsyncThrowingStream { continuation in
      continuation.yield(.firstItems([]))
      continuation.finish()
    }
  }
}

/// A value written and read from any thread.
final class Recorded<Value: Sendable>: @unchecked Sendable {
  // Guarded by `lock`.
  private var stored: Value
  private let lock = NSLock()

  init(_ value: Value) { stored = value }

  var value: Value {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}
