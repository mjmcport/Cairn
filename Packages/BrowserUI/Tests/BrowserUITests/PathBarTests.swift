import AppKit
import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// A completer with canned folders that records where it was called from.
private final class StubCompleter: FolderCompleting, @unchecked Sendable {
  private let lock = NSLock()
  private var onMain: [Bool] = []
  var canned: [URL: [String]] = [:]
  var failing: Set<URL> = []
  var existences: [String: PathExistence] = [:]
  /// Prefixes whose answer is slow. A sleep, not a wait on a signal: a thread
  /// of the cooperative pool must never be held until something else happens.
  var slow: Set<String> = []

  var calledOnMain: Bool { lock.withLock { onMain.contains(true) } }

  func folders(in folder: URL, prefix: String, limit: Int) throws -> [FolderSuggestion] {
    lock.withLock { onMain.append(Thread.isMainThread) }
    if slow.contains(prefix) { Thread.sleep(forTimeInterval: 0.25) }
    if failing.contains(folder) { throw CocoaError(.fileReadNoPermission) }
    return (canned[folder] ?? [])
      .filter { prefix.isEmpty || $0.lowercased().hasPrefix(prefix.lowercased()) }
      .prefix(limit)
      .map {
        FolderSuggestion(name: $0, url: folder.appending(path: $0, directoryHint: .isDirectory))
      }
  }

  func existence(of url: URL) -> PathExistence {
    existences[url.path] ?? .missing
  }
}

@Suite @MainActor struct PathBarTests {
  private let root = URL(filePath: "/fixture", directoryHint: .isDirectory)
  private let docs = URL(filePath: "/fixture/Docs", directoryHint: .isDirectory)
  private let deep = URL(filePath: "/fixture/Docs/Reports/2026/Q3", directoryHint: .isDirectory)

  private func reader() -> StubReader {
    StubReader(results: [
      root: [FileItem(url: docs, kind: .directory)],
      docs: [FileItem(url: docs.appending(path: "a.txt"), kind: .file)],
      deep: [],
      VirtualLocation.recents.url: [],
    ])
  }

  private func pane(at location: URL? = nil) -> PaneViewController {
    let pane = PaneViewController(location: location ?? root, reader: reader())
    _ = pane.view
    return pane
  }

  /// Presses a button without `performClick`, which highlights the button
  /// by spinning the run loop and has stalled the main actor on macOS 15.
  private func press(_ button: NSButton?) {
    guard let button else { return }
    button.sendAction(button.action, to: button.target)
  }

  /// The titles after the root's name, which is read from the system.
  private func titles(_ pane: PaneViewController) -> [String] {
    Array(pane.pathBar.crumbs.map(\.title).dropFirst())
  }

  @Test func theBarFollowsMovesBackAndTabs() async {
    let pane = pane()
    #expect(titles(pane) == ["fixture"])
    pane.showingBrowser.show(docs)
    #expect(titles(pane) == ["fixture", "Docs"])
    pane.showingBrowser.goBack(nil)
    #expect(titles(pane) == ["fixture"])
    pane.show(docs, inNewTab: true)
    #expect(titles(pane) == ["fixture", "Docs"])
    pane.showPreviousTab(nil)
    #expect(titles(pane) == ["fixture"])
  }

  @Test func clickingAFolderNameMovesTheTabAsOneStepAndTheCurrentOneDoesNothing() async {
    let pane = pane(at: docs)
    await pane.showingBrowser.loadTask?.value
    let bar = pane.pathBar
    #expect(!pane.showingBrowser.model.canGoBack)

    press(bar.nameButtons.last)
    #expect(!pane.showingBrowser.model.canGoBack)

    press(bar.nameButtons[bar.nameButtons.count - 2])
    #expect(pane.showingBrowser.location == root)
    #expect(pane.showingBrowser.model.canGoBack)
    pane.showingBrowser.goBack(nil)
    #expect(pane.showingBrowser.location == docs)
  }

  @Test func aNamesMenuListsTheFoldersInsideItOffTheMainThread() async {
    let completer = StubCompleter()
    completer.canned[root] = ["Docs", "Pictures"]
    let bar = PathBarView(completer: completer)
    let menu = await bar.menu(forFolder: root)
    #expect(menu.items.map(\.title) == ["Docs", "Pictures"])
    #expect(menu.items.map(\.isEnabled) == [true, true])
    #expect(!completer.calledOnMain)
  }

  @Test func aFolderThatCannotBeListedGivesOneDisabledLine() async {
    let completer = StubCompleter()
    completer.failing = [root]
    let bar = PathBarView(completer: completer)
    let menu = await bar.menu(forFolder: root)
    #expect(menu.items.map(\.title) == ["Cannot list this folder"])
    #expect(!menu.items[0].isEnabled)
  }

  @Test func choosingAMenuLineNavigatesThere() async {
    let completer = StubCompleter()
    completer.canned[root] = ["Docs"]
    let bar = PathBarView(completer: completer)
    var chosen: URL?
    bar.onNavigate = { chosen = $0 }
    let menu = await bar.menu(forFolder: root)
    let item = menu.items[0]
    _ = item.target?.perform(item.action, with: item)
    #expect(chosen?.path == "/fixture/Docs")
  }

  @Test func aVirtualLocationShowsOneNameWithNoMenu() async {
    let pane = pane()
    pane.show(VirtualLocation.recents.url, inNewTab: false)
    let bar = pane.pathBar
    #expect(bar.crumbs.map(\.title) == ["Recents"])
    bar.frame = NSRect(x: 0, y: 0, width: 400, height: PathBarView.height)
    bar.layout()
    #expect(bar.menuButtons.map(\.isHidden) == [true])
  }

  @Test func longPathsCollapseFromTheLeftIntoOneMenu() {
    let bar = PathBarView(completer: StubCompleter())
    bar.update(location: deep, rootName: "Macintosh HD")
    bar.frame = NSRect(x: 0, y: 0, width: 800, height: PathBarView.height)
    bar.layout()
    #expect(bar.hiddenCount == 0)
    #expect(bar.overflowButton.isHidden)

    bar.frame = NSRect(x: 0, y: 0, width: 200, height: PathBarView.height)
    bar.layout()
    #expect(bar.hiddenCount > 0)
    #expect(!bar.overflowButton.isHidden)
    // The current name always stays.
    #expect(!bar.nameButtons.last!.isHidden)
    #expect(bar.nameButtons.first!.isHidden)

    var shown: NSMenu?
    bar.presentMenu = { menu, _ in shown = menu }
    press(bar.overflowButton)
    #expect(
      shown?.items.map(\.title)
        == ["Macintosh HD", "fixture", "Docs", "Reports", "2026"]
        .prefix(bar.hiddenCount).map { $0 })
  }

  @Test func theBarCanBeHiddenAndShown() {
    let pane = pane()
    #expect(pane.showsPathBar)
    pane.togglePathBar(nil)
    #expect(pane.pathBar.isHidden)
    pane.togglePathBar(nil)
    #expect(!pane.pathBar.isHidden)
  }

  @Test func everyControlHasItsIdentifierAndLabel() {
    let bar = PathBarView(completer: StubCompleter())
    bar.update(location: docs)
    #expect(bar.accessibilityIdentifier() == AccessibilityElement.pathBar.identifier)
    let names = bar.nameButtons.map {
      ($0.accessibilityIdentifier(), $0.accessibilityLabel() ?? "")
    }
    let ids = names.map(\.0)
    #expect(ids == Array(repeating: AccessibilityElement.pathCrumb.identifier, count: ids.count))
    let nameLabelsOK = names.map { $0.1.hasPrefix("Folder ") }
    #expect(!nameLabelsOK.contains(false))
    let menus = bar.menuButtons.map {
      ($0.accessibilityIdentifier(), $0.accessibilityLabel() ?? "")
    }
    let menuIDs = menus.map(\.0)
    #expect(
      menuIDs
        == Array(repeating: AccessibilityElement.pathCrumbMenu.identifier, count: menuIDs.count))
    let menuLabelsOK = menus.map { $0.1.hasPrefix("Folders in ") }
    #expect(!menuLabelsOK.contains(false))
  }
}

@Suite @MainActor struct CopyPathTests {
  private let root = URL(filePath: "/fixture", directoryHint: .isDirectory)
  private let home = URL(filePath: "/fixture", directoryHint: .isDirectory)
  private let spaced = URL(filePath: "/fixture/My Docs/a b.txt")
  private let plain = URL(filePath: "/fixture/c.txt")

  private func browser() async -> BrowserViewController {
    let reader = StubReader(results: [
      root: [
        FileItem(url: spaced, kind: .file),
        FileItem(url: plain, kind: .file),
      ],
      VirtualLocation.recents.url: [FileItem(url: plain, kind: .file)],
    ])
    let browser = BrowserViewController(location: root, reader: reader)
    _ = browser.view
    await browser.loadTask?.value
    return browser
  }

  private final class RecordingPasteboard: PathPasteboard {
    var text: String?
    var urls: [URL] = []
    func replace(with text: String, urls: [URL]) {
      self.text = text
      self.urls = urls
    }
  }

  private func pasteboard() -> RecordingPasteboard { RecordingPasteboard() }

  @Test func withNothingSelectedItCopiesTheFolder() async {
    let browser = await browser()
    let board = pasteboard()
    browser.copyPaths(as: .path, to: board, home: home)
    #expect(board.text == "/fixture")
  }

  @Test func selectedItemsAreCopiedOnePerLineInEachFormat() async {
    let browser = await browser()
    browser.model.selection = [spaced]
    let board = pasteboard()
    browser.copyPaths(as: .escapedPath, to: board, home: home)
    #expect(board.text == "/fixture/My\\ Docs/a\\ b.txt")
    browser.copyPaths(as: .homeRelativePath, to: board, home: home)
    #expect(board.text == "~/My Docs/a b.txt")
    browser.copyPaths(as: .fileURL, to: board, home: home)
    #expect(board.text == "file:///fixture/My%20Docs/a%20b.txt")
    #expect(board.urls == [spaced])

    browser.model.selection = [spaced, plain]
    browser.copyPaths(as: .path, to: board, home: home)
    let lines = (board.text ?? "").split(separator: "\n").map(String.init)
    #expect(Set(lines) == ["/fixture/My Docs/a b.txt", "/fixture/c.txt"])
  }

  @Test func theTextFormatsWriteNoURL() async {
    let browser = await browser()
    browser.model.selection = [plain]
    let board = pasteboard()
    browser.copyPaths(as: .path, to: board, home: home)
    #expect(board.urls.isEmpty)
  }

  @Test func itIsDisabledInAVirtualLocationWithNothingSelected() async {
    let browser = await browser()
    browser.show(VirtualLocation.recents.url)
    await browser.loadTask?.value
    #expect(browser.itemsToCopyPaths.isEmpty)
    browser.model.selection = [plain]
    #expect(browser.itemsToCopyPaths == [plain])
  }
}

@Suite @MainActor struct GoToFolderTests {
  private let base = URL(filePath: "/Users/me/Docs", directoryHint: .isDirectory)
  private let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)

  private func sheet(_ completer: StubCompleter) -> GoToFolderViewController {
    let sheet = GoToFolderViewController(base: base, home: home, completer: completer)
    _ = sheet.view
    return sheet
  }

  @Test func theFieldStartsWithTheShowingFolder() {
    let sheet = sheet(StubCompleter())
    #expect(sheet.field.stringValue == "/Users/me/Docs/")
  }

  @Test func typingOffersMatchingFoldersAndSaysHowMany() async {
    let completer = StubCompleter()
    completer.canned[home] = ["Documents", "Downloads", "Music"]
    let sheet = sheet(completer)
    sheet.field.stringValue = "~/Do"
    sheet.textDidChange()
    await sheet.settle()
    #expect(sheet.suggestions.map(\.name) == ["Documents", "Downloads"])
    #expect(sheet.status.stringValue == "2 folders match.")
    #expect(!completer.calledOnMain)
  }

  @Test func tabCompletesTheTextToTheChosenFolder() async {
    let completer = StubCompleter()
    completer.canned[home] = ["Documents"]
    let sheet = sheet(completer)
    sheet.field.stringValue = "~/Doc"
    sheet.textDidChange()
    await sheet.settle()
    sheet.completeSelection()
    #expect(sheet.field.stringValue == "/Users/me/Documents/")
  }

  @Test func anAnswerForOlderTextIsDropped() async throws {
    let completer = StubCompleter()
    completer.canned[home] = ["Alpha", "Beta"]
    completer.slow = ["A"]
    let sheet = sheet(completer)
    sheet.field.stringValue = "~/A"
    sheet.textDidChange()
    sheet.field.stringValue = "~/B"
    sheet.textDidChange()
    await sheet.settle()
    #expect(sheet.suggestions.map(\.name) == ["Beta"])
    try await Task.sleep(for: .milliseconds(500))
    #expect(sheet.suggestions.map(\.name) == ["Beta"])
  }

  @Test func aMissingPathKeepsTheSheetAndSaysSo() async {
    let sheet = sheet(StubCompleter())
    var went = false
    sheet.onGo = { _, _ in went = true }
    sheet.field.stringValue = "~/nope"
    sheet.go(nil)
    await sheet.settle()
    #expect(!went)
    #expect(sheet.status.stringValue == "There is no folder or file at that path.")
  }

  @Test func aFolderGoesThereAndAFileGoesToItsFolderWithTheFileSelected() async {
    let completer = StubCompleter()
    completer.existences = [
      "/Users/me/Pictures": .folder,
      "/Users/me/notes.txt": .file,
    ]
    let sheet = sheet(completer)
    var result: (URL, Set<URL>)?
    sheet.onGo = { result = ($0, $1) }

    sheet.field.stringValue = "~/Pictures"
    sheet.go(nil)
    await sheet.settle()
    #expect(result?.0.path == "/Users/me/Pictures")
    #expect(result?.1 == [])

    result = nil
    sheet.field.stringValue = "~/notes.txt"
    sheet.go(nil)
    await sheet.settle()
    #expect(result?.0.path == "/Users/me")
    #expect(result?.1.map(\.path) == ["/Users/me/notes.txt"])
  }
}
