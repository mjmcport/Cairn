import AppKit
import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

@Suite @MainActor struct WindowContentTests {
  private let root = URL(filePath: "/fixture", directoryHint: .isDirectory)
  private let docs = URL(filePath: "/fixture/Docs", directoryHint: .isDirectory)
  private let recents = VirtualLocation.recents.url

  private struct Volumes: VolumeSource {
    func volumes() -> [VolumeInfo] { [] }
  }
  private struct Cloud: CloudSource {
    func folders() -> [CloudFolder] { [] }
  }
  private struct Tags: TagSource {
    func tags() async -> [TagInfo] { [] }
  }
  private final class Favorites: FavoriteStoring, @unchecked Sendable {
    let records: [FavoriteRecord]
    init(_ records: [FavoriteRecord]) { self.records = records }
    func load() -> [FavoriteRecord]? { records }
    func save(_ records: [FavoriteRecord]) {}
  }
  private struct NeverEjects: VolumeEjecting {
    func eject(_ volume: URL) async throws {}
  }

  private func reader() -> StubReader {
    StubReader(results: [
      root: [
        FileItem(url: root.appending(path: "a.txt"), kind: .file),
        FileItem(url: docs, kind: .directory),
      ],
      docs: [FileItem(url: docs.appending(path: "inner.txt"), kind: .file)],
      recents: [
        FileItem(url: URL(filePath: "/elsewhere/recent.txt"), kind: .file),
        FileItem(url: docs, kind: .directory),
      ],
    ])
  }

  private func windowContent() async -> (
    content: WindowContentViewController, window: NSWindow
  ) {
    let pane = PaneViewController(location: root, reader: reader())
    let sidebar = SidebarViewController(
      favoriteStore: Favorites([]), volumeSource: Volumes(), cloudSource: Cloud(),
      tagSource: Tags(), ejector: NeverEjects())
    let content = WindowContentViewController(pane: pane, sidebar: sidebar)
    let window = NSWindow(contentViewController: content)
    window.setContentSize(NSSize(width: 900, height: 600))
    await pane.showingBrowser.loadTask?.value
    await sidebar.refresh()
    return (content, window)
  }

  private func recentsItem(in content: WindowContentViewController) throws -> SidebarItem {
    try #require(content.sidebar.sections.flatMap(\.items).first { $0.kind == .recents })
  }

  @Test func theWindowShowsTheSidebarBesideThePane() async throws {
    let (content, _) = await windowContent()
    #expect(content.splitViewItems.count == 2)
    #expect(content.splitViewItems[0].behavior == .sidebar)
    #expect(content.splitViewItems[0].viewController === content.sidebar)
    #expect(content.splitViewItems[1].viewController === content.pane)
    #expect(content.splitViewItems[0].canCollapse)
  }

  @Test func choosingAnItemMovesTheShowingTabAndBackReturns() async throws {
    let (content, window) = await windowContent()
    let browser = content.pane.showingBrowser
    let item = try recentsItem(in: content)

    content.sidebar.onChoose?(item, false)
    await browser.loadTask?.value

    #expect(browser.location == recents)
    #expect(Set(browser.model.items.map(\.name)) == ["recent.txt", "Docs"])
    #expect(window.title == "Recents")
    #expect(content.pane.tabs.tabs.count == 1)
    #expect(content.sidebar.selectedItem?.kind == .recents)

    browser.goBack(nil)
    await browser.loadTask?.value
    #expect(browser.location == root)
    #expect(window.title == "fixture")
    #expect(content.sidebar.selectedItem == nil)
  }

  @Test func aCommandChoiceOpensANewTabAndLeavesTheOneItWasIn() async throws {
    let (content, _) = await windowContent()
    let first = content.pane.showingBrowser
    let item = try recentsItem(in: content)

    content.sidebar.onChoose?(item, true)
    let second = content.pane.showingBrowser
    await second.loadTask?.value

    #expect(content.pane.tabs.tabs.count == 2)
    #expect(second !== first)
    #expect(second.location == recents)
    #expect(first.location == root)
  }

  @Test func theSidebarFollowsTheTabThatIsShowing() async throws {
    let (content, _) = await windowContent()
    let item = try recentsItem(in: content)
    content.sidebar.onChoose?(item, true)
    await content.pane.showingBrowser.loadTask?.value
    #expect(content.sidebar.selectedItem?.kind == .recents)

    content.pane.showPreviousTab(nil)
    #expect(content.sidebar.selectedItem == nil)
    content.pane.showNextTab(nil)
    #expect(content.sidebar.selectedItem?.kind == .recents)
  }

  @Test func theSidebarHasTheChoiceTheShowingFolderDoesNotAndNoMoreThanOneSelection() async throws {
    let (content, _) = await windowContent()
    content.sidebar.select(location: recents)
    #expect(content.sidebar.selectedItem?.kind == .recents)
    content.sidebar.select(location: nil)
    #expect(content.sidebar.selectedItem == nil)
  }

  @Test func commandsReachThePaneAndItsBrowserWithFocusInTheSidebar() async throws {
    let (content, _) = await windowContent()
    let browser = content.pane.showingBrowser

    #expect(
      content.supplementalTarget(forAction: #selector(PaneViewController.newTab(_:)), sender: nil)
        as? PaneViewController === content.pane)
    #expect(
      content.supplementalTarget(
        forAction: #selector(BrowserViewController.goBack(_:)), sender: nil)
        as? BrowserViewController === browser)
  }

  @Test func addToSidebarOffersTheSelectedFolderOrTheOneShown() async throws {
    let (content, _) = await windowContent()
    let browser = content.pane.showingBrowser
    #expect(browser.folderToAdd == root)

    browser.model.selection = [docs]
    #expect(browser.folderToAdd == docs)

    browser.model.selection = [root.appending(path: "a.txt")]
    #expect(browser.folderToAdd == nil, "A file is not offered, and neither is its folder")
  }

  @Test func addToSidebarIsNotOfferedInARecentsListWithNothingSelected() async throws {
    let (content, _) = await windowContent()
    let browser = content.pane.showingBrowser
    content.sidebar.onChoose?(try recentsItem(in: content), false)
    await browser.loadTask?.value
    #expect(browser.folderToAdd == nil)

    browser.model.selection = [docs]
    #expect(browser.folderToAdd == docs)
  }
}
