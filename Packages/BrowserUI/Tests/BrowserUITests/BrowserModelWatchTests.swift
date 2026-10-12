import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// The model's watch session, driven by a stub watcher and a stub reader.
/// No test waits on a clock: each waits on a gate, on the hook that fires
/// when the session has finished with its signals, or on a stream's end.
@Suite @MainActor struct BrowserModelWatchTests {
  private let folder = URL(filePath: "/fixture/folder", directoryHint: .isDirectory)
  private let other = URL(filePath: "/fixture/other", directoryHint: .isDirectory)

  private func item(_ name: String, in parent: URL? = nil) -> FileItem {
    FileItem(
      url: (parent ?? folder).appending(path: name), kind: .file, isHidden: name.hasPrefix("."))
  }

  private func items(_ names: String...) -> [FileItem] {
    names.map { item($0) }
  }

  private func names(_ model: BrowserModel) -> [String] {
    model.items.map(\.name)
  }

  private func selectedNames(_ model: BrowserModel) -> [String] {
    model.selection.map(\.lastPathComponent).sorted()
  }

  /// A reader in which `folder` holds `names` and `other` holds one file.
  private func reader(
    _ names: String..., gate: Gate? = nil, first: [String]? = nil, gateAfterFirst: Gate? = nil
  ) -> StubReader {
    StubReader(
      results: [folder: names.map { item($0) }, other: [item("elsewhere.txt", in: other)]],
      gates: gate.map { [folder: $0] } ?? [:],
      firstItems: first.map { [folder: $0.map { item($0) }] } ?? [:],
      gatesAfterFirstItems: gateAfterFirst.map { [folder: $0] } ?? [:])
  }

  /// A model on `folder` that has been told to watch. Not loaded.
  private func watchingModel(reader: StubReader, arrange: BrowserModel.Arrange? = nil) -> (
    model: BrowserModel, watcher: StubWatcher, answered: AnsweredSignals
  ) {
    let watcher = StubWatcher()
    let model =
      if let arrange {
        BrowserModel(location: folder, reader: reader, watcher: watcher, arrange: arrange)
      } else {
        BrowserModel(location: folder, reader: reader, watcher: watcher)
      }
    let answered = AnsweredSignals(of: model)
    model.startWatching()
    return (model, watcher, answered)
  }

  /// A filter-and-sort that holds its call number `held`, counted from 0, at
  /// `gate`. It returns a result even in a cancelled task, so the model has
  /// to notice by itself.
  private func arrange(holdingCall held: Int, at gate: Gate) -> BrowserModel.Arrange {
    let calls = Counter()
    return { items, sort, includingHidden in
      if calls.next() == held {
        await gate.pass()
      }
      return sort.sorted(items.visible(includingHidden: includingHidden))
    }
  }

  /// What a model published and the state it was in each time.
  @MainActor private final class Publishes {
    private(set) var all: [String] = []

    init(of model: BrowserModel) {
      model.onChange = { [unowned model, unowned self] in
        all.append("\(model.lastPublish) \(model.state)")
      }
    }
  }

  // MARK: Who watches

  @Test func aModelWatchesOnlyOnceItIsToldToAndAsksOnce() async {
    let watcher = StubWatcher()
    let model = BrowserModel(location: folder, reader: reader("a"), watcher: watcher)
    await model.load()
    #expect(watcher.requested.isEmpty)

    model.startWatching()
    model.startWatching()
    #expect(model.isWatching)
    #expect(watcher.requested == [folder])
    #expect(watcher.watched == [folder])

    // A model that was given no watcher has nothing to start.
    let unwatched = BrowserModel(location: folder, reader: reader("a"))
    unwatched.startWatching()
    #expect(!unwatched.isWatching)
    await unwatched.load()
    #expect(unwatched.state == .loaded)
  }

  // MARK: A refresh

  @Test func aSignalWithAChangedListingPublishesTheSortedRowsOnceAsARefresh() async {
    let reader = reader("b", "a")
    let (model, watcher, answered) = watchingModel(reader: reader)
    await model.load()
    #expect(names(model) == ["a", "b"])
    let publishes = Publishes(of: model)

    reader.changed.update { $0[folder] = .items(items("c", "b", "a")) }
    await watcher.send(to: folder)
    await answered.wait(for: 1)
    #expect(names(model) == ["a", "b", "c"])
    #expect(publishes.all == ["refresh loaded"])
  }

  @Test func aSignalWithTheSameListingPublishesNothing() async {
    let reader = reader("b", "a")
    let (model, watcher, answered) = watchingModel(reader: reader)
    await model.load()
    let publishes = Publishes(of: model)

    await watcher.send(to: folder)
    await answered.wait(for: 1)
    #expect(reader.listings(of: folder) == 2)
    #expect(publishes.all.isEmpty)
    #expect(names(model) == ["a", "b"])
  }

  @Test func aSignalAfterOnlyAHiddenItemChangedPublishesNothing() async {
    let reader = reader("b", "a")
    let (model, watcher, answered) = watchingModel(reader: reader)
    await model.load()
    let publishes = Publishes(of: model)

    reader.changed.update { $0[folder] = .items(items("b", "a", ".hidden")) }
    await watcher.send(to: folder)
    await answered.wait(for: 1)
    #expect(reader.listings(of: folder) == 2)
    #expect(publishes.all.isEmpty)
  }

  @Test func theLiveSignalAloneCausesOneListingAfterTheLoadHasSettled() async {
    let reader = reader("b", "a")
    let (model, watcher, answered) = watchingModel(reader: reader)
    await model.load()
    let publishes = Publishes(of: model)

    await watcher.send(.live, to: folder)
    await answered.wait(for: 1)
    #expect(reader.listings(of: folder) == 2)
    #expect(!model.isAnsweringSignals)
    #expect(publishes.all.isEmpty)
  }

  @Test func aRefreshOfAFolderLargerThanOneBatchKeepsTheRowsUntilTheSortedResultReplacesThem()
    async
  {
    let gate = Gate()
    let reader = reader("c", "a", "b", first: ["c", "a"], gateAfterFirst: gate)
    let (model, watcher, answered) = watchingModel(reader: reader)
    await gate.open()
    await model.load()
    #expect(names(model) == ["a", "b", "c"])
    let publishes = Publishes(of: model)

    // The refresh is held between the reader's two events.
    await gate.close()
    reader.changed.update { $0[folder] = .items(items("c", "a", "b", "d")) }
    await watcher.send(to: folder)
    await gate.waitUntilReached()
    #expect(names(model) == ["a", "b", "c"])
    #expect(model.state == .loaded)
    #expect(publishes.all.isEmpty)

    await gate.open()
    await answered.wait(for: 1)
    #expect(names(model) == ["a", "b", "c", "d"])
    #expect(publishes.all == ["refresh loaded"])
  }

  // MARK: Selection

  @Test func aRefreshKeepsTheSelectionOfItemsThatStillExist() async {
    let reader = reader("a", "b")
    let (model, watcher, answered) = watchingModel(reader: reader)
    await model.load()
    model.selection = Set(model.items.map(\.url))

    reader.changed.update { $0[folder] = .items(items("a", "c")) }
    await watcher.send(to: folder)
    await answered.wait(for: 1)
    #expect(names(model) == ["a", "c"])
    #expect(selectedNames(model) == ["a"])
  }

  @Test func aSelectionMadeWhileARefreshIsHeldIsTheSelectionAfterIt() async {
    let gate = Gate()
    let reader = reader("a", "b", "c", gate: gate)
    let (model, watcher, answered) = watchingModel(reader: reader)
    await gate.open()
    await model.load()
    model.selection = [item("a").url]

    await gate.close()
    reader.changed.update { $0[folder] = .items(items("a", "b")) }
    await watcher.send(to: folder)
    await gate.waitUntilReached()
    model.selection = [item("b").url]

    await gate.open()
    await answered.wait(for: 1)
    #expect(names(model) == ["a", "b"])
    #expect(selectedNames(model) == ["b"])
  }

  // MARK: A signal during a load

  @Test func aSignalWhileALoadIsHeldIsAnsweredByOneRefreshAfterTheLoadSettles() async {
    let gate = Gate()
    let reader = reader("b", "a", gate: gate)
    let (model, watcher, answered) = watchingModel(reader: reader)

    let load = Task { await model.load() }
    await gate.waitUntilReached()
    await watcher.send(to: folder)
    await answered.wait(for: 1)
    // Set aside: the reader has not been asked again.
    #expect(reader.listings(of: folder) == 1)
    #expect(model.state == .loading)

    await gate.open()
    await load.value
    #expect(model.state == .loaded)
    await answered.wait(for: 2)
    #expect(reader.listings(of: folder) == 2)
    #expect(!model.isAnsweringSignals)
  }

  @Test func aSignalWhileFirstRowsAreShowingLeavesThemUntilTheLoadSettlesThenRefreshesOnce() async {
    let gate = Gate()
    let reader = reader("c", "a", "b", first: ["c", "a"], gateAfterFirst: gate)
    let (model, watcher, answered) = watchingModel(reader: reader)
    let publishes = Publishes(of: model)

    let load = Task { await model.load() }
    await gate.waitUntilReached()
    #expect(names(model) == ["c", "a"])
    await watcher.send(to: folder)
    await answered.wait(for: 1)
    #expect(names(model) == ["c", "a"])
    #expect(model.state == .loading)
    #expect(reader.listings(of: folder) == 1)

    await gate.open()
    await load.value
    #expect(names(model) == ["a", "b", "c"])
    await answered.wait(for: 2)
    #expect(reader.listings(of: folder) == 2)
    #expect(!model.isAnsweringSignals)
    // The refresh found nothing new, so only the load published.
    #expect(publishes.all == ["load loading", "load loading", "load loaded"])
  }

  @Test func aLoadThatStartsAfterASignalWasSetAsideIsFollowedByNoRefresh() async {
    let gate = Gate()
    let reader = reader("b", "a", gate: gate)
    let (model, watcher, answered) = watchingModel(reader: reader)

    let first = Task { await model.load() }
    await gate.waitUntilReached()
    await watcher.send(to: folder)
    await answered.wait(for: 1)

    // A second load starts, with no signal during it. Its listing begins
    // after the signal, so it owes nothing.
    await gate.close()
    let second = Task { await model.load() }
    await gate.waitUntilReached()
    await gate.open()
    await first.value
    await second.value
    #expect(model.state == .loaded)
    #expect(!model.isAnsweringSignals)
    #expect(answered.count == 1)
    #expect(reader.listings(of: folder) == 2)
  }

  @Test func aRefreshStartedBetweenAMoveAndItsLoadPublishesNothingAndTheLoadStands() async {
    let gate = Gate()
    let reader = reader("y.txt", "x.txt", gate: gate)
    let (model, watcher, answered) = watchingModel(reader: reader)
    // The folder is left with x selected before it was ever listed, so its
    // gate first holds the return to it.
    model.selection = [item("x.txt").url]
    await model.navigate(to: other)
    let publishes = Publishes(of: model)

    // Back, then a signal before the load has started: a refresh of the
    // folder begins, and is held at the reader.
    #expect(model.moveBack())
    await watcher.send(to: folder)
    await gate.waitUntilReached()
    #expect(model.items.isEmpty)

    // The load starts, which retires the refresh, and reaches the gate too.
    await gate.close()
    let load = Task { await model.load() }
    await gate.waitUntilReached()
    await gate.open()
    await load.value
    await answered.wait(for: 1)
    #expect(names(model) == ["x.txt", "y.txt"])
    #expect(selectedNames(model) == ["x.txt"])
    #expect(publishes.all == ["load loading", "load loaded"])
  }

  // MARK: Signals during a refresh

  @Test func threeSignalsWhileARefreshIsHeldAreAnsweredByExactlyOneMoreListing() async {
    let gate = Gate()
    let reader = reader("b", "a", gate: gate)
    let (model, watcher, answered) = watchingModel(reader: reader)
    await gate.open()
    await model.load()

    await gate.close()
    await watcher.send(to: folder)
    await gate.waitUntilReached()
    #expect(reader.listings(of: folder) == 2)
    for _ in 0..<3 {
      await watcher.send(to: folder)
    }

    // The session goes quiet once, after the held refresh and one more.
    await gate.open()
    await answered.wait(for: 1)
    #expect(!model.isAnsweringSignals)
    #expect(reader.listings(of: folder) == 3)
  }

  // MARK: Ways a refresh is superseded

  @Test func aMoveWhileARefreshIsHeldAtTheReaderPublishesNothingAndMovesTheWatch() async {
    let gate = Gate()
    let reader = reader("b", "a", gate: gate)
    let (model, watcher, answered) = watchingModel(reader: reader)
    await gate.open()
    await model.load()
    let publishes = Publishes(of: model)

    await gate.close()
    reader.changed.update { $0[folder] = .items(items("a", "b", "c")) }
    await watcher.send(to: folder)
    await gate.waitUntilReached()

    #expect(model.move(to: other))
    // The new folder's signals were asked for before the move returned.
    #expect(watcher.requested == [folder, other])
    await watcher.waitForEnd(of: folder)
    #expect(watcher.watched == [other])

    await gate.open()
    await answered.wait(for: 1)
    #expect(publishes.all.isEmpty)
    #expect(model.location == other)
    #expect(model.items.isEmpty)
  }

  @Test func aMoveWhileARefreshIsHeldAtTheSortPublishesNothingAndMovesTheWatch() async {
    let sortGate = Gate()
    let reader = reader("b", "a")
    let (model, watcher, answered) = watchingModel(
      reader: reader, arrange: arrange(holdingCall: 1, at: sortGate))
    await model.load()
    let publishes = Publishes(of: model)

    reader.changed.update { $0[folder] = .items(items("a", "b", "c")) }
    await watcher.send(to: folder)
    await sortGate.waitUntilReached()

    #expect(model.move(to: other))
    #expect(watcher.requested == [folder, other])
    await watcher.waitForEnd(of: folder)

    await sortGate.open()
    await answered.wait(for: 1)
    #expect(publishes.all.isEmpty)
    #expect(model.location == other)
    #expect(model.items.isEmpty)
  }

  @Test func whileTheSortOfARefreshIsHeldTheMainActorIsFreeAndAMoveWins() async {
    let sortGate = Gate()
    let reader = reader("b", "a")
    let (model, watcher, answered) = watchingModel(
      reader: reader, arrange: arrange(holdingCall: 1, at: sortGate))
    await model.load()

    reader.changed.update { $0[folder] = .items(items("a", "b", "c")) }
    await watcher.send(to: folder)
    await sortGate.waitUntilReached()
    // This test runs on the main actor, so the refresh is not holding it.
    #expect(model.state == .loaded)
    #expect(names(model) == ["a", "b"])
    #expect(model.move(to: other))
    await model.load()
    #expect(names(model) == ["elsewhere.txt"])
    let publishes = Publishes(of: model)

    await sortGate.open()
    await answered.wait(for: 1)
    #expect(publishes.all.isEmpty)
    #expect(names(model) == ["elsewhere.txt"])
    #expect(model.state == .loaded)
  }

  @Test func aLoadOfTheSameFolderWhileARefreshIsHeldRetiresTheRefresh() async {
    let gate = Gate()
    let reader = reader("b", "a", gate: gate)
    let (model, watcher, answered) = watchingModel(reader: reader)
    await gate.open()
    await model.load()

    await gate.close()
    await watcher.send(to: folder)
    await gate.waitUntilReached()
    let publishes = Publishes(of: model)

    // The load reaches the gate behind the refresh. What it lists is newer.
    await gate.close()
    let load = Task { await model.load() }
    await gate.waitUntilReached()
    reader.changed.update { $0[folder] = .items(items("a", "b", "c")) }
    await gate.open()
    await load.value
    await answered.wait(for: 1)
    #expect(names(model) == ["a", "b", "c"])
    #expect(publishes.all == ["load loading", "load loaded"])
    #expect(!model.isAnsweringSignals)
    #expect(reader.listings(of: folder) == 3)
  }

  @Test func turningWatchingOffWhileARefreshIsHeldPublishesNothingAndEndsTheWatch() async {
    let gate = Gate()
    let reader = reader("b", "a", gate: gate)
    let (model, watcher, answered) = watchingModel(reader: reader)
    await gate.open()
    await model.load()
    let publishes = Publishes(of: model)

    await gate.close()
    reader.changed.update { $0[folder] = .items(items("a", "b", "c")) }
    await watcher.send(to: folder)
    await gate.waitUntilReached()

    model.stopWatching()
    await watcher.waitForEnd(of: folder)
    #expect(watcher.watched.isEmpty)

    await gate.open()
    await answered.wait(for: 1)
    #expect(publishes.all.isEmpty)
    #expect(names(model) == ["a", "b"])

    // A later signal goes nowhere and starts nothing.
    await watcher.send(to: folder)
    #expect(!model.isAnsweringSignals)
    #expect(reader.listings(of: folder) == 2)
  }

  // MARK: The folder goes away

  @Test func aListingThatFailsOnASignalClearsTheRowsAndReportsWhyOnce() async {
    let reader = reader("b", "a")
    let watcher = StubWatcher()
    let model = BrowserModel(location: other, reader: reader, watcher: watcher)
    let answered = AnsweredSignals(of: model)
    model.startWatching()
    await model.load()
    await model.navigate(to: folder)
    model.selection = [item("a").url]
    let publishes = Publishes(of: model)

    reader.changed.update { $0[folder] = .missing }
    await watcher.send(.folderChanged, to: folder)
    await answered.wait(for: 1)
    let failure = BrowserModel.State.failed(CocoaError(.fileReadNoSuchFile).localizedDescription)
    #expect(model.items.isEmpty)
    #expect(model.selection.isEmpty)
    #expect(model.state == failure)
    // One publish, and never the loading state.
    #expect(publishes.all == ["refresh \(failure)"])

    // The same failure seen again is not news.
    await watcher.send(to: folder)
    await answered.wait(for: 2)
    #expect(publishes.all.count == 1)

    // Back still works from there.
    await model.goBack()
    #expect(model.location == other)
    #expect(model.state == .loaded)
    #expect(names(model) == ["elsewhere.txt"])
  }

  @Test func aFolderThatFailedOnASignalIsListedAgainOnALaterSignal() async {
    let reader = reader("b", "a")
    let (model, watcher, answered) = watchingModel(reader: reader)
    await model.load()

    reader.changed.update { $0[folder] = .missing }
    await watcher.send(.folderChanged, to: folder)
    await answered.wait(for: 1)
    guard case .failed = model.state else {
      Issue.record("Expected a failed state, got \(model.state)")
      return
    }

    reader.changed.update { $0[folder] = .items(items("only")) }
    await watcher.send(.folderChanged, to: folder)
    await answered.wait(for: 2)
    #expect(names(model) == ["only"])
    #expect(model.state == .loaded)
    #expect(model.lastPublish == .refresh)
  }

  @Test func aFolderThatFailedItsFirstLoadIsListedAfterASignalOnceItCanBe() async {
    let reader = StubReader(results: [:])
    let (model, watcher, answered) = watchingModel(reader: reader)
    await model.load()
    guard case .failed = model.state else {
      Issue.record("Expected a failed state, got \(model.state)")
      return
    }
    let publishes = Publishes(of: model)

    // The folder exists now and is empty: the rows are the same, the state is not.
    reader.changed.update { $0[folder] = .items([]) }
    await watcher.send(.folderChanged, to: folder)
    await answered.wait(for: 1)
    #expect(model.items.isEmpty)
    #expect(publishes.all == ["refresh loaded"])
  }

  // MARK: A watch that ends

  @Test func aModelWhoseWatchEndsAtOnceLoadsAndMovesAsBefore() async {
    let watcher = StubWatcher(endsAtOnce: true)
    let model = BrowserModel(location: folder, reader: reader("b", "a"), watcher: watcher)
    model.startWatching()
    await model.load()
    #expect(names(model) == ["a", "b"])

    await model.navigate(to: other)
    #expect(model.state == .loaded)
    #expect(names(model) == ["elsewhere.txt"])
    await model.goBack()
    #expect(names(model) == ["a", "b"])
    #expect(watcher.requested == [folder, other, folder])
    #expect(watcher.watched.isEmpty)
  }

  @Test func droppingTheLastReferenceToAWatchingModelEndsItsWatch() async {
    let watcher = StubWatcher()
    var model: BrowserModel? = BrowserModel(
      location: folder, reader: reader("b", "a"), watcher: watcher)
    model?.startWatching()
    await model?.load()
    #expect(watcher.watched == [folder])

    model = nil
    await watcher.waitForEnd(of: folder)
    #expect(watcher.watched.isEmpty)
  }
}
