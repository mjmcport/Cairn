import AppKit
import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

/// Everything a window saves tells its owner when it changes
/// (plans/phase-1a-step-10-state-restoration.md, U3).
@Suite @MainActor struct StateChangeSignalTests {
  private let root = URL(filePath: "/fixture/root", directoryHint: .isDirectory)
  private var sub: URL { root.appending(path: "Sub", directoryHint: .isDirectory) }

  private func reader() -> StubReader {
    StubReader(results: [
      root: [
        FileItem(url: sub, kind: .directory),
        FileItem(url: root.appending(path: "a.txt"), kind: .file),
      ],
      sub: [FileItem(url: sub.appending(path: "x.txt"), kind: .file)],
    ])
  }

  private func window() async -> (WindowContentViewController, NSWindow) {
    let pane = PaneViewController(location: root, reader: reader(), watcher: nil)
    let content = WindowContentViewController(pane: pane, sidebar: SidebarViewController())
    let window = NSWindow(contentViewController: content)
    window.setContentSize(NSSize(width: 1000, height: 600))
    await pane.showingBrowser.loadTask?.value
    return (content, window)
  }

  private final class Counter {
    var count = 0
  }

  private func counting(_ content: WindowContentViewController) -> Counter {
    let counter = Counter()
    content.onStateChange = { counter.count += 1 }
    return counter
  }

  @Test func aNewTabAndAClosedTabSignal() async throws {
    let (content, window) = await window()
    _ = window
    let counter = counting(content)
    content.pane.newTab(nil)
    #expect(counter.count > 0)
    counter.count = 0
    content.pane.closeTab(nil)
    #expect(counter.count > 0)
  }

  @Test func theViewModeSortHiddenFilesAndSelectionSignal() async throws {
    let (content, window) = await window()
    _ = window
    let model = content.pane.showingBrowser.model
    let counter = counting(content)

    model.setViewMode(.icons)
    #expect(counter.count > 0)
    counter.count = 0
    model.changeSort(to: FileItemSort(key: .size))
    #expect(counter.count > 0)
    counter.count = 0
    model.showsHiddenFiles = true
    #expect(counter.count > 0)
    counter.count = 0
    model.selection = [root.appending(path: "a.txt")]
    #expect(counter.count > 0)
  }

  @Test func aMoveSignals() async throws {
    let (content, window) = await window()
    _ = window
    let counter = counting(content)
    let model = content.pane.showingBrowser.model
    await model.navigate(to: sub)
    #expect(counter.count > 0)
  }

  @Test func thePathBarSignalsWhenItIsToggled() async throws {
    let (content, window) = await window()
    _ = window
    let counter = counting(content)
    content.pane.togglePathBar(nil)
    #expect(counter.count > 0)
  }

  @Test func theSidebarsWidthAndCollapseSignalAndAreCaptured() async throws {
    let (content, window) = await window()
    _ = window
    content.view.layoutSubtreeIfNeeded()
    let counter = counting(content)

    content.splitView.setPosition(220, ofDividerAt: 0)
    content.view.layoutSubtreeIfNeeded()
    #expect(counter.count > 0)
    let width = try #require(content.captureState().sidebarWidth)
    #expect(abs(width - 220) < 2)
    #expect(!content.captureState().sidebarCollapsed)

    counter.count = 0
    content.splitViewItems[0].isCollapsed = true
    content.view.layoutSubtreeIfNeeded()
    #expect(counter.count > 0)
    let collapsed = content.captureState()
    #expect(collapsed.sidebarCollapsed)
    #expect(collapsed.sidebarWidth == nil)
  }

  @Test func theListsColumnWidthsAreSavedUnderTheConfiguredName() async throws {
    let name = "StateChangeSignalTests-\(UUID().uuidString)"
    try await BrowserViewController.$columnAutosaveNameOverride.withValue(name) {
      let (content, window) = await window()
      _ = window
      let table = try #require(Self.outline(in: content.pane.showingBrowser.view))
      #expect(table.autosaveName == name)
      #expect(table.autosaveTableColumns)

      let column = try #require(table.tableColumns.last)
      column.width = 133
      // The table writes its columns after the resize, not during it.
      try await Task.sleep(for: .milliseconds(300))
      let keys = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.contains(name) }
      #expect(!keys.isEmpty)
      for key in keys { UserDefaults.standard.removeObject(forKey: key) }
    }
  }

  @Test func theSavedSortWinsOverTheTablesOwnAutosavedSortOrdering() async throws {
    let name = "StateChangeSignalTests-sort-\(UUID().uuidString)"
    defer {
      let defaults = UserDefaults.standard
      for key in defaults.dictionaryRepresentation().keys where key.contains(name) {
        defaults.removeObject(forKey: key)
      }
    }
    try await BrowserViewController.$columnAutosaveNameOverride.withValue(name) {
      // A first window leaves a different sort ordering in the defaults.
      let (first, firstWindow) = await window()
      _ = firstWindow
      first.pane.showingBrowser.model.changeSort(to: FileItemSort(key: .modificationDate))
      try await Task.sleep(for: .milliseconds(300))
      let stored = UserDefaults.standard.dictionaryRepresentation().keys.filter {
        $0.contains(name) && $0.contains("Sort Ordering")
      }
      #expect(!stored.isEmpty)

      let browser = BrowserViewController(
        restoring: SavedTab(
          location: root.absoluteString, sort: SavedSort(key: .size, ascending: false)),
        location: root, reader: reader(), watcher: nil)
      _ = browser.view
      let table = try #require(Self.outline(in: browser.view))
      let descriptor = try #require(table.sortDescriptors.first)
      #expect(descriptor.key == "size")
      #expect(!descriptor.ascending)
      #expect(browser.model.sort.key == .size)
    }
  }

  private static func outline(in view: NSView) -> NSOutlineView? {
    if let table = view as? NSOutlineView { return table }
    for subview in view.subviews {
      if let found = outline(in: subview) { return found }
    }
    return nil
  }
}
