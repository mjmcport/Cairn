import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// What the model does when its location is a tag or the recents.
@Suite @MainActor struct VirtualLocationBrowsingTests {
  private let tag = VirtualLocation.tag("Red").url
  private let recents = VirtualLocation.recents.url
  private let folder = URL(filePath: "/fixture/Docs", directoryHint: .isDirectory)

  private func results() -> [URL: [FileItem]] {
    [
      tag: [
        FileItem(url: URL(filePath: "/fixture/one/report.txt"), kind: .file, size: 5),
        FileItem(url: URL(filePath: "/fixture/two/report.txt"), kind: .file, size: 7),
        FileItem(url: folder, kind: .directory),
      ],
      folder: [FileItem(url: folder.appending(path: "inner.txt"), kind: .file)],
    ]
  }

  @Test func aTagListsThroughTheReaderAndKeepsTwoFilesWithOneName() async {
    let model = BrowserModel(location: tag, reader: StubReader(results: results()))
    await model.load()
    #expect(model.items.count == 3)
    #expect(
      model.items.filter { $0.name == "report.txt" }.map(\.url.path)
        == ["/fixture/one/report.txt", "/fixture/two/report.txt"])
  }

  @Test func selectionIsByURLSoTwoFilesWithOneNameAreTold() async {
    let model = BrowserModel(location: tag, reader: StubReader(results: results()))
    await model.load()
    let second = URL(filePath: "/fixture/two/report.txt")
    model.selection = [second]
    #expect(model.selectedItems.map(\.url) == [second])
  }

  @Test func aVirtualLocationHasNoEnclosingFolder() async {
    let model = BrowserModel(location: tag, reader: StubReader(results: results()))
    await model.load()
    #expect(model.enclosingFolder == nil)
    #expect(!model.moveToEnclosingFolder())
    #expect(model.location == tag)
  }

  @Test func foldersDoNotOpenInPlaceInAVirtualLocation() async {
    let model = BrowserModel(location: tag, reader: StubReader(results: results()))
    await model.load()
    #expect(model.isShowingVirtualLocation)
    #expect(!model.openFolder(FolderKey(names: ["Docs"])))
    #expect(model.openFolders.isEmpty)
  }

  @Test func aVirtualLocationIsNeverWatched() async {
    let watcher = StubWatcher()
    let model = BrowserModel(
      location: recents, reader: StubReader(results: results()), watcher: watcher)
    model.startWatching()
    await model.load()
    #expect(watcher.requested.isEmpty)
  }

  @Test func openingAFolderFromAVirtualLocationEntersItAsAMoveAndBackReturns() async {
    let model = BrowserModel(location: tag, reader: StubReader(results: results()))
    await model.load()
    let item = model.items.first { $0.kind == .directory }!
    #expect(await model.open(item))
    #expect(model.location == folder)
    #expect(model.items.map(\.name) == ["inner.txt"])
    // From the folder, Enclosing Folder is the folder's parent as ever.
    #expect(model.enclosingFolder?.path == "/fixture")

    #expect(model.moveBack())
    await model.load()
    #expect(model.location == tag)
  }

  @Test func aTagAndTheRecentsAreDifferentPlacesEvenWithTheSamePath() {
    let tagNamedRecents = VirtualLocation.tag("Recents").url
    #expect(!BrowserHistory.isSamePlace(tagNamedRecents, recents))
    #expect(BrowserHistory.isSamePlace(recents, VirtualLocation.recents.url))
    // A folder is not the tag with its path.
    #expect(
      !BrowserHistory.isSamePlace(
        URL(filePath: "/Red", directoryHint: .isDirectory), VirtualLocation.tag("Red").url))
  }

  @Test func theTabIsTitledByTheTagOrRecents() {
    #expect(BrowserViewController.title(for: tag) == "Red")
    #expect(BrowserViewController.title(for: recents) == "Recents")
    #expect(
      BrowserViewController.title(for: URL(filePath: "/Users", directoryHint: .isDirectory))
        == "Users")
  }
}
