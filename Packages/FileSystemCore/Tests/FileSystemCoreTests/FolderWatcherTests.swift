import CoreServices
import Foundation
import TestSupport
import Testing

@testable import FileSystemCore

@Suite struct FolderWatcherTests {
  // MARK: Which events concern the folder

  private func concerns(_ path: String, flags: Int = 0, folder: String = "/a/b") -> Bool {
    FolderWatcher.eventConcernsFolder(
      path: path, flags: FSEventStreamEventFlags(flags), folder: folder)
  }

  @Test func anEventAboutTheFolderItselfConcernsIt() {
    #expect(concerns("/a/b"))
    #expect(concerns("/a/b/"))
    #expect(concerns("/a/b", folder: "/a/b/"))
  }

  @Test func anEventAboutADirectSubfolderConcernsIt() {
    #expect(concerns("/a/b/sub"))
    #expect(concerns("/a/b/sub/"))
  }

  @Test func anEventTwoLevelsDownDoesNot() {
    #expect(!concerns("/a/b/sub/deep"))
    #expect(!concerns("/a/b/sub/deep/"))
  }

  @Test func aSiblingWhoseNameStartsWithTheFoldersNameDoesNot() {
    #expect(!concerns("/a/b2"))
    #expect(!concerns("/a/b2/"))
    #expect(!concerns("/a/b2/sub/"))
    // Nor does the folder above.
    #expect(!concerns("/a/"))
  }

  @Test func anyPathWithTheRootChangedOrMustScanFlagDoes() {
    #expect(concerns("/elsewhere/entirely", flags: kFSEventStreamEventFlagRootChanged))
    #expect(concerns("/a/b/sub/deep/", flags: kFSEventStreamEventFlagMustScanSubDirs))
    // A flag that says nothing about the folder changes nothing.
    #expect(!concerns("/a/b/sub/deep/", flags: kFSEventStreamEventFlagItemIsFile))
  }

  @Test func theRootFolderIsConcernedByItselfAndItsDirectSubfolders() {
    #expect(concerns("/", folder: "/"))
    #expect(concerns("/Users/", folder: "/"))
    #expect(!concerns("/Users/someone/", folder: "/"))
  }

  // MARK: A real FSEvents stream
  //
  // These wait, with a bound, for a signal to arrive. They never assert how
  // many arrive, apart from the burst test: a new stream can report events
  // from just before it started. Where a test needs to know that a signal
  // was caused by what it just did, it watches a folder that was empty and
  // untouched when the watch began, and makes every change after `live`.

  /// How long a test waits for a signal that should arrive.
  private static let bound: Duration = .seconds(10)

  /// Reads a stream of signals into a list a test can poll.
  private final class Listener: Sendable {
    let signals = Recorded<[FolderChangeSignal]>([])
    let callbacks = Recorded<Int>(0)
    let callbacksWhenStopped = Recorded<Int?>(nil)
    private let consumer = Recorded<Task<Void, Never>?>(nil)

    init(watching folder: URL) {
      let (signals, callbacks, callbacksWhenStopped) = (signals, callbacks, callbacksWhenStopped)
      let stream = FolderWatcher.signals(
        for: folder,
        hooks: FolderWatcher.Hooks(
          // Both hooks run on the watch's one queue, so the count is exact.
          onCallback: { callbacks.value += 1 },
          onStopped: { callbacksWhenStopped.value = callbacks.value }))
      consumer.value = Task {
        for await signal in stream {
          signals.value += [signal]
        }
      }
    }

    var count: Int { signals.value.count }

    func count(of signal: FolderChangeSignal) -> Int {
      signals.value.count { $0 == signal }
    }

    /// Stops reading, which stops the watch.
    func cancel() {
      consumer.value?.cancel()
    }

    deinit { cancel() }
  }

  /// Waits until `condition` holds, for at most ``bound``.
  /// - Returns: Whether it came to hold.
  private func eventually(_ condition: @Sendable () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + Self.bound
    while !condition() {
      guard ContinuousClock.now < deadline else { return false }
      try? await Task.sleep(for: .milliseconds(5))
    }
    return true
  }

  /// A listener on `folder` whose watch is live.
  private func liveListener(watching folder: URL) async throws -> Listener {
    let listener = Listener(watching: folder)
    try #require(await eventually { listener.signals.value.first == .live })
    return listener
  }

  /// Does `change` and waits for a signal that arrived after it began.
  private func signalFollows(_ listener: Listener, _ change: () throws -> Void) async rethrows
    -> Bool
  {
    let before = listener.count
    try change()
    return await eventually { listener.count > before }
  }

  private func createFile(_ url: URL) throws {
    try Data().write(to: url, options: .withoutOverwriting)
  }

  /// A fixture whose folder `Watched` is empty.
  private func treeWithAnEmptyFolder() throws -> (tree: FixtureTree, watched: URL) {
    let tree = try FixtureTree.build { FixtureNode.directory("Watched") }
    return (tree, tree.url("Watched"))
  }

  @Test func aFileCreatedStraightAfterTheWatchIsLiveBringsASignal() async throws {
    let (tree, watched) = try treeWithAnEmptyFolder()
    defer { try? tree.remove() }
    let listener = try await liveListener(watching: watched)

    // No wait between `live` and the change.
    #expect(try await signalFollows(listener) { try createFile(watched.appending(path: "a.txt")) })
    #expect(listener.signals.value == [.live, .contentsChanged])
  }

  @Test func renamingDeletingAndModifyingAFileEachBringASignal() async throws {
    let (tree, watched) = try treeWithAnEmptyFolder()
    defer { try? tree.remove() }
    let listener = try await liveListener(watching: watched)
    let (a, b, c) = (
      watched.appending(path: "a.txt"), watched.appending(path: "b.txt"),
      watched.appending(path: "c.txt")
    )
    try #require(
      await signalFollows(listener) {
        try createFile(a)
        try createFile(b)
      })

    #expect(try await signalFollows(listener) { try FileManager.default.moveItem(at: a, to: c) })
    #expect(try await signalFollows(listener) { try FileManager.default.removeItem(at: c) })
    #expect(
      try await signalFollows(listener) {
        let handle = try FileHandle(forWritingTo: b)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("more".utf8))
        try handle.close()
      })
  }

  @Test func aFileCreatedInsideADirectSubfolderBringsASignal() async throws {
    let (tree, watched) = try treeWithAnEmptyFolder()
    defer { try? tree.remove() }
    let listener = try await liveListener(watching: watched)
    let sub = watched.appending(path: "Sub", directoryHint: .isDirectory)
    try #require(
      await signalFollows(listener) {
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
      })

    #expect(try await signalFollows(listener) { try createFile(sub.appending(path: "inner.txt")) })
  }

  @Test func aFolderWatchedThroughASymbolicLinkReportsAFileCreatedInIt() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.directory("Real")
      FixtureNode.symlink("Link", to: "Real")
    }
    defer { try? tree.remove() }
    let listener = try await liveListener(watching: tree.url("Link"))

    #expect(try await signalFollows(listener) { try createFile(tree.url("Real/a.txt")) })
    #expect(listener.signals.value == [.live, .contentsChanged])
  }

  @Test func deletingTheWatchedFolderBringsASignalAndSoDoesRenamingItAway() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.directory("Deleted")
      FixtureNode.directory("Renamed")
    }
    defer { try? tree.remove() }

    let deleted = try await liveListener(watching: tree.url("Deleted"))
    try FileManager.default.removeItem(at: tree.url("Deleted"))
    #expect(await eventually { deleted.count(of: .folderChanged) == 1 })

    let renamed = try await liveListener(watching: tree.url("Renamed"))
    try FileManager.default.moveItem(at: tree.url("Renamed"), to: tree.url("Elsewhere"))
    #expect(await eventually { renamed.count(of: .folderChanged) == 1 })
  }

  @Test func afterTheFolderIsDeletedAndCreatedAgainAFileCreatedInItBringsASignal() async throws {
    let (tree, watched) = try treeWithAnEmptyFolder()
    defer { try? tree.remove() }
    let listener = try await liveListener(watching: watched)

    try FileManager.default.removeItem(at: watched)
    try #require(
      await eventually { listener.count(of: .folderChanged) == 1 }, "\(listener.signals.value)")
    try FileManager.default.createDirectory(at: watched, withIntermediateDirectories: false)
    try #require(
      await eventually { listener.count(of: .folderChanged) == 2 }, "\(listener.signals.value)")

    // Twice: the deletion can still have one late report on its way, which
    // would answer for the first file. Nothing else can answer for both.
    for name in ["first.txt", "second.txt"] {
      let before = listener.count(of: .contentsChanged)
      try createFile(watched.appending(path: name))
      #expect(await eventually { listener.count(of: .contentsChanged) > before })
    }
  }

  /// The case a single FSEvents stream gets wrong: created again within a
  /// millisecond of being deleted, as `rm -rf x && mkdir x` does, the folder
  /// is not reported as back and the stream says nothing more about it. The
  /// watcher answers a change to the folder with a new stream, which does.
  @Test func aFolderDeletedAndCreatedAgainAtOnceStillReportsFilesCreatedInIt() async throws {
    let (tree, watched) = try treeWithAnEmptyFolder()
    defer { try? tree.remove() }
    let listener = try await liveListener(watching: watched)

    try FileManager.default.removeItem(at: watched)
    try FileManager.default.createDirectory(at: watched, withIntermediateDirectories: false)
    try #require(
      await eventually { listener.count(of: .folderChanged) >= 1 }, "\(listener.signals.value)")

    // Twice: a report of the creation can still be on its way and would
    // answer for the first file. Nothing else can answer for both.
    for name in ["first.txt", "second.txt"] {
      #expect(
        try await signalFollows(listener) { try createFile(watched.appending(path: name)) },
        "\(name): \(listener.signals.value)")
    }
  }

  /// The one test that waits a fixed time: the collecting is FSEvents' own,
  /// so the only way to count what a burst became is to give it time.
  @Test func twoHundredFilesCreatedInOneLoopBringFarFewerSignals() async throws {
    let (tree, watched) = try treeWithAnEmptyFolder()
    defer { try? tree.remove() }
    let listener = try await liveListener(watching: watched)

    for index in 0..<200 {
      try createFile(watched.appending(path: FixtureNames.numbered(index)))
    }
    try await Task.sleep(for: .seconds(1))
    let signals = listener.count(of: .contentsChanged)
    #expect(signals >= 1)
    #expect(signals <= 10, "\(signals) signals for 200 files")
  }

  @Test func cancellingTheConsumerStopsTheWatchAndNothingIsReportedAfterwards() async throws {
    let (tree, watched) = try treeWithAnEmptyFolder()
    defer { try? tree.remove() }
    let listener = try await liveListener(watching: watched)
    try #require(listener.callbacksWhenStopped.value == nil)

    listener.cancel()
    try #require(await eventually { listener.callbacksWhenStopped.value != nil })

    // A second watch on the same folder says when FSEvents has reported the
    // file, so the first one's silence is not a matter of waiting.
    let second = try await liveListener(watching: watched)
    try #require(await signalFollows(second) { try createFile(watched.appending(path: "a.txt")) })
    #expect(listener.callbacks.value == listener.callbacksWhenStopped.value)
  }

  @Test func aLocationThatDoesNotExistCanBeWatchedAndHearsOfItsCreation() async throws {
    let tree = try FixtureTree.build { FixtureNode.file("a.txt") }
    defer { try? tree.remove() }
    let missing = tree.url("missing")
    let listener = try await liveListener(watching: missing)

    try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: false)
    #expect(await eventually { listener.count(of: .folderChanged) == 1 })
  }
}
