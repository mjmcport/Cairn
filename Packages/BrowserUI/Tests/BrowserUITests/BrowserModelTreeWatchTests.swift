import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// Open folders are watched and kept current by the rules of step 4, one
/// folder at a time (plans/phase-1a-step-05-list-view.md, U3). A stub watcher
/// sends the signals and a stub reader holds the listings; nothing waits on
/// a clock.
@Suite @MainActor struct BrowserModelTreeWatchTests {
  private let root = URL(filePath: "/fixture/root", directoryHint: .isDirectory)
  private var sub: URL { root.appending(path: "Sub", directoryHint: .isDirectory) }
  private var other: URL { root.appending(path: "Other", directoryHint: .isDirectory) }
  private var deep: URL { sub.appending(path: "Deep", directoryHint: .isDirectory) }

  private let subKey = FolderKey(names: ["Sub"])
  private let otherKey = FolderKey(names: ["Other"])
  private let deepKey = FolderKey(names: ["Sub", "Deep"])

  private func file(_ name: String, in folder: URL) -> FileItem {
    FileItem(url: folder.appending(path: name), kind: .file)
  }

  private func folder(_ name: String, in parent: URL) -> FileItem {
    FileItem(url: parent.appending(path: name, directoryHint: .isDirectory), kind: .directory)
  }

  private func listings() -> [URL: [FileItem]] {
    [
      root: [
        folder("Sub", in: root), folder("Other", in: root), file("a.txt", in: root),
      ],
      sub: [folder("Deep", in: sub), file("x.txt", in: sub), file("b.txt", in: sub)],
      deep: [file("z.txt", in: deep)],
      other: [file("x.txt", in: other), file("o.txt", in: other)],
    ]
  }

  private func names(_ items: [FileItem]) -> [String] { items.map(\.name) }

  private struct Rig {
    let model: BrowserModel
    let reader: StubReader
    let watcher: StubWatcher
    let answered: AnsweredSignals
  }

  /// A model that has been told to watch and has listed `root`.
  private func watchingModel(
    results: [URL: [FileItem]]? = nil, reader: StubReader? = nil,
    watcher: StubWatcher = StubWatcher()
  ) async -> Rig {
    let reader = reader ?? StubReader(results: results ?? listings())
    let model = BrowserModel(location: root, reader: reader, watcher: watcher)
    let answered = AnsweredSignals(of: model)
    model.startWatching()
    await model.load()
    return Rig(model: model, reader: reader, watcher: watcher, answered: answered)
  }

  /// What a model published, with the folder each publish was about.
  @MainActor private final class Publishes {
    private(set) var all: [(BrowserModel.Publish, FolderKey?)] = []

    init(of model: BrowserModel) {
      model.onChange = { [unowned model, unowned self] in
        all.append((model.lastPublish, model.lastChangedFolder))
      }
    }

    var kinds: [BrowserModel.Publish] { all.map(\.0) }
  }

  // MARK: Who watches

  @Test func openingAFolderStartsItsWatchAndClosingItEndsTheWatch() async {
    let rig = await watchingModel()
    #expect(rig.watcher.watched == [root])

    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    #expect(rig.watcher.requested == [root, sub])
    #expect(rig.watcher.watched == [root, sub])

    rig.model.closeFolder(subKey)
    await rig.watcher.waitForEnd(of: sub)
    #expect(rig.watcher.watched == [root])
    // Closing a folder that is not open changes no watch.
    rig.model.closeFolder(subKey)
    #expect(rig.watcher.requested == [root, sub])
  }

  @Test func closingAFolderEndsTheWatchOfEverythingOpenInsideIt() async {
    let rig = await watchingModel()
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    rig.model.openFolder(deepKey)
    await rig.model.waitForOpenFolders()
    #expect(rig.watcher.watched == [root, sub, deep])

    rig.model.closeFolder(subKey)
    await rig.watcher.waitForEnd(of: sub)
    await rig.watcher.waitForEnd(of: deep)
    #expect(rig.watcher.watched == [root])
  }

  @Test func aMoveEndsEveryWatchAndAsksForTheNewFolderAsTheCommandArrives() async {
    let rig = await watchingModel()
    rig.model.openFolder(subKey)
    rig.model.openFolder(otherKey)
    await rig.model.waitForOpenFolders()
    #expect(rig.watcher.watched.count == 3)

    #expect(rig.model.move(to: other))
    // Before any listing: the old folders are not watched, the new is.
    #expect(rig.watcher.watched == [other])
    #expect(rig.watcher.requested.last == other)
    await rig.watcher.waitForEnd(of: root)
    await rig.watcher.waitForEnd(of: sub)
  }

  @Test func stoppingEndsEveryWatchAndStartingAgainWatchesTheOpenFolders() async {
    let rig = await watchingModel()
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()

    rig.model.stopWatching()
    await rig.watcher.waitForEnd(of: root)
    await rig.watcher.waitForEnd(of: sub)
    #expect(rig.watcher.watched.isEmpty)
    #expect(rig.model.isOpen(subKey))

    rig.model.startWatching()
    #expect(Set(rig.watcher.watched) == [root, sub])
  }

  @Test func foldersOpenedWhileNothingWasWatchingAreWatchedOnceWatchingStarts() async {
    let watcher = StubWatcher()
    let model = BrowserModel(
      location: root, reader: StubReader(results: listings()), watcher: watcher)
    await model.load()
    model.openFolder(subKey)
    await model.waitForOpenFolders()
    #expect(watcher.requested.isEmpty)

    model.startWatching()
    #expect(Set(watcher.watched) == [root, sub])
  }

  // MARK: A refresh of one folder

  @Test func aSignalForAnOpenFolderPublishesThatFoldersRowsOnceAndNothingElseMoves() async {
    let rig = await watchingModel()
    rig.model.openFolder(subKey)
    rig.model.openFolder(otherKey)
    await rig.model.waitForOpenFolders()
    rig.model.selection = [other.appending(path: "o.txt")]
    let topLevel = names(rig.model.items)
    let otherRows = names(rig.model.children(of: otherKey))
    let publishes = Publishes(of: rig.model)

    var changed = listings()[sub]!
    changed.append(file("new.txt", in: sub))
    rig.reader.changed.update { $0[sub] = .items(changed) }
    await rig.watcher.send(to: sub)
    await rig.answered.wait(for: 1)

    #expect(names(rig.model.children(of: subKey)) == ["b.txt", "Deep", "new.txt", "x.txt"])
    #expect(publishes.kinds == [.folder])
    #expect(publishes.all.first?.1 == subKey)
    #expect(names(rig.model.items) == topLevel)
    #expect(names(rig.model.children(of: otherKey)) == otherRows)
    #expect(rig.model.selection == [other.appending(path: "o.txt")])
    #expect(rig.model.state == .loaded)
  }

  @Test func aSignalWhoseListingIsTheSamePublishesNothing() async {
    let rig = await watchingModel()
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    let publishes = Publishes(of: rig.model)
    let before = rig.reader.listings(of: sub)

    await rig.watcher.send(to: sub)
    await rig.answered.wait(for: 1)
    #expect(rig.reader.listings(of: sub) == before + 1)
    #expect(publishes.all.isEmpty)
  }

  @Test func aSelectionInsideARefreshedFolderKeepsTheItemsThatStillExist() async {
    let rig = await watchingModel()
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    rig.model.selection = [sub.appending(path: "x.txt"), sub.appending(path: "b.txt")]

    rig.reader.changed.update { $0[sub] = .items([self.file("x.txt", in: self.sub)]) }
    await rig.watcher.send(to: sub)
    await rig.answered.wait(for: 1)
    #expect(rig.model.selection == [sub.appending(path: "x.txt")])
  }

  @Test func theRefreshIsOfThatFolderAndNeverShowsALoadingState() async {
    let rig = await watchingModel()
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    var states: [BrowserModel.State] = []
    rig.model.onChange = { states.append(rig.model.state) }

    rig.reader.changed.update { $0[sub] = .items([self.file("only.txt", in: self.sub)]) }
    await rig.watcher.send(to: sub)
    await rig.answered.wait(for: 1)
    #expect(states == [.loaded])
  }

  // MARK: One at a time

  @Test func signalsFromTwoFoldersAreAnsweredOneAtATimeShallowestFirst() async {
    let gate = Gate()
    var reader = StubReader(results: listings())
    reader.gates[sub] = gate
    await gate.open()
    let rig = await watchingModel(reader: reader)
    rig.model.openFolder(subKey)
    rig.model.openFolder(otherKey)
    await rig.model.waitForOpenFolders()
    let otherBefore = rig.reader.listings(of: other)
    let subBefore = rig.reader.listings(of: sub)

    // The refresh of Sub is held at the reader.
    await gate.close()
    await rig.watcher.send(to: sub)
    await gate.waitUntilReached()
    #expect(rig.model.isAnsweringSignals)
    await rig.watcher.send(to: other)
    // Other waits its turn: it has not been listed again.
    #expect(rig.reader.listings(of: other) == otherBefore)

    await gate.open()
    await rig.answered.wait(for: 1)
    #expect(rig.reader.listings(of: sub) == subBefore + 1)
    #expect(rig.reader.listings(of: other) == otherBefore + 1)
    #expect(!rig.model.isAnsweringSignals)
  }

  @Test func aRefreshHeldWhileTheFolderIsClosedPublishesNothing() async {
    let gate = Gate()
    var reader = StubReader(results: listings())
    reader.gates[sub] = gate
    await gate.open()
    let rig = await watchingModel(reader: reader)
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()

    await gate.close()
    rig.reader.changed.update { $0[sub] = .items([self.file("new.txt", in: self.sub)]) }
    await rig.watcher.send(to: sub)
    await gate.waitUntilReached()
    rig.model.closeFolder(subKey)
    let publishes = Publishes(of: rig.model)

    await gate.open()
    await rig.answered.wait(for: 1)
    #expect(publishes.all.isEmpty)
    #expect(!rig.model.isOpen(subKey))
  }

  @Test func aMoveWhileAFolderRefreshIsHeldPublishesNothingFromTheOldFolder() async {
    let gate = Gate()
    var reader = StubReader(results: listings())
    reader.gates[sub] = gate
    await gate.open()
    let rig = await watchingModel(reader: reader)
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()

    await gate.close()
    rig.reader.changed.update { $0[sub] = .items([self.file("new.txt", in: self.sub)]) }
    await rig.watcher.send(to: sub)
    await gate.waitUntilReached()
    #expect(rig.model.move(to: other))
    await rig.model.load()
    let publishes = Publishes(of: rig.model)

    await gate.open()
    await rig.answered.wait(for: 1)
    #expect(publishes.all.isEmpty)
    #expect(names(rig.model.items) == ["o.txt", "x.txt"])
  }

  // MARK: Signals set aside

  @Test func aSignalForAFolderWhoseListingIsInFlightIsPaidWithOneRefreshWhenItSettles() async {
    let gate = Gate()
    var reader = StubReader(results: listings())
    reader.gates[sub] = gate
    let rig = await watchingModel(reader: reader)

    rig.model.openFolder(subKey)
    await gate.waitUntilReached()
    await rig.watcher.send(to: sub)
    await rig.answered.wait(for: 1)
    // Set aside: no second listing while the first is in flight.
    #expect(rig.reader.listings(of: sub) == 1)

    await gate.open()
    await rig.model.waitForOpenFolders()
    await rig.answered.wait(for: 2)
    #expect(rig.reader.listings(of: sub) == 2)
    #expect(names(rig.model.children(of: subKey)) == ["b.txt", "Deep", "x.txt"])
  }

  @Test func aSignalForTheTopLevelDuringALoadIsPaidWithOneRefreshWhenTheLoadSettles() async {
    let gate = Gate()
    var reader = StubReader(results: listings())
    reader.gates[root] = gate
    await gate.open()
    let rig = await watchingModel(reader: reader)
    let before = rig.reader.listings(of: root)

    await gate.close()
    let reload = Task { await rig.model.load() }
    await gate.waitUntilReached()
    #expect(rig.model.state == .loading)
    await rig.watcher.send(to: root)
    await rig.answered.wait(for: 1)
    #expect(rig.reader.listings(of: root) == before + 1)

    await gate.open()
    await reload.value
    await rig.answered.wait(for: 2)
    #expect(rig.reader.listings(of: root) == before + 2)
  }

  @Test func aSignalForAnOpenFolderDuringAReloadIsAnsweredByTheReloadsOwnListing() async {
    let gate = Gate()
    var reader = StubReader(results: listings())
    reader.gates[root] = gate
    await gate.open()
    let rig = await watchingModel(reader: reader)
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    let before = rig.reader.listings(of: sub)

    await gate.close()
    let reload = Task { await rig.model.load() }
    await gate.waitUntilReached()
    await rig.watcher.send(to: sub)
    await rig.answered.wait(for: 1)

    await gate.open()
    await reload.value
    await rig.model.waitForOpenFolders()
    // Listed again once by the reload, and not a second time for the signal.
    #expect(rig.reader.listings(of: sub) == before + 1)
  }

  // MARK: Folders that go away

  @Test func anOpenFolderThatIsDeletedClosesWithWhatWasInsideItAndEndsTheirWatches() async {
    let rig = await watchingModel()
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    rig.model.openFolder(deepKey)
    await rig.model.waitForOpenFolders()
    rig.model.selection = [deep.appending(path: "z.txt"), root.appending(path: "a.txt")]

    rig.reader.changed.update {
      $0[root] = .items([self.folder("Other", in: self.root), self.file("a.txt", in: self.root)])
    }
    await rig.watcher.send(to: root)
    await rig.answered.wait(for: 1)

    #expect(!rig.model.isOpen(subKey))
    #expect(!rig.model.isOpen(deepKey))
    await rig.watcher.waitForEnd(of: sub)
    await rig.watcher.waitForEnd(of: deep)
    #expect(rig.watcher.watched == [root])
    #expect(rig.model.selection == [root.appending(path: "a.txt")])
  }

  @Test func aFolderThatCannotBeListedOnASignalShowsWhyOnceAndIsListedWhenItCan() async {
    let rig = await watchingModel()
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    let publishes = Publishes(of: rig.model)

    rig.reader.changed.update { $0[sub] = .missing }
    await rig.watcher.send(to: sub)
    await rig.answered.wait(for: 1)
    #expect(rig.model.failure(of: subKey) != nil)
    #expect(rig.model.children(of: subKey).isEmpty)
    #expect(publishes.kinds == [.folder])

    // The same failure again is not news.
    await rig.watcher.send(to: sub)
    await rig.answered.wait(for: 2)
    #expect(publishes.kinds == [.folder])

    rig.reader.changed.update { $0[sub] = .items([self.file("back.txt", in: self.sub)]) }
    await rig.watcher.send(to: sub)
    await rig.answered.wait(for: 3)
    #expect(rig.model.failure(of: subKey) == nil)
    #expect(names(rig.model.children(of: subKey)) == ["back.txt"])
    #expect(publishes.kinds == [.folder, .folder])
  }

  @Test func aFolderThatFailsClosesTheFoldersOpenInsideIt() async {
    let rig = await watchingModel()
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    rig.model.openFolder(deepKey)
    await rig.model.waitForOpenFolders()

    rig.reader.changed.update { $0[sub] = .missing }
    await rig.watcher.send(to: sub)
    await rig.answered.wait(for: 1)
    #expect(rig.model.isOpen(subKey))
    #expect(!rig.model.isOpen(deepKey))
    await rig.watcher.waitForEnd(of: deep)
  }

  // MARK: Many folders, and a watch that cannot start

  @Test func fiftyOpenFoldersAreWatchedEachOnce() async {
    var results: [URL: [FileItem]] = [:]
    var top: [FileItem] = []
    for index in 0..<50 {
      let folder = folder("F\(index)", in: root)
      top.append(folder)
      results[folder.url] = [file("f.txt", in: folder.url)]
    }
    results[root] = top
    let rig = await watchingModel(results: results)

    for index in 0..<50 {
      #expect(rig.model.openFolder(FolderKey(names: ["F\(index)"])))
    }
    await rig.model.waitForOpenFolders()

    #expect(rig.watcher.watched.count == 51)
    #expect(Set(rig.watcher.requested).count == 51)
    #expect(rig.model.openFolders.values.allSatisfy { $0.listing == .listed })
  }

  @Test func aWatchThatCannotStartLeavesTheFoldersListedAndTheBrowserWorking() async {
    let rig = await watchingModel(watcher: StubWatcher(endsAtOnce: true))
    rig.model.openFolder(subKey)
    await rig.model.waitForOpenFolders()
    #expect(names(rig.model.children(of: subKey)) == ["b.txt", "Deep", "x.txt"])
    #expect(rig.model.state == .loaded)

    #expect(rig.model.move(to: other))
    await rig.model.load()
    #expect(names(rig.model.items) == ["o.txt", "x.txt"])
  }
}
