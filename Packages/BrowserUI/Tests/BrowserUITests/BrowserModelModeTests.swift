import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// The view mode of a browser (plans/phase-1a-step-06-icon-view.md, U2).
@Suite @MainActor struct BrowserModelModeTests {
  private let root = URL(filePath: "/fixture/root", directoryHint: .isDirectory)
  private var sub: URL { root.appending(path: "Sub", directoryHint: .isDirectory) }
  private var deep: URL { sub.appending(path: "Deep", directoryHint: .isDirectory) }
  private let subKey = FolderKey(names: ["Sub"])
  private let deepKey = FolderKey(names: ["Sub", "Deep"])

  private func file(_ name: String, in folder: URL) -> FileItem {
    FileItem(url: folder.appending(path: name), kind: .file)
  }

  private func folder(_ name: String, in parent: URL) -> FileItem {
    FileItem(url: parent.appending(path: name, directoryHint: .isDirectory), kind: .directory)
  }

  private func loadedModel(gates: [URL: Gate] = [:]) async -> (BrowserModel, StubReader) {
    var reader = StubReader(results: [
      root: [folder("Sub", in: root), file("a.txt", in: root)],
      sub: [folder("Deep", in: sub), file("x.txt", in: sub)],
      deep: [file("z.txt", in: deep)],
    ])
    reader.gates = gates
    let model = BrowserModel(location: root, reader: reader)
    await model.load()
    return (model, reader)
  }

  @Test func theDefaultIsListAndSettingTheSameModeDoesNothing() async {
    let (model, _) = await loadedModel()
    #expect(model.viewMode == .list)
    var changes = 0
    model.onChange = { changes += 1 }

    model.setViewMode(.list)
    #expect(changes == 0)
    model.setViewMode(.icons)
    #expect(changes == 1)
    model.setViewMode(.icons)
    #expect(changes == 1)
  }

  @Test func switchingToIconsClosesEveryOpenFolderInOnePublishAndKeepsTheRest() async throws {
    let (model, reader) = await loadedModel()
    model.openFolder(subKey)
    await model.waitForOpenFolders()
    model.openFolder(deepKey)
    await model.waitForOpenFolders()
    model.selection = [deep.appending(path: "z.txt"), root.appending(path: "a.txt")]
    let location = model.location
    let sort = model.sort
    let listings = reader.listings(of: root)
    var published: [BrowserModel.Publish] = []
    model.onChange = { published.append(model.lastPublish) }

    model.setViewMode(.icons)

    #expect(published == [.mode])
    #expect(model.openFolders.isEmpty)
    // What was selected inside falls back to the folder, as a close does.
    #expect(model.selection == [sub, root.appending(path: "a.txt")])
    #expect(model.location == location)
    #expect(model.sort == sort)
    #expect(!model.canGoBack)
    #expect(reader.listings(of: root) == listings)
  }

  @Test func switchingBackDoesNotReopenAnythingOrListAgain() async {
    let (model, reader) = await loadedModel()
    model.openFolder(subKey)
    await model.waitForOpenFolders()
    model.setViewMode(.icons)
    let listings = reader.listings(of: root) + reader.listings(of: sub)

    model.setViewMode(.list)
    await model.waitForOpenFolders()
    #expect(model.viewMode == .list)
    #expect(model.openFolders.isEmpty)
    #expect(reader.listings(of: root) + reader.listings(of: sub) == listings)
  }

  @Test func theModeIsKeptThroughAMoveAndAReload() async throws {
    let (model, _) = await loadedModel()
    model.setViewMode(.icons)

    #expect(model.move(to: sub))
    await model.load()
    #expect(model.viewMode == .icons)
    #expect(model.moveBack())
    await model.load()
    #expect(model.viewMode == .icons)
    #expect(model.items.map(\.name) == ["a.txt", "Sub"])
  }

  @Test func aModeSetWhileAFolderIsBeingOpenedRetiresItsListing() async throws {
    let gate = Gate()
    let (model, _) = await loadedModel(gates: [sub: gate])
    model.openFolder(subKey)
    await gate.waitUntilReached()

    model.setViewMode(.icons)
    #expect(!model.isOpen(subKey))
    var changes = 0
    model.onChange = { changes += 1 }
    await gate.open()
    await model.waitForOpenFolders()
    #expect(changes == 0)
    #expect(model.children(of: subKey).isEmpty)
  }

  @Test func aModeSetWhileTheTopLevelLoadsDoesNotDisturbTheLoad() async throws {
    let gate = Gate()
    let reader = StubReader(
      results: [root: [file("a.txt", in: root), file("b.txt", in: root)]], gates: [root: gate])
    let model = BrowserModel(location: root, reader: reader)
    let load = Task { await model.load() }
    await gate.waitUntilReached()

    model.setViewMode(.icons)
    await gate.open()
    await load.value
    #expect(model.state == .loaded)
    #expect(model.items.map(\.name) == ["a.txt", "b.txt"])
    #expect(model.viewMode == .icons)
  }

  // MARK: Columns

  private func modelWithTwoLevelsOpen() async -> BrowserModel {
    var reader = StubReader(results: [
      root: [folder("Sub", in: root), folder("Other", in: root), file("a.txt", in: root)],
      sub: [folder("Deep", in: sub), file("x.txt", in: sub)],
      deep: [file("z.txt", in: deep)],
      root.appending(path: "Other", directoryHint: .isDirectory): [file("o.txt", in: root)],
    ])
    reader.gates = [:]
    let model = BrowserModel(location: root, reader: reader)
    await model.load()
    model.openFolder(subKey)
    await model.waitForOpenFolders()
    model.openFolder(deepKey)
    await model.waitForOpenFolders()
    model.openFolder(FolderKey(names: ["Other"]))
    await model.waitForOpenFolders()
    return model
  }

  @Test func columnsKeepTheFoldersThatLeadToTheSelectionAndCloseTheRest() async throws {
    let model = await modelWithTwoLevelsOpen()
    model.selection = [deep.appending(path: "z.txt")]
    var published: [BrowserModel.Publish] = []
    model.onChange = { published.append(model.lastPublish) }

    model.setViewMode(.columns)

    #expect(Set(model.openFolders.keys) == [subKey, deepKey])
    #expect(model.selection == [deep.appending(path: "z.txt")])
    #expect(published == [.mode])
  }

  @Test func aSelectionHigherUpKeepsOnlyTheChainToItsFolder() async throws {
    let model = await modelWithTwoLevelsOpen()
    model.selection = [sub.appending(path: "x.txt")]

    model.setViewMode(.columns)
    // Deep, which is open beyond the selection, goes; Sub stays.
    #expect(Set(model.openFolders.keys) == [subKey])
    #expect(model.selection == [sub.appending(path: "x.txt")])
  }

  @Test func aSelectedFolderThatIsOpenStaysOpenAndOneThatIsNotIsNotOpened() async throws {
    let model = await modelWithTwoLevelsOpen()
    model.selection = [sub]
    model.setViewMode(.columns)
    #expect(Set(model.openFolders.keys) == [subKey])

    let other = await modelWithTwoLevelsOpen()
    other.closeFolder(subKey)
    other.selection = [sub]
    other.setViewMode(.columns)
    #expect(!other.isOpen(subKey))
  }

  @Test func selectionsInDifferentFoldersOrNoSelectionCloseEveryFolder() async throws {
    let mixed = await modelWithTwoLevelsOpen()
    mixed.selection = [sub.appending(path: "x.txt"), root.appending(path: "a.txt")]
    mixed.setViewMode(.columns)
    #expect(mixed.openFolders.isEmpty)
    // What was selected inside Sub falls back to the folder.
    #expect(mixed.selection == [sub, root.appending(path: "a.txt")])

    let none = await modelWithTwoLevelsOpen()
    none.setViewMode(.columns)
    #expect(none.openFolders.isEmpty)
  }

  @Test func leavingColumnsForTheListKeepsFoldersOpenAndForIconsClosesThem() async throws {
    let model = await modelWithTwoLevelsOpen()
    model.selection = [deep.appending(path: "z.txt")]
    model.setViewMode(.columns)
    model.setViewMode(.list)
    #expect(Set(model.openFolders.keys) == [subKey, deepKey])

    model.setViewMode(.columns)
    model.setViewMode(.icons)
    #expect(model.openFolders.isEmpty)
  }
}
