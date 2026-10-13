import AppKit
import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// The icon presentation (plans/phase-1a-step-06-icon-view.md, U4 and U5): a
/// real `NSCollectionView` in a real window, a stub reader, a stub watcher and
/// a stub thumbnail provider. Nothing waits on a clock.
@Suite @MainActor struct IconViewTests {
  private let root = URL(filePath: "/fixture/root", directoryHint: .isDirectory)
  private var sub: URL { root.appending(path: "Sub", directoryHint: .isDirectory) }

  private func file(_ name: String, onlineOnly: Bool = false, size: Int64 = 10) -> FileItem {
    FileItem(
      url: root.appending(path: name), kind: .file, size: size, isOnlineOnly: onlineOnly)
  }

  private func listing() -> [URL: [FileItem]] {
    [
      root: [
        file("alpha.txt"), file("beta.txt"), file("cloud.png", onlineOnly: true),
        FileItem(url: sub, kind: .directory),
        FileItem(url: root.appending(path: ".hidden"), kind: .file, isHidden: true),
      ],
      sub: [FileItem(url: sub.appending(path: "inner.txt"), kind: .file)],
    ]
  }

  @MainActor private struct Rig {
    let controller: BrowserViewController
    let window: NSWindow
    let icons: IconCollectionView
    let reader: StubReader
    let watcher: StubWatcher
    let answered: AnsweredSignals
    let provider: StubThumbnailer

    var model: BrowserModel { controller.model }

    func cell(_ index: Int) -> IconItem? {
      icons.item(at: IndexPath(item: index, section: 0)) as? IconItem
    }
  }

  private func rig(results: [URL: [FileItem]]? = nil) async throws -> Rig {
    let reader = StubReader(results: results ?? listing())
    let watcher = StubWatcher()
    let provider = StubThumbnailer()
    let controller = BrowserViewController(location: root, reader: reader, watcher: watcher)
    controller.thumbnailLoader = ThumbnailLoader(provider: provider)
    let answered = AnsweredSignals(of: controller.model)
    let window = NSWindow(contentViewController: controller)
    window.setContentSize(NSSize(width: 700, height: 500))
    window.layoutIfNeeded()
    let icons = try #require(Self.firstSubview(of: IconCollectionView.self, in: controller.view))
    await controller.loadTask?.value
    controller.startWatching()
    return Rig(
      controller: controller, window: window, icons: icons, reader: reader, watcher: watcher,
      answered: answered, provider: provider)
  }

  private static func firstSubview<View: NSView>(of type: View.Type, in view: NSView) -> View? {
    if let match = view as? View { return match }
    for subview in view.subviews {
      if let match = firstSubview(of: type, in: subview) { return match }
    }
    if let scrollView = view as? NSScrollView, let document = scrollView.documentView {
      return firstSubview(of: type, in: document)
    }
    return nil
  }

  /// Lets the main actor run until `condition` holds, giving up after a fixed
  /// number of turns: no clock is involved.
  private func settle(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<5_000 {
      if condition() { return true }
      await Task.yield()
    }
    return condition()
  }

  private func showIcons(_ rig: Rig) {
    rig.controller.showAsIcons(nil)
    rig.window.layoutIfNeeded()
    rig.icons.layoutSubtreeIfNeeded()
  }

  // MARK: The mode

  @Test func theListIsShownFirstAndTheCommandsSwitch() async throws {
    let rig = try await rig()
    let scroll = try #require(rig.icons.enclosingScrollView)
    #expect(scroll.isHidden)
    #expect(rig.model.viewMode == .list)

    showIcons(rig)
    #expect(!scroll.isHidden)
    #expect(rig.model.viewMode == .icons)

    rig.controller.showAsList(nil)
    #expect(scroll.isHidden)
    #expect(rig.model.viewMode == .list)
  }

  @Test func theCommandsAreCheckedForTheCurrentMode() async throws {
    let rig = try await rig()
    let list = NSMenuItem(
      title: "as List", action: #selector(BrowserViewController.showAsList(_:)), keyEquivalent: "")
    let icons = NSMenuItem(
      title: "as Icons", action: #selector(BrowserViewController.showAsIcons(_:)),
      keyEquivalent: "")

    #expect(rig.controller.validateUserInterfaceItem(list))
    #expect(rig.controller.validateUserInterfaceItem(icons))
    #expect(list.state == .on && icons.state == .off)

    showIcons(rig)
    #expect(rig.controller.validateUserInterfaceItem(list))
    #expect(rig.controller.validateUserInterfaceItem(icons))
    #expect(list.state == .off && icons.state == .on)
  }

  @Test func theCollectionViewIsIdentifiedAndLabelled() async throws {
    let rig = try await rig()
    #expect(rig.icons.accessibilityIdentifier() == "icon-view")
    #expect(rig.icons.accessibilityLabel() == "Files")
  }

  // MARK: Cells and pictures

  @Test func thereIsOneCellPerVisibleItemEachWithAGenericPictureAtOnce() async throws {
    let rig = try await rig()
    showIcons(rig)

    #expect(rig.icons.numberOfItems(inSection: 0) == 4)
    for index in 0..<4 {
      let cell = try #require(rig.cell(index))
      #expect(cell.showsGenericIcon)
    }
  }

  @Test func aCellSpeaksItsNameItsKindAndWhetherItIsOnlineOnly() async throws {
    let rig = try await rig()
    showIcons(rig)
    let spoken = (0..<4).compactMap { rig.cell($0)?.view.accessibilityLabel() }

    #expect(
      spoken == [
        "alpha.txt, file", "beta.txt, file", "cloud.png, file, online only", "Sub, folder",
      ])
  }

  @Test func aPictureThatArrivesReplacesTheGenericOneOfThatCell() async throws {
    let rig = try await rig()
    showIcons(rig)
    let first = try #require(rig.cell(0))

    let arrived = await settle { !first.showsGenericIcon }
    #expect(arrived)
    #expect(rig.provider.requests.map(\.lastPathComponent).contains("alpha.txt"))
  }

  @Test func nothingIsAskedOfTheProviderForAnOnlineOnlyItem() async throws {
    let rig = try await rig()
    showIcons(rig)
    // Everything that is going to be asked for has been.
    _ = await settle {
      rig.cell(0)?.showsGenericIcon == false && rig.cell(1)?.showsGenericIcon == false
    }

    #expect(!rig.provider.requests.map(\.lastPathComponent).contains("cloud.png"))
    #expect(rig.cell(2)?.showsGenericIcon == true)
  }

  // MARK: Selection and opening

  @Test func theModelsSelectionIsShownAndAClickWritesBackOnce() async throws {
    let rig = try await rig()
    rig.model.selection = [root.appending(path: "beta.txt")]
    showIcons(rig)
    #expect(rig.icons.selectionIndexPaths == [IndexPath(item: 1, section: 0)])

    var changes = 0
    rig.model.onChange = { changes += 1 }
    rig.icons.selectionIndexPaths = [
      IndexPath(item: 0, section: 0), IndexPath(item: 3, section: 0),
    ]
    rig.controller.collectionView(
      rig.icons, didSelectItemsAt: [IndexPath(item: 0, section: 0), IndexPath(item: 3, section: 0)])

    #expect(rig.model.selection == [root.appending(path: "alpha.txt"), sub])
    // The model's selection is plain state: no publish, nothing looped back.
    #expect(changes == 0)
  }

  @Test func aRefreshThatAddsAnItemAboveTheSelectedOneKeepsTheSameItemSelected() async throws {
    let rig = try await rig()
    rig.model.selection = [root.appending(path: "beta.txt")]
    showIcons(rig)
    try #require(rig.icons.selectionIndexPaths == [IndexPath(item: 1, section: 0)])

    var results = listing()
    results[root]?.append(file("0-new.txt"))
    rig.reader.changed.update { $0[root] = .items(results[root]!) }
    await rig.watcher.send(to: root)
    await rig.answered.wait(for: 1)

    // beta.txt moved down one place and is still the selected item.
    #expect(rig.icons.selectionIndexPaths == [IndexPath(item: 2, section: 0)])
    #expect(rig.model.selection == [root.appending(path: "beta.txt")])
  }

  @Test func openOnAFolderCellEntersItAsAMoveAndOnAFileDoesNothing() async throws {
    let rig = try await rig()
    showIcons(rig)

    rig.model.selection = [root.appending(path: "alpha.txt")]
    rig.controller.openSelection(nil)
    #expect(rig.model.location == root)

    rig.model.selection = [sub]
    rig.controller.openSelection(nil)
    await rig.controller.loadTask?.value
    #expect(rig.model.location.lastPathComponent == "Sub")
    #expect(rig.model.canGoBack)
    #expect(rig.model.viewMode == .icons)
    #expect(rig.icons.numberOfItems(inSection: 0) == 1)
  }

  @Test func typingSelectsTheFirstNameThatStartsWithIt() async throws {
    let rig = try await rig()
    showIcons(rig)

    rig.icons.onType?("b", 100.0)
    rig.icons.onType?("e", 100.3)
    #expect(rig.model.selection == [root.appending(path: "beta.txt")])
    #expect(rig.icons.selectionIndexPaths == [IndexPath(item: 1, section: 0)])

    // After a pause the next letter starts again.
    rig.icons.onType?("s", 105.0)
    #expect(rig.model.selection == [sub])
  }

  // MARK: Switching keeps what is the browser's

  @Test func aRoundTripKeepsTheSelectionTheSortAndTheLocation() async throws {
    let rig = try await rig()
    rig.model.selection = [root.appending(path: "beta.txt")]
    rig.model.changeSort(to: FileItemSort(ascending: false))
    await rig.model.waitForOpenFolders()

    showIcons(rig)
    #expect(rig.cell(0)?.item?.name == "Sub")
    rig.controller.showAsList(nil)

    #expect(rig.model.selection == [root.appending(path: "beta.txt")])
    #expect(!rig.model.sort.ascending)
    #expect(rig.model.location == root)
    #expect(!rig.model.canGoBack)
  }

  @Test func switchingToIconsClosesTheFoldersOpenInTheListAndSelectsTheFolder() async throws {
    let rig = try await rig()
    rig.model.openFolder(FolderKey(names: ["Sub"]))
    await rig.model.waitForOpenFolders()
    rig.model.selection = [sub.appending(path: "inner.txt")]

    showIcons(rig)
    #expect(rig.model.openFolders.isEmpty)
    #expect(rig.model.selection == [sub])
    #expect(rig.icons.selectionIndexPaths == [IndexPath(item: 3, section: 0)])
  }

  @Test func keyboardFocusFollowsTheSwitch() async throws {
    let rig = try await rig()
    rig.window.orderFront(nil)
    rig.controller.focusList()
    let outline = try #require(rig.window.firstResponder as? NSOutlineView)

    showIcons(rig)
    #expect(rig.window.firstResponder === rig.icons)
    rig.controller.showAsList(nil)
    #expect(rig.window.firstResponder === outline)
  }
}
