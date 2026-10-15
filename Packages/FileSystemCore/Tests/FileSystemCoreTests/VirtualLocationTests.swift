import Foundation
import TestSupport
import Testing

@testable import FileSystemCore

@Suite struct VirtualLocationTests {
  @Test(arguments: ["Red", "Work & Home", "What? #1", "Café", "a/b", "100%"])
  func aTagRoundTripsThroughItsURL(name: String) {
    let location = VirtualLocation.tag(name)
    #expect(VirtualLocation(url: location.url) == location)
    #expect(VirtualLocation.isVirtual(location.url))
  }

  @Test func recentsRoundTripAndTitleTheTab() {
    #expect(VirtualLocation(url: VirtualLocation.recents.url) == .recents)
    #expect(VirtualLocation.recents.url.lastPathComponent == "Recents")
    #expect(VirtualLocation.tag("Red").url.lastPathComponent == "Red")
    #expect(VirtualLocation.tag("Red").title == "Red")
  }

  @Test func aFolderURLIsNotVirtual() {
    let url = URL(filePath: "/Users", directoryHint: .isDirectory)
    #expect(VirtualLocation(url: url) == nil)
    #expect(!VirtualLocation.isVirtual(url))
  }

  @Test func aTagURLWithNoNameIsNotALocation() throws {
    #expect(VirtualLocation(url: try #require(URL(string: "cairn-tag:///"))) == nil)
  }
}

@Suite struct MetadataQueryReaderTests {
  private struct Stub: VirtualLocationSearching {
    let urls: [URL]
    func files(at location: VirtualLocation, limit: Int) async throws -> [URL] {
      Array(urls.prefix(limit))
    }
  }

  private struct Failing: VirtualLocationSearching {
    struct Boom: Error, Equatable {}
    func files(at location: VirtualLocation, limit: Int) async throws -> [URL] { throw Boom() }
  }

  /// Reports that it started, then waits, and reports when it was cancelled.
  private struct Waiting: VirtualLocationSearching {
    let started: AsyncStream<Void>.Continuation
    let cancelled: AsyncStream<Void>.Continuation

    func files(at location: VirtualLocation, limit: Int) async throws -> [URL] {
      try await withTaskCancellationHandler {
        started.yield()
        // Bounded, so a missed cancellation ends the test instead of hanging it.
        try await Task.sleep(for: .seconds(30))
        return []
      } onCancel: {
        cancelled.yield()
      }
    }
  }

  private func events(
    _ reader: some DirectoryReading, _ location: VirtualLocation
  ) async throws -> [DirectoryListingEvent] {
    var found: [DirectoryListingEvent] = []
    for try await event in reader.listing(in: location.url) { found.append(event) }
    return found
  }

  @Test func yieldsAllItemsOnceWithTheFilesMetadata() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.file("a.txt", size: 10)
      FixtureNode.directory("Dir")
    }
    defer { try? tree.remove() }

    let reader = MetadataQueryReader(
      searcher: Stub(urls: [tree.url("a.txt"), tree.url("Dir")]))
    let found = try await events(reader, .tag("Red"))
    #expect(found.count == 1)
    guard case .allItems(let items) = try #require(found.first) else {
      Issue.record("Expected allItems")
      return
    }
    #expect(items.map(\.name) == ["a.txt", "Dir"])
    #expect(items[0].size == 10)
    #expect(items[1].kind == .directory)
  }

  @Test func aResultForAFileThatIsGoneIsLeftOut() async throws {
    let tree = try FixtureTree.build { FixtureNode.file("here.txt") }
    defer { try? tree.remove() }

    let reader = MetadataQueryReader(
      searcher: Stub(urls: [tree.url("gone.txt"), tree.url("here.txt")]))
    let items = try await reader.items(in: VirtualLocation.recents.url)
    #expect(items.map(\.name) == ["here.txt"])
  }

  @Test func theListingIsLimited() async throws {
    let urls = (0..<(MetadataQueryReader.limit + 50)).map { URL(filePath: "/nonexistent/\($0)") }
    let searcherSaw = LimitRecorder()
    struct Recording: VirtualLocationSearching {
      let recorder: LimitRecorder
      let urls: [URL]
      func files(at location: VirtualLocation, limit: Int) async throws -> [URL] {
        recorder.limit = limit
        return urls
      }
    }
    _ = try await MetadataQueryReader(searcher: Recording(recorder: searcherSaw, urls: urls))
      .items(in: VirtualLocation.recents.url)
    #expect(searcherSaw.limit == MetadataQueryReader.limit)
  }

  private final class LimitRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var limit: Int {
      get { lock.withLock { stored } }
      set { lock.withLock { stored = newValue } }
    }
  }

  @Test func aFailedSearchEndsTheStreamWithItsError() async {
    let reader = MetadataQueryReader(searcher: Failing())
    await #expect(throws: Failing.Boom.self) {
      _ = try await events(reader, .tag("Red"))
    }
  }

  @Test func aURLThatIsNotVirtualIsRefused() async {
    let reader = MetadataQueryReader(searcher: Stub(urls: []))
    let folder = URL(filePath: "/tmp", directoryHint: .isDirectory)
    await #expect(throws: DirectoryReadError.notADirectory(folder)) {
      for try await _ in reader.listing(in: folder) {}
    }
  }

  @Test func cancellingTheConsumerStopsTheSearch() async {
    let (started, startedContinuation) = AsyncStream<Void>.makeStream()
    let (cancelled, cancelledContinuation) = AsyncStream<Void>.makeStream()
    let reader = MetadataQueryReader(
      searcher: Waiting(started: startedContinuation, cancelled: cancelledContinuation))

    let consumer = Task {
      for try await _ in reader.listing(in: VirtualLocation.recents.url) {}
    }
    for await _ in started.prefix(1) { break }
    consumer.cancel()
    for await _ in cancelled.prefix(1) { break }
    _ = try? await consumer.value
  }

  @Test @MainActor func buildingItemsOnTheMainThreadTripsTheGuard() {
    final class Count: @unchecked Sendable {
      private let lock = NSLock()
      private var stored = 0
      var value: Int { lock.withLock { stored } }
      func bump() { lock.withLock { stored += 1 } }
    }
    let count = Count()
    MainThreadGuard.withHandler({ _ in count.bump() }) {
      _ = MetadataQueryReader.items(for: [])
    }
    #expect(count.value == 1)
  }
}

@Suite struct CompositeReaderTests {
  private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var all: [String] { lock.withLock { stored } }
    func record(_ name: String) { lock.withLock { stored.append(name) } }
  }

  private struct Named: DirectoryReading {
    let name: String
    let recorder: Recorder
    func listing(in directory: URL) -> AsyncThrowingStream<DirectoryListingEvent, any Error> {
      recorder.record("\(name):\(directory.absoluteString)")
      return AsyncThrowingStream {
        $0.yield(.allItems([])); $0.finish()
      }
    }
  }

  @Test func aFolderGoesToTheFolderReaderAndAVirtualLocationToTheQueryReader() async throws {
    let recorder = Recorder()
    let reader = CompositeReader(
      files: Named(name: "files", recorder: recorder),
      virtual: Named(name: "virtual", recorder: recorder))

    let folder = URL(filePath: "/Users", directoryHint: .isDirectory)
    _ = try await reader.items(in: folder)
    _ = try await reader.items(in: VirtualLocation.tag("Red").url)
    _ = try await reader.items(in: VirtualLocation.recents.url)

    #expect(
      recorder.all == [
        "files:\(folder.absoluteString)",
        "virtual:\(VirtualLocation.tag("Red").url.absoluteString)",
        "virtual:\(VirtualLocation.recents.url.absoluteString)",
      ])
  }

  @Test func theDefaultReaderStillListsARealFolder() async throws {
    let tree = try FixtureTree.build { FixtureNode.file("one.txt") }
    defer { try? tree.remove() }
    let items = try await CompositeReader().items(in: tree.root)
    #expect(items.map(\.name) == ["one.txt"])
  }
}
