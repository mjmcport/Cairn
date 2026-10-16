import AppKit
import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// Capturing a tab or a pane and applying it again (plans/phase-1a-step-10-state-restoration.md, U2).
@Suite @MainActor struct SavedStateCaptureTests {
  private let root = URL(filePath: "/fixture/root", directoryHint: .isDirectory)
  private var sub: URL { root.appending(path: "Sub", directoryHint: .isDirectory) }
  private var other: URL { root.appending(path: "Other", directoryHint: .isDirectory) }
  private var third: URL { root.appending(path: "Third", directoryHint: .isDirectory) }
  private let subKey = FolderKey(names: ["Sub"])

  private func reader() -> StubReader {
    func file(_ name: String, in folder: URL) -> FileItem {
      FileItem(url: folder.appending(path: name), kind: .file)
    }
    return StubReader(results: [
      root: [
        FileItem(url: sub, kind: .directory), FileItem(url: other, kind: .directory),
        FileItem(url: third, kind: .directory), file("a.txt", in: root),
      ],
      sub: [file("x.txt", in: sub), file("y.txt", in: sub)],
      other: [file("o.txt", in: other)],
      third: [],
    ])
  }

  private func suite() throws -> (settings: BrowserSettings, cleanup: () -> Void) {
    let name = "SavedStateCaptureTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    return (BrowserSettings(defaults: defaults), { defaults.removePersistentDomain(forName: name) })
  }

  // MARK: Model

  @Test func aModelReproducesModeSortHiddenOpenFoldersAndSelection() async throws {
    let suite = try suite()
    defer { suite.cleanup() }
    let reader = reader()
    let model = BrowserModel(location: root, reader: reader, settings: suite.settings)
    await model.load()
    model.showsHiddenFiles = true
    model.changeSort(to: FileItemSort(key: .size, ascending: false, foldersFirst: true))
    model.openFolder(subKey)
    await model.waitForOpenFolders()
    model.selection = [sub.appending(path: "y.txt")]

    let saved = model.captureState()
    #expect(saved.location == root.absoluteString)
    #expect(saved.viewMode == .list)
    #expect(saved.showsHidden)
    #expect(saved.sort == SavedSort(key: .size, ascending: false, foldersFirst: true))
    #expect(saved.openFolders == [["Sub"]])
    #expect(saved.selection == [sub.appending(path: "y.txt").absoluteString])

    let data = try #require(SavedState(windows: [SavedWindow(tabs: [saved])]).encoded())
    let back = try #require(SavedState.decode(data)).windows[0].tabs[0]

    let again = BrowserModel(location: root, reader: reader, settings: suite.settings)
    again.restore(back)
    await again.load()
    await again.waitForOpenFolders()
    #expect(again.viewMode == .list)
    #expect(again.showsHiddenFiles)
    #expect(again.sort == FileItemSort(key: .size, ascending: false, foldersFirst: true))
    #expect(again.isOpen(subKey))
    #expect(again.selection.map(\.lastPathComponent) == ["y.txt"])
  }

  @Test func historySurvivesAndBackWorks() async throws {
    let suite = try suite()
    defer { suite.cleanup() }
    let reader = reader()
    let model = BrowserModel(location: root, reader: reader, settings: suite.settings)
    await model.load()
    await model.navigate(to: other)
    await model.navigate(to: sub)
    await model.goBack()
    let saved = model.captureState()
    #expect(saved.location == other.absoluteString)
    #expect(saved.back.map(\.location) == [root.absoluteString])
    #expect(saved.forward.map(\.location) == [sub.absoluteString])

    let again = BrowserModel(
      location: try #require(URL(string: saved.location)), reader: reader, settings: suite.settings)
    again.restore(saved)
    await again.load()
    #expect(again.canGoBack)
    #expect(again.canGoForward)
    await again.goBack()
    #expect(again.location == root)
  }

  @Test func iconsModeRestoresNoOpenFolders() async throws {
    let suite = try suite()
    defer { suite.cleanup() }
    let model = BrowserModel(location: root, reader: reader(), settings: suite.settings)
    var saved = SavedTab(location: root.absoluteString, viewMode: .icons)
    saved.openFolders = [["Sub"]]
    model.restore(saved)
    await model.load()
    await model.waitForOpenFolders()
    #expect(model.viewMode == .icons)
    #expect(!model.isOpen(subKey))
  }

  // MARK: Pane

  @Test func aPaneRestoresTabsInOrderWithTheSavedOneShowingAndListsOnlyThatOne() async throws {
    let reader = reader()
    let saved = SavedWindow(
      showsPathBar: false,
      tabs: [
        SavedTab(location: root.absoluteString),
        SavedTab(location: other.absoluteString, viewMode: .icons),
        SavedTab(location: third.absoluteString, viewMode: .columns),
      ],
      showingIndex: 1)
    let pane = PaneViewController(
      location: URL(filePath: "/unused", directoryHint: .isDirectory), reader: reader,
      watcher: nil, restoring: saved)
    let window = NSWindow(contentViewController: pane)
    _ = window
    await pane.showingBrowser.loadTask?.value

    #expect(pane.tabs.tabs.map(\.model.location) == [root, other, third])
    #expect(pane.tabs.showingIndex == 1)
    #expect(pane.tabs.tabs.map(\.model.viewMode) == [.list, .icons, .columns])
    #expect(!pane.showsPathBar)
    // Only the showing tab listed (R18).
    #expect(reader.listings(of: other) == 1)
    #expect(reader.listings(of: root) == 0)
    #expect(reader.listings(of: third) == 0)

    let captured = pane.captureState()
    #expect(captured.tabs.map(\.location) == saved.tabs.map(\.location))
    #expect(captured.showingIndex == 1)
    #expect(!captured.showsPathBar)
  }

  @Test func aPaneWithNothingUsableOpensTheDefaultLocation() async throws {
    let reader = reader()
    let pane = PaneViewController(
      location: root, reader: reader, watcher: nil,
      restoring: SavedWindow(tabs: [], showingIndex: 0))
    #expect(pane.tabs.tabs.count == 1)
    #expect(pane.showingBrowser.model.location == root)
  }
}
