import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// Folders opened in place: listed, sorted and selected across levels, under
/// the rules of the load counter (plans/phase-1a-step-05-list-view.md, U2).
/// Every wait is on a gate or on the model's own end-of-work, never a clock.
@Suite @MainActor struct BrowserModelTreeTests {
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

  /// A folder `root` holding `Sub` and `Other` and two files, with `x.txt`
  /// in each folder so that names repeat between levels.
  private func listings() -> [URL: [FileItem]] {
    [
      root: [
        folder("Sub", in: root), folder("Other", in: root), file("a.txt", in: root),
        file("x.txt", in: root),
      ],
      sub: [folder("Deep", in: sub), file("x.txt", in: sub), file("b.txt", in: sub)],
      deep: [file("z.txt", in: deep)],
      other: [file("x.txt", in: other), file("o.txt", in: other)],
    ]
  }

  private func names(_ items: [FileItem]) -> [String] { items.map(\.name) }

  private func loadedModel(
    reader: StubReader? = nil, arrange: BrowserModel.Arrange? = nil
  ) async -> (BrowserModel, StubReader) {
    let reader = reader ?? StubReader(results: listings())
    let model: BrowserModel
    if let arrange {
      model = BrowserModel(location: root, reader: reader, arrange: arrange)
    } else {
      model = BrowserModel(location: root, reader: reader)
    }
    await model.load()
    return (model, reader)
  }

  /// A filter-and-sort that holds its call number `index` at `gate`.
  private func arrangeHeld(call index: Int, at gate: Gate) -> BrowserModel.Arrange {
    let calls = Counter()
    return { items, sort, includingHidden in
      if calls.next() == index {
        await gate.pass()
      }
      return sort.sorted(items.visible(includingHidden: includingHidden))
    }
  }

  // MARK: Opening

  @Test func openingAFolderListsItSortsItAndPublishesItsRows() async throws {
    let (model, reader) = await loadedModel()
    var published: [(BrowserModel.Publish, FolderKey?)] = []
    model.onChange = { published.append((model.lastPublish, model.lastChangedFolder)) }
    let topLevel = names(model.items)

    #expect(model.openFolder(subKey))
    #expect(model.isOpen(subKey))
    #expect(model.children(of: subKey).isEmpty)
    await model.waitForOpenFolders()

    #expect(names(model.children(of: subKey)) == ["b.txt", "Deep", "x.txt"])
    #expect(model.state == .loaded)
    #expect(names(model.items) == topLevel)
    #expect(reader.listings(of: sub) == 1)
    // The open, then the rows.
    #expect(published.count == 2)
    #expect(published.allSatisfy { $0.0 == .folder && $0.1 == subKey })
    // Not a move.
    #expect(model.location == root)
    #expect(!model.canGoBack)
  }

  @Test func onlyAFolderThatIsListedCanBeOpened() async throws {
    let (model, _) = await loadedModel()
    #expect(!model.openFolder(FolderKey(names: ["a.txt"])))
    #expect(!model.openFolder(FolderKey(names: ["Missing"])))
    #expect(!model.openFolder(deepKey))
    #expect(!model.openFolder(.root))
    #expect(model.openFolders.isEmpty)
  }

  @Test func aPackageAndASymbolicLinkAreNotOpenedInPlace() async throws {
    var results = listings()
    results[root]?.append(FileItem(url: root.appending(path: "App.app"), kind: .package))
    results[root]?.append(FileItem(url: root.appending(path: "link"), kind: .symbolicLink))
    let (model, _) = await loadedModel(reader: StubReader(results: results))
    #expect(!model.openFolder(FolderKey(names: ["App.app"])))
    #expect(!model.openFolder(FolderKey(names: ["link"])))
  }

  @Test func foldersWithTheSameFileNameKeepTheirListsApart() async throws {
    let (model, _) = await loadedModel()
    model.openFolder(subKey)
    model.openFolder(otherKey)
    await model.waitForOpenFolders()

    #expect(names(model.children(of: subKey)) == ["b.txt", "Deep", "x.txt"])
    #expect(names(model.children(of: otherKey)) == ["o.txt", "x.txt"])
    #expect(
      model.children(of: subKey).first { $0.name == "x.txt" }?.url == sub.appending(path: "x.txt"))
  }

  @Test func openingTwiceListsOnceAndAFolderOpensInsideAFolder() async throws {
    let (model, reader) = await loadedModel()
    #expect(model.openFolder(subKey))
    #expect(!model.openFolder(subKey))
    await model.waitForOpenFolders()
    #expect(reader.listings(of: sub) == 1)

    #expect(model.openFolder(deepKey))
    await model.waitForOpenFolders()
    #expect(names(model.children(of: deepKey)) == ["z.txt"])
  }

  @Test func closingRightAfterOpeningPublishesNothingWhenTheListingArrives() async throws {
    let gate = Gate()
    var reader = StubReader(results: listings())
    reader.gates[sub] = gate
    let (model, _) = await loadedModel(reader: reader)

    model.openFolder(subKey)
    await gate.waitUntilReached()
    #expect(model.closeFolder(subKey))
    var changes = 0
    model.onChange = { changes += 1 }

    await gate.open()
    await model.waitForOpenFolders()
    #expect(changes == 0)
    #expect(!model.isOpen(subKey))
    #expect(model.children(of: subKey).isEmpty)
  }

  @Test func aFolderClosedAndOpenedAgainIsNotFilledByTheListingOfTheFirstOpening() async throws {
    let gate = Gate()
    var reader = StubReader(results: listings())
    reader.gates[sub] = gate
    let (model, _) = await loadedModel(reader: reader)

    model.openFolder(subKey)
    await gate.waitUntilReached()
    model.closeFolder(subKey)
    model.openFolder(subKey)
    var withRows = 0
    model.onChange = { if !model.children(of: subKey).isEmpty { withRows += 1 } }

    // Both listings are held at the gate and both complete. Only the second
    // opening's belongs to the folder as it is now.
    await gate.open()
    await model.waitForOpenFolders()
    #expect(withRows == 1)
    #expect(names(model.children(of: subKey)) == ["b.txt", "Deep", "x.txt"])
  }

  @Test func aFolderThatCannotBeListedStaysOpenWithTheReasonAndIsListedByAReload() async throws {
    var results = listings()
    results[sub] = nil
    let (model, reader) = await loadedModel(reader: StubReader(results: results))

    model.openFolder(subKey)
    await model.waitForOpenFolders()
    #expect(model.isOpen(subKey))
    #expect(model.failure(of: subKey) != nil)
    #expect(model.children(of: subKey).isEmpty)
    // Already open: nothing happens.
    #expect(!model.openFolder(subKey))

    reader.changed.update { $0[sub] = .items([file("late.txt", in: sub)]) }
    await model.load()
    await model.waitForOpenFolders()
    #expect(model.failure(of: subKey) == nil)
    #expect(names(model.children(of: subKey)) == ["late.txt"])
  }

  // MARK: Closing

  @Test func closingAFolderClosesWhatIsOpenInsideItAndDropsTheirSelection() async throws {
    let (model, _) = await loadedModel()
    model.openFolder(subKey)
    await model.waitForOpenFolders()
    model.openFolder(deepKey)
    await model.waitForOpenFolders()
    model.selection = [deep.appending(path: "z.txt"), root.appending(path: "a.txt")]

    #expect(model.closeFolder(subKey))
    #expect(!model.isOpen(subKey))
    #expect(!model.isOpen(deepKey))
    // What was selected inside is gone and the folder is selected in its
    // place. The selection outside is kept.
    #expect(model.selection == [sub, root.appending(path: "a.txt")])
    #expect(!model.closeFolder(subKey))
  }

  @Test func closingAFolderWithNothingSelectedInsideLeavesTheSelectionAlone() async throws {
    let (model, _) = await loadedModel()
    model.openFolder(subKey)
    await model.waitForOpenFolders()
    model.selection = [root.appending(path: "a.txt")]

    model.closeFolder(subKey)
    #expect(model.selection == [root.appending(path: "a.txt")])
  }

  // MARK: Selection across levels

  @Test func aSelectionInOneFolderDoesNotSelectTheSameNameInAnother() async throws {
    let (model, _) = await loadedModel()
    model.openFolder(subKey)
    model.openFolder(otherKey)
    await model.waitForOpenFolders()

    let wanted: Set<URL> = [sub.appending(path: "x.txt")]
    #expect(model.resolveSelection(wanted) == wanted)
    // After a reload every level is listed again, and the selection holds.
    model.selection = wanted
    await model.load()
    await model.waitForOpenFolders()
    #expect(model.selection == wanted)
  }

  @Test func aSelectionInsideAnOpenFolderSurvivesARefreshOfTheTopLevel() async throws {
    let (model, reader) = await loadedModel()
    model.openFolder(subKey)
    await model.waitForOpenFolders()
    model.selection = [sub.appending(path: "b.txt"), root.appending(path: "a.txt")]

    reader.changed.update {
      $0[root] = .items(listings()[root]! + [file("new.txt", in: root)])
    }
    await model.load()
    await model.waitForOpenFolders()
    #expect(model.selection == [sub.appending(path: "b.txt"), root.appending(path: "a.txt")])
    #expect(model.items.count == 5)
  }

  @Test func theLocationsSpellingAndTheListingsSpellingFindTheSameItemAtEveryLevel() async throws {
    // The location is spelled through a link; the listing reports the real path.
    let link = URL(filePath: "/fixture/link", directoryHint: .isDirectory)
    let real = URL(filePath: "/fixture/real", directoryHint: .isDirectory)
    let realSub = real.appending(path: "Sub", directoryHint: .isDirectory)
    let reader = StubReader(results: [
      link: [folder("Sub", in: real), file("x.txt", in: real)],
      realSub: [file("x.txt", in: realSub), file("y.txt", in: realSub)],
    ])
    let model = BrowserModel(location: link, reader: reader)
    await model.load()
    model.openFolder(subKey)
    await model.waitForOpenFolders()
    // Resolved by the listing's path for the open folder: the stub lists
    // `Sub` under the real folder, so its URL is under `real`.
    let nested = realSub.appending(path: "x.txt")
    let topLevel = real.appending(path: "x.txt")

    // The item's own URL.
    #expect(model.resolveSelection([nested]) == [nested])
    // The location's spelling, at the nested level and at the top.
    #expect(model.resolveSelection([link.appending(path: "Sub/x.txt")]) == [nested])
    #expect(model.resolveSelection([link.appending(path: "x.txt")]) == [topLevel])
    // A URL outside both is a top-level item of that name.
    #expect(
      model.resolveSelection([URL(filePath: "/elsewhere/x.txt")]) == [topLevel])
    // A nested path that no longer exists is not mistaken for the top level.
    #expect(model.resolveSelection([link.appending(path: "Gone/x.txt")]).isEmpty)
  }

  // MARK: Sorting every level

  @Test func aChangeOfSortPutsEveryLevelInOrderWithOneBatchOfPublishing() async throws {
    let (model, _) = await loadedModel()
    model.openFolder(subKey)
    await model.waitForOpenFolders()
    model.selection = [sub.appending(path: "b.txt")]
    var published: [BrowserModel.Publish] = []
    model.onChange = { published.append(model.lastPublish) }

    model.changeSort(to: FileItemSort(ascending: false))
    await model.waitForOpenFolders()

    #expect(names(model.items) == ["x.txt", "Sub", "Other", "a.txt"])
    #expect(names(model.children(of: subKey)) == ["x.txt", "Deep", "b.txt"])
    #expect(published == [.resort])
    #expect(model.selection == [sub.appending(path: "b.txt")])
  }

  @Test func foldersFirstGroupsFoldersAtEveryLevelInBothDirections() async throws {
    let (model, _) = await loadedModel()
    model.openFolder(subKey)
    await model.waitForOpenFolders()

    model.changeSort(to: FileItemSort(foldersFirst: true))
    await model.waitForOpenFolders()
    #expect(names(model.items) == ["Other", "Sub", "a.txt", "x.txt"])
    #expect(names(model.children(of: subKey)) == ["Deep", "b.txt", "x.txt"])

    model.changeSort(to: FileItemSort(ascending: false, foldersFirst: true))
    await model.waitForOpenFolders()
    #expect(names(model.items) == ["Sub", "Other", "x.txt", "a.txt"])
    #expect(names(model.children(of: subKey)) == ["Deep", "x.txt", "b.txt"])
  }

  @Test func aMoveWhileTheSortPassIsHeldAtASecondLevelPublishesNothing() async throws {
    let gate = Gate()
    // Calls: top-level load, the folder's listing, then the pass's top
    // level (2) and its folder (3). Hold the folder.
    let (model, _) = await loadedModel(arrange: arrangeHeld(call: 3, at: gate))
    model.openFolder(subKey)
    await model.waitForOpenFolders()

    model.changeSort(to: FileItemSort(ascending: false))
    await gate.waitUntilReached()
    // This test runs on the main actor, so the pass is not holding it.
    #expect(model.move(to: other))
    await model.load()
    var changes = 0
    model.onChange = { changes += 1 }

    await gate.open()
    await model.waitForOpenFolders()
    #expect(changes == 0)
    // The new sort applies to the folder that was moved to.
    #expect(names(model.items) == ["x.txt", "o.txt"])
  }

  // MARK: Under the load counter

  @Test func aMoveWhileAFolderIsHeldAtTheReaderPublishesNothingAndClosesIt() async throws {
    let gate = Gate()
    var reader = StubReader(results: listings())
    reader.gates[sub] = gate
    let (model, _) = await loadedModel(reader: reader)

    model.openFolder(subKey)
    await gate.waitUntilReached()
    #expect(model.move(to: other))
    #expect(!model.isOpen(subKey))
    await model.load()
    var changes = 0
    model.onChange = { changes += 1 }

    await gate.open()
    await model.waitForOpenFolders()
    #expect(changes == 0)
    #expect(!model.isOpen(subKey))
    #expect(names(model.items) == ["o.txt", "x.txt"])
  }

  @Test func aMoveWhileAFolderIsHeldAtTheSortPublishesNothing() async throws {
    let gate = Gate()
    // Call 0 is the top level, call 1 the folder.
    let (model, _) = await loadedModel(arrange: arrangeHeld(call: 1, at: gate))

    model.openFolder(subKey)
    await gate.waitUntilReached()
    // The main actor is free while the sort is held: read and move.
    #expect(model.children(of: subKey).isEmpty)
    #expect(model.move(to: other))
    await model.load()
    var changes = 0
    model.onChange = { changes += 1 }

    await gate.open()
    await model.waitForOpenFolders()
    #expect(changes == 0)
    #expect(!model.isOpen(subKey))
  }

  @Test func aReloadWhileAFolderIsHeldRetiresItAndListsItAgainOnceAfterTheTopLevelSettles()
    async throws
  {
    let gate = Gate()
    var reader = StubReader(results: listings())
    reader.gates[sub] = gate
    let (model, _) = await loadedModel(reader: reader)

    model.openFolder(subKey)
    await gate.waitUntilReached()
    var withRows = 0
    model.onChange = { if !model.children(of: subKey).isEmpty { withRows += 1 } }
    // The reload retires the held listing. Its own relisting of the folder
    // is held at the same gate once the top level has settled.
    await model.load()
    await gate.open()
    await model.waitForOpenFolders()

    #expect(model.isOpen(subKey))
    #expect(names(model.children(of: subKey)) == ["b.txt", "Deep", "x.txt"])
    #expect(model.state == .loaded)
    // The retired listing published nothing; the relisting published once.
    #expect(withRows == 1)
  }

  @Test func aReloadKeepsAnOpenFoldersRowsUntilTheNewOnesReplaceThem() async throws {
    let gate = Gate()
    var reader = StubReader(results: listings())
    reader.gates[sub] = gate
    let (model, _) = await loadedModel(reader: reader)
    await gate.open()
    model.openFolder(subKey)
    await model.waitForOpenFolders()
    #expect(names(model.children(of: subKey)) == ["b.txt", "Deep", "x.txt"])

    // The relisting of the folder is held; the old rows stay.
    await gate.close()
    await model.load()
    await gate.waitUntilReached()
    #expect(model.state == .loaded)
    #expect(names(model.children(of: subKey)) == ["b.txt", "Deep", "x.txt"])
    #expect(model.isOpen(subKey))

    await gate.open()
    await model.waitForOpenFolders()
    #expect(names(model.children(of: subKey)) == ["b.txt", "Deep", "x.txt"])
  }

  @Test func aFolderThatIsGoneAfterAReloadIsClosedWithWhatWasOpenInsideIt() async throws {
    let (model, reader) = await loadedModel()
    model.openFolder(subKey)
    await model.waitForOpenFolders()
    model.openFolder(deepKey)
    await model.waitForOpenFolders()
    model.selection = [deep.appending(path: "z.txt")]

    reader.changed.update {
      $0[root] = .items([folder("Other", in: root), file("a.txt", in: root)])
    }
    await model.load()
    await model.waitForOpenFolders()

    #expect(!model.isOpen(subKey))
    #expect(!model.isOpen(deepKey))
    #expect(model.selection.isEmpty)
  }

  @Test func aTopLevelThatFailsToReloadClosesEveryFolder() async throws {
    let (model, reader) = await loadedModel()
    model.openFolder(subKey)
    await model.waitForOpenFolders()

    reader.changed.update { $0[root] = .missing }
    await model.load()
    #expect(model.openFolders.isEmpty)
    #expect(model.items.isEmpty)
    if case .failed = model.state {
    } else {
      Issue.record("The top level should have failed")
    }
  }

  @Test func hiddenItemsAreFilteredAtEveryLevelUntilTheNextLoadShowsThem() async throws {
    var results = listings()
    results[sub]?.append(FileItem(url: sub.appending(path: ".secret"), kind: .file, isHidden: true))
    let (model, _) = await loadedModel(reader: StubReader(results: results))
    model.openFolder(subKey)
    await model.waitForOpenFolders()
    #expect(!names(model.children(of: subKey)).contains(".secret"))

    // The flag takes effect at the next load, as it does for the top level;
    // the folder stays open and is listed again with it.
    model.showsHiddenFiles = true
    await model.load()
    await model.waitForOpenFolders()
    #expect(model.isOpen(subKey))
    #expect(names(model.children(of: subKey)).contains(".secret"))
  }

  @Test func openingFoldersIsNotAMoveAndTheHistoryIsUntouched() async throws {
    let (model, _) = await loadedModel()
    model.openFolder(subKey)
    await model.waitForOpenFolders()
    model.openFolder(deepKey)
    await model.waitForOpenFolders()

    #expect(model.location == root)
    #expect(!model.canGoBack)
    #expect(!model.canGoForward)
  }
}
