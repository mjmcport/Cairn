import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// Back and Forward open again the folders that were open in the place
/// returned to (plans/phase-1a-step-05-list-view.md, U4). Every wait is on a
/// gate or on the model's own end-of-work, never a clock.
@Suite @MainActor struct BrowserModelRestoreTests {
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

  /// `root` holds `Sub` (with `Deep` inside) and `Other`. Moving to `Other`
  /// is the move away from `root`, so `Other` is not shown in `root`'s own
  /// rows twice: it is a folder of `root` as well as a place to go.
  private func listings() -> [URL: [FileItem]] {
    [
      root: [folder("Sub", in: root), folder("Other", in: root), file("a.txt", in: root)],
      sub: [folder("Deep", in: sub), file("x.txt", in: sub), file("b.txt", in: sub)],
      deep: [file("z.txt", in: deep)],
      other: [file("o.txt", in: other), folder("Inner", in: other)],
      other.appending(path: "Inner", directoryHint: .isDirectory): [],
    ]
  }

  private func names(_ items: [FileItem]) -> [String] { items.map(\.name) }

  private struct Suite {
    let defaults: UserDefaults
    let name: String
    var settings: BrowserSettings { BrowserSettings(defaults: defaults) }
    func cleanup() { defaults.removePersistentDomain(forName: name) }
  }

  private func suite(remembering: Bool = true) throws -> Suite {
    let name = "BrowserModelRestoreTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.set(remembering, forKey: BrowserSettings.rememberOpenFoldersKey)
    return Suite(defaults: defaults, name: name)
  }

  private struct Rig {
    let model: BrowserModel
    let reader: StubReader
    let suite: Suite
  }

  /// A model on `root` with `Sub` and `Deep` open, listed and settled.
  private func modelWithFoldersOpen(
    remembering: Bool = true, reader: StubReader? = nil
  ) async throws -> Rig {
    let suite = try suite(remembering: remembering)
    let reader = reader ?? StubReader(results: listings())
    let model = BrowserModel(location: root, reader: reader, settings: suite.settings)
    await model.load()
    model.openFolder(subKey)
    await model.waitForOpenFolders()
    model.openFolder(deepKey)
    await model.waitForOpenFolders()
    return Rig(model: model, reader: reader, suite: suite)
  }

  /// Leaves `root` for `Other` and settles there.
  private func leave(_ model: BrowserModel) async {
    #expect(model.move(to: other))
    await model.load()
  }

  // MARK: What an entry keeps

  @Test func aMoveRemembersTheFoldersOpenInTheFolderLeftAndNothingOpenedLater() async throws {
    let rig = try await modelWithFoldersOpen()
    defer { rig.suite.cleanup() }

    await leave(rig.model)
    #expect(rig.model.history.backEntries.last?.openFolders == [subKey, deepKey])

    // Opening in the new folder changes no entry but its own, later.
    rig.model.openFolder(FolderKey(names: ["Inner"]))
    await rig.model.waitForOpenFolders()
    #expect(rig.model.history.backEntries.last?.openFolders == [subKey, deepKey])
  }

  @Test func anEntryMadeWithTheSettingOffStillHoldsTheFolders() async throws {
    let rig = try await modelWithFoldersOpen(remembering: false)
    defer { rig.suite.cleanup() }

    await leave(rig.model)
    #expect(rig.model.history.backEntries.last?.openFolders == [subKey, deepKey])

    // Turned on afterwards, going back restores what was open.
    rig.suite.settings.rememberOpenFolders = true
    #expect(rig.model.moveBack())
    await rig.model.load()
    await rig.model.waitForOpenFolders()
    #expect(rig.model.isOpen(subKey))
    #expect(rig.model.isOpen(deepKey))
  }

  // MARK: Going back and forward

  @Test func backOpensTheRememberedFoldersAgainShallowestFirstOnceTheTopLevelHasSettled()
    async throws
  {
    let rig = try await modelWithFoldersOpen()
    defer { rig.suite.cleanup() }
    await leave(rig.model)

    var folderPublishes: [FolderKey?] = []
    var states: [BrowserModel.State] = []
    rig.model.onChange = {
      states.append(rig.model.state)
      if rig.model.lastPublish == .folder,
        !rig.model.children(of: rig.model.lastChangedFolder!).isEmpty
      {
        folderPublishes.append(rig.model.lastChangedFolder)
      }
    }
    #expect(rig.model.moveBack())
    // Closed until the listing arrives.
    #expect(rig.model.openFolders.isEmpty)
    await rig.model.load()
    #expect(names(rig.model.items) == ["a.txt", "Other", "Sub"])
    await rig.model.waitForOpenFolders()

    #expect(rig.model.isOpen(subKey) && rig.model.isOpen(deepKey))
    #expect(names(rig.model.children(of: subKey)) == ["b.txt", "Deep", "x.txt"])
    #expect(names(rig.model.children(of: deepKey)) == ["z.txt"])
    // Each folder's rows arrive once, the shallower first.
    #expect(folderPublishes == [subKey, deepKey])
    // The loading state was the load's alone.
    #expect(states.last == .loaded)
    #expect(states.drop { $0 == .loading }.allSatisfy { $0 == .loaded })
  }

  @Test func forwardRestoresTheSameWay() async throws {
    let rig = try await modelWithFoldersOpen()
    defer { rig.suite.cleanup() }
    await leave(rig.model)
    #expect(rig.model.moveBack())
    await rig.model.load()
    await rig.model.waitForOpenFolders()
    rig.model.openFolder(otherKey)
    await rig.model.waitForOpenFolders()

    // Forward to `Other` and back again: root's folders are restored once more,
    // and Other is what was open there when it was left.
    #expect(rig.model.moveForward())
    await rig.model.load()
    await rig.model.waitForOpenFolders()
    #expect(rig.model.openFolders.isEmpty)
    #expect(rig.model.moveBack())
    await rig.model.load()
    await rig.model.waitForOpenFolders()
    #expect(Set(rig.model.openFolders.keys) == [subKey, deepKey, otherKey])
  }

  @Test func withTheSettingOffBackLeavesTheOutlineClosedAndKeepsTheTopLevelSelection()
    async throws
  {
    let rig = try await modelWithFoldersOpen()
    defer { rig.suite.cleanup() }
    rig.model.selection = [root.appending(path: "a.txt")]
    await leave(rig.model)

    rig.suite.settings.rememberOpenFolders = false
    #expect(rig.model.moveBack())
    await rig.model.load()
    await rig.model.waitForOpenFolders()
    #expect(rig.model.openFolders.isEmpty)
    #expect(rig.model.selection == [root.appending(path: "a.txt")])
  }

  @Test func theSettingIsReadWhenTheMoveIsMadeNotWhenTheListingArrives() async throws {
    let rig = try await modelWithFoldersOpen()
    defer { rig.suite.cleanup() }
    await leave(rig.model)

    #expect(rig.model.moveBack())
    rig.suite.settings.rememberOpenFolders = false
    await rig.model.load()
    await rig.model.waitForOpenFolders()
    #expect(rig.model.isOpen(subKey))
  }

  @Test func openAndEnclosingFolderStartClosedWhateverTheSettingSays() async throws {
    let rig = try await modelWithFoldersOpen()
    defer { rig.suite.cleanup() }

    // Into Sub: a move. Then out again by Enclosing Folder: not Back.
    #expect(rig.model.move(to: sub))
    await rig.model.load()
    #expect(rig.model.openFolders.isEmpty)
    #expect(rig.model.moveToEnclosingFolder())
    await rig.model.load()
    await rig.model.waitForOpenFolders()
    #expect(rig.model.openFolders.isEmpty)
    #expect(rig.model.history.backEntries.last?.openFolders.isEmpty == true)
  }

  // MARK: Selection

  @Test func selectedItemsInsideTheFoldersComeBackAsTheirRowsAppear() async throws {
    let rig = try await modelWithFoldersOpen()
    defer { rig.suite.cleanup() }
    let wanted: Set<URL> = [
      root.appending(path: "a.txt"), sub.appending(path: "x.txt"), deep.appending(path: "z.txt"),
    ]
    rig.model.selection = wanted
    await leave(rig.model)

    // The selection must never name an item whose folder has no rows yet.
    var namedAnItemBeforeItsRows = false
    let nested = sub.appending(path: "x.txt")
    rig.model.onChange = {
      if rig.model.selection.contains(nested), rig.model.children(of: self.subKey).isEmpty {
        namedAnItemBeforeItsRows = true
      }
    }
    #expect(rig.model.moveBack())
    await rig.model.load()
    // The top-level part is back as soon as the list settles.
    #expect(rig.model.selection == [root.appending(path: "a.txt")])
    await rig.model.waitForOpenFolders()
    #expect(rig.model.selection == wanted)
    #expect(!namedAnItemBeforeItsRows)
  }

  @Test func aSelectionTheUserMakesWhileTheFoldersOpenIsTheOneKept() async throws {
    let gate = Gate()
    var reader = StubReader(results: listings())
    reader.gates[sub] = gate
    await gate.open()
    let rig = try await modelWithFoldersOpen(reader: reader)
    defer { rig.suite.cleanup() }
    rig.model.selection = [sub.appending(path: "x.txt")]
    await leave(rig.model)

    await gate.close()
    #expect(rig.model.moveBack())
    await rig.model.load()
    await gate.waitUntilReached()
    // The user selects while Sub is being opened again.
    rig.model.selection = [root.appending(path: "a.txt")]

    await gate.open()
    await rig.model.waitForOpenFolders()
    #expect(rig.model.isOpen(subKey))
    #expect(rig.model.selection == [root.appending(path: "a.txt")])
  }

  // MARK: Folders that are gone or cannot be listed

  @Test func aRememberedFolderThatIsGoneIsSkippedWithoutAMessage() async throws {
    let rig = try await modelWithFoldersOpen()
    defer { rig.suite.cleanup() }
    await leave(rig.model)

    rig.reader.changed.update {
      $0[root] = .items([self.folder("Other", in: self.root), self.file("a.txt", in: self.root)])
    }
    #expect(rig.model.moveBack())
    await rig.model.load()
    await rig.model.waitForOpenFolders()

    #expect(rig.model.openFolders.isEmpty)
    #expect(rig.model.state == .loaded)
    #expect(names(rig.model.items) == ["a.txt", "Other"])
  }

  @Test func aFolderThatCannotBeListedShowsWhyAndTheRestOfTheRestoreGoesOn() async throws {
    let suite = try suite()
    defer { suite.cleanup() }
    let reader = StubReader(results: listings())
    let model = BrowserModel(location: root, reader: reader, settings: suite.settings)
    await model.load()
    model.openFolder(subKey)
    model.openFolder(otherKey)
    await model.waitForOpenFolders()
    #expect(model.move(to: other))
    await model.load()

    reader.changed.update { $0[sub] = .missing }
    #expect(model.moveBack())
    await model.load()
    await model.waitForOpenFolders()

    #expect(model.failure(of: subKey) != nil)
    #expect(model.isOpen(otherKey))
    #expect(names(model.children(of: otherKey)) == ["Inner", "o.txt"])
  }

  // MARK: Under the load counter

  @Test func aMoveWhileTheFirstFolderIsBeingOpenedPublishesNothingIntoTheNewFolder() async throws {
    let gate = Gate()
    var reader = StubReader(results: listings())
    reader.gates[sub] = gate
    await gate.open()
    let rig = try await modelWithFoldersOpen(reader: reader)
    defer { rig.suite.cleanup() }
    await leave(rig.model)

    await gate.close()
    #expect(rig.model.moveBack())
    await rig.model.load()
    await gate.waitUntilReached()
    #expect(rig.model.move(to: other))
    await rig.model.load()
    var changes = 0
    rig.model.onChange = { changes += 1 }

    await gate.open()
    await rig.model.waitForOpenFolders()
    #expect(changes == 0)
    #expect(rig.model.openFolders.isEmpty)
    #expect(names(rig.model.items) == ["Inner", "o.txt"])
  }

  @Test func twoBackCommandsWithNoAwaitBetweenEndOnTheRightFolderWithItsOwnRestore()
    async throws
  {
    let rig = try await modelWithFoldersOpen()
    defer { rig.suite.cleanup() }
    // root (Sub, Deep open) -> Other -> Inner
    await leave(rig.model)
    #expect(rig.model.move(to: other.appending(path: "Inner", directoryHint: .isDirectory)))
    await rig.model.load()

    #expect(rig.model.moveBack())
    #expect(rig.model.moveBack())
    await rig.model.load()
    await rig.model.waitForOpenFolders()

    #expect(rig.model.location == root)
    #expect(rig.model.isOpen(subKey) && rig.model.isOpen(deepKey))
  }

  @Test func aLoadOfTheSameFolderWhileTheRestoreIsHeldRetiresItAndItsRowsStand() async throws {
    let gate = Gate()
    var reader = StubReader(results: listings())
    reader.gates[sub] = gate
    await gate.open()
    let rig = try await modelWithFoldersOpen(reader: reader)
    defer { rig.suite.cleanup() }
    await leave(rig.model)

    await gate.close()
    #expect(rig.model.moveBack())
    await rig.model.load()
    await gate.waitUntilReached()
    // Reloaded while Sub is still being opened again.
    let reload = Task { await rig.model.load() }
    await gate.open()
    await reload.value
    await rig.model.waitForOpenFolders()

    #expect(rig.model.state == .loaded)
    #expect(names(rig.model.items) == ["a.txt", "Other", "Sub"])
    // The reload kept what was open and listed it again. Deep, which the
    // retired restore had yet to reach, was not opened by anything.
    #expect(rig.model.isOpen(subKey))
    #expect(names(rig.model.children(of: subKey)) == ["b.txt", "Deep", "x.txt"])
    #expect(!rig.model.isOpen(deepKey))
  }

  @Test func closingAParentWhileTheRestoreIsUnderWayOpensNothingBeneathIt() async throws {
    let gate = Gate()
    var reader = StubReader(results: listings())
    reader.gates[sub] = gate
    await gate.open()
    let rig = try await modelWithFoldersOpen(reader: reader)
    defer { rig.suite.cleanup() }
    await leave(rig.model)

    await gate.close()
    #expect(rig.model.moveBack())
    await rig.model.load()
    await gate.waitUntilReached()
    #expect(rig.model.closeFolder(subKey))

    await gate.open()
    await rig.model.waitForOpenFolders()
    #expect(!rig.model.isOpen(subKey))
    #expect(!rig.model.isOpen(deepKey))
  }

  @Test func aFolderTheUserOpenedFirstIsNotListedTwiceByTheRestore() async throws {
    let gate = Gate()
    var reader = StubReader(results: listings())
    // Folders are opened again by depth and then by name, so Other comes
    // before Sub: hold Other, and let the user open Sub in the meantime.
    reader.gates[other] = gate
    let suite = try suite()
    defer { suite.cleanup() }
    await gate.open()
    let model = BrowserModel(location: root, reader: reader, settings: suite.settings)
    await model.load()
    model.openFolder(subKey)
    model.openFolder(otherKey)
    await model.waitForOpenFolders()
    #expect(model.move(to: other))
    await model.load()
    let before = reader.listings(of: sub)

    await gate.close()
    #expect(model.moveBack())
    await model.load()
    await gate.waitUntilReached()
    #expect(model.openFolder(subKey))

    await gate.open()
    await model.waitForOpenFolders()
    #expect(model.isOpen(subKey) && model.isOpen(otherKey))
    // Listed by the user's opening, and not again by the restore.
    #expect(reader.listings(of: sub) == before + 1)
  }

  @Test func aRestoreRetiredByAMoveDoesNotOpenAFolderOfTheSameNameInTheNewPlace() async throws {
    let gate = Gate()
    let third = URL(filePath: "/fixture/third", directoryHint: .isDirectory)
    let thirdSub = third.appending(path: "Sub", directoryHint: .isDirectory)
    var results = listings()
    // A place with a folder whose key is the same as one to be restored.
    results[third] = [folder("Sub", in: third)]
    results[thirdSub] = [file("t.txt", in: thirdSub)]
    var reader = StubReader(results: results)
    // Folders are opened again by depth and then by name: Other first.
    reader.gates[other] = gate
    let suite = try suite()
    defer { suite.cleanup() }
    await gate.open()
    let model = BrowserModel(location: root, reader: reader, settings: suite.settings)
    await model.load()
    model.openFolder(subKey)
    model.openFolder(otherKey)
    await model.waitForOpenFolders()
    #expect(model.move(to: third))
    await model.load()

    await gate.close()
    #expect(model.moveBack())
    await model.load()
    await gate.waitUntilReached()
    // Held opening Other again. Away to a place that has a folder called Sub.
    #expect(model.move(to: third))
    await model.load()
    var changes = 0
    model.onChange = { changes += 1 }

    await gate.open()
    await model.waitForOpenFolders()
    #expect(changes == 0)
    #expect(model.openFolders.isEmpty)
    #expect(model.children(of: subKey).isEmpty)
  }

  @Test func leavingBeforeTheRestoreFinishesKeepsTheFoldersStillToOpen() async throws {
    let rig = try await modelWithFoldersOpen()
    defer { rig.suite.cleanup() }
    await leave(rig.model)

    // Back, and away again before the listing has even been asked for.
    #expect(rig.model.moveBack())
    #expect(rig.model.move(to: other))
    #expect(rig.model.history.backEntries.last?.openFolders == [subKey, deepKey])
  }
}
