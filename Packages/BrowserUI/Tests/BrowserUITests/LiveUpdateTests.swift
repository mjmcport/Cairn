import FileSystemCore
import Foundation
import TestSupport
import Testing

@testable import BrowserUI

/// The real pieces together: a model with the real reader and the real
/// FSEvents watcher, on fixture folders. Every wait has a bound, and one test
/// asserts that a change shows within a second (quality bar 5).
@Suite @MainActor struct LiveUpdateTests {
  /// How long a test waits for something that should happen.
  private static let bound: Duration = .seconds(10)

  /// How long the watch must be silent before a test changes the disk: well
  /// over FSEvents' own 0.3 s collecting time.
  private static let quiet: Duration = .seconds(1)

  /// Waits until `condition` holds, for at most ``bound``.
  /// - Returns: Whether it came to hold.
  private func eventually(_ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + Self.bound
    while !condition() {
      guard ContinuousClock.now < deadline else { return false }
      try? await Task.sleep(for: .milliseconds(2))
    }
    return true
  }

  /// A model on `folder`, loaded and watching, whose watch is live and whose
  /// first look after going live is over. Nothing on disk has been touched
  /// since the fixture was built.
  private func watchingModel(on folder: URL) async throws -> BrowserModel {
    try await watching(on: folder).model
  }

  private func watching(on folder: URL) async throws -> (
    model: BrowserModel, answered: AnsweredSignals
  ) {
    let model = BrowserModel(location: folder)
    let answered = AnsweredSignals(of: model)
    model.startWatching()
    await model.load()
    try #require(model.state == .loaded)
    try #require(await eventually { answered.count >= 1 }, "The watch never went live")
    try await waitUntilQuiet(answered)
    return (model, answered)
  }

  /// Waits until the model has answered no signal for ``quiet``. A new stream
  /// can deliver events from just before it started, such as the ones that
  /// built the fixture; so that a test's own change is the only thing left to
  /// be seen, they are let through first.
  private func waitUntilQuiet(_ answered: AnsweredSignals) async throws {
    var seen = answered.count
    var quietSince = ContinuousClock.now
    let deadline = ContinuousClock.now + Self.bound
    while ContinuousClock.now - quietSince < Self.quiet {
      try #require(ContinuousClock.now < deadline, "The watch never went quiet")
      try? await Task.sleep(for: .milliseconds(20))
      if answered.count != seen {
        seen = answered.count
        quietSince = .now
      }
    }
  }

  private func names(_ model: BrowserModel) -> [String] {
    model.items.map(\.name)
  }

  @Test func aFileCreatedInAWatchedFolderShowsWithinOneSecond() async throws {
    let tree = try FixtureTree.build {
      for index in 0..<100 {
        FixtureNode.file(FixtureNames.numbered(index))
      }
    }
    defer { try? tree.remove() }
    let model = try await watchingModel(on: tree.root)
    try #require(model.items.count == 100)

    var shownAt: ContinuousClock.Instant?
    model.onChange = { [unowned model] in
      if shownAt == nil, model.items.contains(where: { $0.name == "new.txt" }) {
        shownAt = .now
      }
    }
    try Data().write(to: tree.url("new.txt"), options: .withoutOverwriting)
    let created = ContinuousClock.now

    try #require(await eventually { shownAt != nil }, "The new file never showed")
    let elapsed = try #require(shownAt) - created
    // For the step's record of what the bound leaves to spare.
    print("LiveUpdateTests: a new file showed after \(elapsed)")
    #expect(elapsed < .seconds(1))
    #expect(model.items.count == 101)
    #expect(model.state == .loaded)
    #expect(model.lastPublish == .refresh)
  }

  @Test func aLocationSpelledThroughASymbolicLinkShowsANewFileAndKeepsItsSelection() async throws {
    let tree = try FixtureTree.build {
      FixtureNode.directory("Real") {
        FixtureNode.file("a.txt")
        FixtureNode.file("b.txt")
      }
      FixtureNode.symlink("Link", to: "Real")
    }
    defer { try? tree.remove() }
    let model = try await watchingModel(on: tree.url("Link"))
    try #require(names(model) == ["a.txt", "b.txt"])
    model.selection = [try #require(model.items.first { $0.name == "b.txt" }).url]

    try Data().write(to: tree.url("Real/a-new.txt"), options: .withoutOverwriting)
    #expect(await eventually { names(model) == ["a-new.txt", "a.txt", "b.txt"] })
    #expect(model.selection.map(\.lastPathComponent) == ["b.txt"])
  }

  @Test func aWatchedFolderThatIsRemovedFailsWithoutLoadingAndIsListedWhenItComesBack()
    async throws
  {
    let tree = try FixtureTree.build {
      FixtureNode.directory("Watched") {
        FixtureNode.file("a.txt")
      }
    }
    defer { try? tree.remove() }
    let watched = tree.url("Watched")
    let model = try await watchingModel(on: watched)
    try #require(names(model) == ["a.txt"])
    var states: [BrowserModel.State] = []
    model.onChange = { [unowned model] in states.append(model.state) }

    try FileManager.default.removeItem(at: watched)
    let failed = await eventually {
      if case .failed = model.state { return true }
      return false
    }
    #expect(failed, "The model never noticed its folder was gone")
    #expect(model.items.isEmpty)
    #expect(!states.contains(.loading))

    try FileManager.default.createDirectory(at: watched, withIntermediateDirectories: false)
    try Data().write(to: watched.appending(path: "back.txt"), options: .withoutOverwriting)
    #expect(await eventually { model.state == .loaded && names(model) == ["back.txt"] })
    #expect(!states.contains(.loading))
  }

  @Test func aFileCreatedInAnOpenFolderShowsWithinOneSecondAndKeepsTheSelectionAndTheOpenState()
    async throws
  {
    let tree = try FixtureTree.build {
      FixtureNode.file("top.txt")
      FixtureNode.directory("Sub") {
        for index in 0..<50 {
          FixtureNode.file(FixtureNames.numbered(index))
        }
      }
    }
    defer { try? tree.remove() }
    let (model, answered) = try await watching(on: tree.root)
    let subKey = FolderKey(names: ["Sub"])
    #expect(model.openFolder(subKey))
    await model.waitForOpenFolders()
    try #require(model.children(of: subKey).count == 50)
    // The new folder's own watch goes live and its first look is over.
    let afterOpen = answered.count
    try #require(
      await eventually { answered.count > afterOpen }, "The open folder's watch never went live")
    try await waitUntilQuiet(answered)

    let selected = try #require(model.children(of: subKey).first)
    model.selection = [selected.url]
    var shownAt: ContinuousClock.Instant?
    var shownWith: BrowserModel.Publish?
    model.onChange = { [unowned model] in
      if shownAt == nil, model.children(of: subKey).contains(where: { $0.name == "new.txt" }) {
        shownAt = .now
        shownWith = model.lastPublish
      }
    }
    let subURL = try #require(model.items.first { $0.name == "Sub" }).url
    try Data().write(to: subURL.appending(path: "new.txt"), options: .withoutOverwriting)
    let created = ContinuousClock.now

    try #require(await eventually { shownAt != nil }, "The new file never showed")
    let elapsed = try #require(shownAt) - created
    print("LiveUpdateTests: a new file in an open folder showed after \(elapsed)")
    #expect(elapsed < .seconds(1))
    #expect(model.isOpen(subKey))
    #expect(model.children(of: subKey).count == 51)
    #expect(model.selection == [selected.url])
    // The folder's rows arrive as a folder publish. The top level may then
    // refresh as well, because the folder's modified date changed.
    #expect(shownWith == .folder)
    #expect(names(model) == ["Sub", "top.txt"])
  }
}
