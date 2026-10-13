import AppKit
import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// The column presentation (plans/phase-1a-step-07-column-view.md, U4): a real
/// `NSBrowser` in a window over a stub reader, a stub watcher and a stub
/// thumbnail provider. Nothing waits on a clock.
@Suite @MainActor struct ColumnViewTests {
  private let root = URL(filePath: "/fixture/root", directoryHint: .isDirectory)
  private var sub: URL { root.appending(path: "Sub", directoryHint: .isDirectory) }
  private var other: URL { root.appending(path: "Other", directoryHint: .isDirectory) }
  private var deep: URL { sub.appending(path: "Deep", directoryHint: .isDirectory) }

  private func file(_ name: String, in folder: URL, size: Int64 = 10) -> FileItem {
    FileItem(url: folder.appending(path: name), kind: .file, size: size)
  }

  private func folder(_ name: String, in parent: URL) -> FileItem {
    FileItem(url: parent.appending(path: name, directoryHint: .isDirectory), kind: .directory)
  }

  private func listings() -> [URL: [FileItem]] {
    [
      root: [
        file("alpha.txt", in: root), folder("Other", in: root), folder("Sub", in: root),
        FileItem(url: root.appending(path: ".hidden"), kind: .file, isHidden: true),
      ],
      sub: [folder("Deep", in: sub), file("x.txt", in: sub), file("y.txt", in: sub)],
      deep: [file("z.txt", in: deep)],
      other: [file("o.txt", in: other)],
    ]
  }

  @MainActor private struct Rig {
    let controller: BrowserViewController
    let window: NSWindow
    let reader: StubReader
    let watcher: StubWatcher
    let answered: AnsweredSignals
    let provider: StubThumbnailer

    var model: BrowserModel { controller.model }
    var browser: NSBrowser { controller.columns.browser }
  }

  private func rig(results: [URL: [FileItem]]? = nil) async throws -> Rig {
    let reader = StubReader(results: results ?? listings())
    let watcher = StubWatcher()
    let provider = StubThumbnailer()
    let controller = BrowserViewController(location: root, reader: reader, watcher: watcher)
    controller.thumbnailLoader = ThumbnailLoader(provider: provider)
    let answered = AnsweredSignals(of: controller.model)
    let window = NSWindow(contentViewController: controller)
    window.setContentSize(NSSize(width: 900, height: 500))
    window.layoutIfNeeded()
    await controller.loadTask?.value
    controller.startWatching()
    return Rig(
      controller: controller, window: window, reader: reader, watcher: watcher,
      answered: answered, provider: provider)
  }

  /// The text drawn in a column, row by row: the cells the browser has made
  /// for it, which for a short column is every row.
  private func names(_ rig: Rig, column: Int) -> [String] {
    rig.window.orderFront(nil)
    rig.browser.layoutSubtreeIfNeeded()
    rig.window.displayIfNeeded()
    var names: [String] = []
    for row in 0..<200 {
      // Past the last row the browser has only empty cells.
      guard let cell = rig.browser.loadedCell(atRow: row, column: column) as? NSCell,
        !cell.stringValue.isEmpty
      else { break }
      names.append(cell.stringValue)
    }
    return names
  }

  private func showColumns(_ rig: Rig) {
    rig.controller.showAsColumns(nil)
    rig.window.layoutIfNeeded()
    rig.browser.layoutSubtreeIfNeeded()
  }

  /// What a click does: select the row, and send the action.
  private func click(_ rig: Rig, row: Int, column: Int) {
    rig.browser.selectRow(row, inColumn: column)
    rig.browser.sendAction()
  }

  // MARK: The mode

  @Test func theCommandShowsTheBrowserInPlaceOfTheListAndIsChecked() async throws {
    let rig = try await rig()
    let item = NSMenuItem(
      title: "as Columns", action: #selector(BrowserViewController.showAsColumns(_:)),
      keyEquivalent: "")
    #expect(rig.browser.isHidden)

    showColumns(rig)
    #expect(!rig.browser.isHidden)
    #expect(rig.model.viewMode == .columns)
    #expect(rig.controller.validateUserInterfaceItem(item))
    #expect(item.state == .on)
    #expect(rig.browser.accessibilityIdentifier() == "column-browser")
  }

  @Test func theFirstColumnListsTheFolderWithoutHiddenItems() async throws {
    let rig = try await rig()
    showColumns(rig)
    #expect(names(rig, column: 0) == ["alpha.txt", "Other", "Sub"])
  }

  // MARK: Selecting folders

  @Test func selectingAFolderOpensItInTheModelAndFillsTheNextColumn() async throws {
    let rig = try await rig()
    showColumns(rig)

    click(rig, row: 2, column: 0)  // Sub
    #expect(rig.model.isOpen(FolderKey(names: ["Sub"])))
    #expect(rig.model.selection == [sub])
    await rig.model.waitForOpenFolders()

    #expect(names(rig, column: 1) == ["Deep", "x.txt", "y.txt"])
    // Not a move.
    #expect(rig.model.location == root)
    #expect(!rig.model.canGoBack)
  }

  @Test func selectingASiblingFolderClosesTheFirstOnesChain() async throws {
    let rig = try await rig()
    showColumns(rig)
    click(rig, row: 2, column: 0)
    await rig.model.waitForOpenFolders()
    click(rig, row: 0, column: 1)  // Deep
    await rig.model.waitForOpenFolders()
    try #require(rig.model.isOpen(FolderKey(names: ["Sub", "Deep"])))

    click(rig, row: 1, column: 0)  // Other
    #expect(!rig.model.isOpen(FolderKey(names: ["Sub"])))
    #expect(!rig.model.isOpen(FolderKey(names: ["Sub", "Deep"])))
    #expect(rig.model.isOpen(FolderKey(names: ["Other"])))
    await rig.model.waitForOpenFolders()
    #expect(names(rig, column: 1) == ["o.txt"])
  }

  @Test func selectingTheSameItemAgainChangesNothingAndPublishesNothing() async throws {
    let rig = try await rig()
    showColumns(rig)
    click(rig, row: 2, column: 0)
    await rig.model.waitForOpenFolders()
    var changes = 0
    rig.model.onChange = { changes += 1 }

    rig.browser.sendAction()
    rig.browser.sendAction()
    #expect(changes == 0)
    #expect(rig.model.selection == [sub])
  }

  // MARK: Selecting files

  @Test func aFileShowsItsPreviewAndSeveralShowACount() async throws {
    let rig = try await rig()
    showColumns(rig)
    click(rig, row: 2, column: 0)
    await rig.model.waitForOpenFolders()

    click(rig, row: 1, column: 1)  // x.txt
    #expect(rig.controller.previewController.shownName == "x.txt")
    #expect(rig.model.selection == [sub.appending(path: "x.txt")])

    rig.browser.selectionIndexPaths = [
      IndexPath(indexes: [2, 1]), IndexPath(indexes: [2, 2]),
    ]
    rig.browser.sendAction()
    #expect(rig.controller.previewController.shownName == "2 items")
    #expect(
      rig.model.selection == [sub.appending(path: "x.txt"), sub.appending(path: "y.txt")])
  }

  @Test func anOnlineOnlyFileShowsThatItIsAndIsNeverAskedFor() async throws {
    var results = listings()
    results[sub]?.append(
      FileItem(
        url: sub.appending(path: "cloud.png"), kind: .file, size: 100, allocatedSize: 0,
        isOnlineOnly: true))
    let rig = try await rig(results: results)
    showColumns(rig)
    click(rig, row: 2, column: 0)
    await rig.model.waitForOpenFolders()
    let row = try #require(names(rig, column: 1).firstIndex(of: "cloud.png"))

    click(rig, row: row, column: 1)
    #expect(rig.controller.previewController.showsCloudMark)
    #expect(
      rig.controller.previewController.shownFacts.contains(
        "Availability: Online only, not on this Mac"))
    #expect(!rig.provider.requests.map(\.lastPathComponent).contains("cloud.png"))
  }

  // MARK: Following the model

  @Test func aChangeInAColumnsFolderChangesThatColumnOnly() async throws {
    let rig = try await rig()
    showColumns(rig)
    click(rig, row: 2, column: 0)
    await rig.model.waitForOpenFolders()
    let before = names(rig, column: 0)

    var inside = listings()[sub]!
    inside.append(file("new.txt", in: sub))
    rig.reader.changed.update { $0[sub] = .items(inside) }
    await rig.watcher.send(to: sub)
    await rig.answered.wait(for: 1)

    #expect(names(rig, column: 1) == ["Deep", "new.txt", "x.txt", "y.txt"])
    #expect(names(rig, column: 0) == before)
    #expect(rig.model.selection == [sub])
  }

  @Test func aFolderThatCannotBeListedSaysWhyInItsColumn() async throws {
    var results = listings()
    results[sub] = nil
    let rig = try await rig(results: results)
    showColumns(rig)

    click(rig, row: 2, column: 0)
    await rig.model.waitForOpenFolders()

    let reason = try #require(rig.model.failure(of: FolderKey(names: ["Sub"])))
    // The browser draws the one row, and its cell is reused beyond it.
    #expect(names(rig, column: 1).first == reason)
  }

  // MARK: Switching

  @Test func switchingFromTheListKeepsTheSelectedItemAndTheFoldersThatLeadToIt() async throws {
    let rig = try await rig()
    rig.model.openFolder(FolderKey(names: ["Sub"]))
    await rig.model.waitForOpenFolders()
    rig.model.openFolder(FolderKey(names: ["Other"]))
    await rig.model.waitForOpenFolders()
    rig.model.selection = [sub.appending(path: "x.txt")]

    showColumns(rig)
    #expect(rig.model.isOpen(FolderKey(names: ["Sub"])))
    #expect(!rig.model.isOpen(FolderKey(names: ["Other"])))
    #expect(rig.model.selection == [sub.appending(path: "x.txt")])
    #expect(names(rig, column: 1) == ["Deep", "x.txt", "y.txt"])
    #expect(rig.controller.previewController.shownName == "x.txt")
  }

  @Test func aRoundTripThroughColumnsKeepsTheSelectionAndTheLocation() async throws {
    let rig = try await rig()
    rig.model.selection = [root.appending(path: "alpha.txt")]
    showColumns(rig)
    rig.controller.showAsList(nil)

    #expect(rig.model.selection == [root.appending(path: "alpha.txt")])
    #expect(rig.model.location == root)
    #expect(!rig.model.canGoBack)
  }

  // MARK: Opening

  @Test func openOnAFolderEntersItAsAMoveAndTheColumnsStartAgain() async throws {
    let rig = try await rig()
    showColumns(rig)
    click(rig, row: 2, column: 0)
    await rig.model.waitForOpenFolders()

    rig.controller.openSelection(nil)
    await rig.controller.loadTask?.value
    #expect(rig.model.location.lastPathComponent == "Sub")
    #expect(rig.model.canGoBack)
    #expect(rig.model.openFolders.isEmpty)
    #expect(names(rig, column: 0) == ["Deep", "x.txt", "y.txt"])
  }

  @Test func openOnAFileDoesNothing() async throws {
    let rig = try await rig()
    showColumns(rig)
    click(rig, row: 0, column: 0)
    rig.controller.openSelection(nil)
    #expect(rig.model.location == root)
  }

  @Test func typeSelectUsesTheNameOfTheRow() async throws {
    let rig = try await rig()
    showColumns(rig)
    let name = rig.controller.columns.browser(rig.browser, typeSelectStringForRow: 1, inColumn: 0)
    #expect(name == "Other")
  }
}
