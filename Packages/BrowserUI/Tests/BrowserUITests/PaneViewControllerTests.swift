import AppKit
import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

@Suite @MainActor struct PaneViewControllerTests {
  private let root = URL(filePath: "/fixture", directoryHint: .isDirectory)
  private var sub: URL { root.appending(path: "Sub", directoryHint: .isDirectory) }
  private var deeper: URL { sub.appending(path: "Deeper", directoryHint: .isDirectory) }

  /// `/fixture` holds `a.txt` and `Sub`; `Sub` holds `Deeper` and `inner.txt`.
  /// - Parameter gateAfterFirstItemsOfSub: Makes `Sub` hand `inner.txt` over
  ///   first, then hold at this gate before its whole listing.
  private func reader(gates: [URL: Gate] = [:], gateAfterFirstItemsOfSub: Gate? = nil)
    -> StubReader
  {
    var reader = reader(gates: gates)
    if let gate = gateAfterFirstItemsOfSub {
      reader.firstItems[sub] = [FileItem(url: sub.appending(path: "inner.txt"), kind: .file)]
      reader.gatesAfterFirstItems[sub] = gate
    }
    return reader
  }

  private func reader(gates: [URL: Gate]) -> StubReader {
    StubReader(
      results: [
        root: [
          FileItem(url: root.appending(path: "a.txt"), kind: .file),
          FileItem(url: sub, kind: .directory),
        ],
        sub: [
          FileItem(url: deeper, kind: .directory),
          FileItem(url: sub.appending(path: "inner.txt"), kind: .file),
        ],
        deeper: [],
      ],
      gates: gates)
  }

  /// A pane on `/fixture` in a window, with its first tab loaded.
  private func paneInAWindow(gates: [URL: Gate] = [:], gateAfterFirstItemsOfSub: Gate? = nil)
    async -> (pane: PaneViewController, window: NSWindow)
  {
    let pane = PaneViewController(
      location: root,
      reader: reader(gates: gates, gateAfterFirstItemsOfSub: gateAfterFirstItemsOfSub))
    let window = NSWindow(contentViewController: pane)
    await pane.showingBrowser.loadTask?.value
    return (pane, window)
  }

  /// Waits for every tab's listing, showing or not.
  private func settle(_ pane: PaneViewController) async {
    for browser in pane.tabs.tabs {
      await browser.loadTask?.value
    }
  }

  private func table(of browser: BrowserViewController) throws -> NSTableView {
    try #require(Self.firstSubview(of: NSTableView.self, in: browser.view))
  }

  /// Selects a row by name, as a click does.
  private func select(_ name: String, in browser: BrowserViewController) throws {
    let row = try #require(browser.model.items.firstIndex { $0.name == name })
    try table(of: browser).selectRowIndexes([row], byExtendingSelection: false)
  }

  /// Whether a browser's view is in the pane's view tree. Only the showing tab's is.
  private func isShown(_ browser: BrowserViewController, in pane: PaneViewController) -> Bool {
    browser.isViewLoaded && browser.view.isDescendant(of: pane.view)
  }

  /// The bar's buttons that carry an element's identifier, in order.
  private func buttons(_ element: AccessibilityElement, in pane: PaneViewController) -> [NSButton] {
    var found: [NSButton] = []
    func visit(_ view: NSView) {
      if let button = view as? NSButton, button.accessibilityIdentifier() == element.identifier {
        found.append(button)
      }
      for subview in view.subviews { visit(subview) }
    }
    visit(pane.tabBar)
    return found
  }

  private func menuItem(_ action: Selector) -> NSMenuItem {
    NSMenuItem(title: "", action: action, keyEquivalent: "")
  }

  // MARK: Tabs

  @Test func aNewPaneHasOneTabAHiddenTabBarAndItsBrowsersView() async throws {
    let (pane, window) = await paneInAWindow()
    #expect(pane.tabs.tabs.count == 1)
    #expect(pane.tabBar.isHidden)
    #expect(pane.showingBrowser.view.isDescendant(of: pane.view))
    #expect(pane.showingBrowser.parent === pane)
    #expect(pane.showingBrowser.model.items.map(\.name) == ["a.txt", "Sub"])
    #expect(window.title == "fixture")
    // With no bar, the browser has the whole pane.
    pane.view.layoutSubtreeIfNeeded()
    #expect(pane.showingBrowser.view.frame.height == pane.view.frame.height)
  }

  @Test func newTabOpensATabAtTheSameFolderWithNoHistoryAndShowsIt() async throws {
    let (pane, _) = await paneInAWindow()
    let first = pane.showingBrowser
    // The first tab has somewhere to go back to; the new one must not.
    try select("Sub", in: first)
    first.openSelection(nil)
    await settle(pane)
    try #require(first.model.canGoBack)

    pane.newTab(nil)
    let second = pane.showingBrowser
    #expect(pane.tabs.tabs == [first, second])
    #expect(second !== first)
    #expect(second.location == sub)
    #expect(!second.model.canGoBack && !second.model.canGoForward)
    #expect(!pane.tabBar.isHidden)
    #expect(!isShown(first, in: pane))
    #expect(isShown(second, in: pane))
    #expect(second.parent === pane)

    await settle(pane)
    #expect(second.model.items.map(\.name) == ["Deeper", "inner.txt"])
    #expect(second.model.selection.isEmpty)
    // The bar takes its height from the top of the pane.
    pane.view.layoutSubtreeIfNeeded()
    #expect(second.view.frame.height == pane.view.frame.height - TabBarView.height)
  }

  @Test func newTabSentStraightAfterOpenIsAtTheFolderThatWasOpened() async throws {
    let (pane, _) = await paneInAWindow()
    let first = pane.showingBrowser
    try select("Sub", in: first)

    // No await between the two: the listing of Sub has not started.
    first.openSelection(nil)
    pane.newTab(nil)
    #expect(pane.tabs.tabs.count == 2)
    #expect(pane.showingBrowser !== first)
    #expect(pane.showingBrowser.location == sub)

    await settle(pane)
    #expect(pane.showingBrowser.model.items.map(\.name) == ["Deeper", "inner.txt"])
  }

  @Test func newTabSentTwiceOpensTwoTabsAndEveryTabEndsLoaded() async throws {
    let (pane, _) = await paneInAWindow()

    // No await between the two.
    pane.newTab(nil)
    pane.newTab(nil)
    #expect(pane.tabs.tabs.count == 3)
    #expect(pane.tabs.showingIndex == 2)
    #expect(Set(pane.tabs.tabs.map(ObjectIdentifier.init)).count == 3)

    await settle(pane)
    for browser in pane.tabs.tabs {
      #expect(browser.model.state == .loaded)
      #expect(browser.model.items.map(\.name) == ["a.txt", "Sub"])
    }
    #expect(buttons(.tab, in: pane).count == 3)
  }

  @Test func eachTabKeepsItsFolderSelectionAndHistory() async throws {
    let (pane, _) = await paneInAWindow()
    let first = pane.showingBrowser
    try select("a.txt", in: first)
    pane.newTab(nil)
    let second = pane.showingBrowser
    await settle(pane)

    try select("Sub", in: second)
    second.openSelection(nil)
    await settle(pane)
    try select("inner.txt", in: second)

    pane.showPreviousTab(nil)
    #expect(pane.showingBrowser === first)
    #expect(isShown(first, in: pane) && !isShown(second, in: pane))
    #expect(first.location == root)
    #expect(try table(of: first).selectedRowIndexes == [0])
    #expect(!first.validateUserInterfaceItem(menuItem(#selector(BrowserViewController.goBack(_:)))))

    pane.showNextTab(nil)
    #expect(pane.showingBrowser === second)
    #expect(isShown(second, in: pane) && !isShown(first, in: pane))
    #expect(second.location == sub)
    #expect(try table(of: second).selectedRowIndexes == [1])
    #expect(second.validateUserInterfaceItem(menuItem(#selector(BrowserViewController.goBack(_:)))))
  }

  @Test func showNextTabWrapsAndSentTwiceMovesTwoTabs() async throws {
    let (pane, _) = await paneInAWindow()
    pane.newTab(nil)
    pane.newTab(nil)
    let tabs = pane.tabs.tabs
    try #require(tabs.count == 3 && pane.showingBrowser === tabs[2])

    pane.showNextTab(nil)
    #expect(pane.showingBrowser === tabs[0])

    // No await between the two.
    pane.showNextTab(nil)
    pane.showNextTab(nil)
    #expect(pane.showingBrowser === tabs[2])
    #expect(
      isShown(tabs[2], in: pane) && !isShown(tabs[0], in: pane) && !isShown(tabs[1], in: pane))

    pane.showPreviousTab(nil)
    pane.showPreviousTab(nil)
    #expect(pane.showingBrowser === tabs[0])
    await settle(pane)
    #expect(tabs.allSatisfy { $0.model.state == .loaded })
  }

  @Test func nextAndPreviousAreEnabledOnlyWithSeveralTabs() async throws {
    let (pane, _) = await paneInAWindow()
    let next = menuItem(#selector(PaneViewController.showNextTab(_:)))
    let previous = menuItem(#selector(PaneViewController.showPreviousTab(_:)))
    let new = menuItem(#selector(PaneViewController.newTab(_:)))
    let close = menuItem(#selector(PaneViewController.closeTab(_:)))
    func enabled() -> [Bool] {
      [next, previous, new, close].map { pane.validateUserInterfaceItem($0) }
    }
    #expect(enabled() == [false, false, true, true])

    pane.newTab(nil)
    #expect(enabled() == [true, true, true, true])

    pane.closeTab(nil)
    #expect(enabled() == [false, false, true, true])
  }

  // MARK: Closing

  @Test func closingTheMiddleTabShowsItsRightNeighbourAndCancelsItsListing() async throws {
    let gate = Gate()
    let (pane, _) = await paneInAWindow(gates: [sub: gate])
    pane.newTab(nil)
    pane.newTab(nil)
    await settle(pane)
    let tabs = pane.tabs.tabs
    try #require(tabs.count == 3)
    pane.showPreviousTab(nil)
    try #require(pane.showingBrowser === tabs[1])

    // The middle tab's listing of Sub is held at the gate.
    try select("Sub", in: tabs[1])
    tabs[1].openSelection(nil)
    await gate.waitUntilReached()
    let held = try #require(tabs[1].loadTask)

    pane.closeTab(nil)
    #expect(pane.tabs.tabs == [tabs[0], tabs[2]])
    #expect(pane.showingBrowser === tabs[2])
    #expect(isShown(tabs[2], in: pane) && !isShown(tabs[1], in: pane))
    #expect(tabs[1].parent == nil)
    #expect(buttons(.tab, in: pane).count == 2)
    // Required, not expected: a listing still running would be awaited at the gate forever.
    try #require(held.isCancelled)

    await gate.open()
    await held.value
    #expect(tabs[1].model.state == .loading)
  }

  @Test func closingDownToOneTabHidesTheBar() async throws {
    let (pane, _) = await paneInAWindow()
    let first = pane.showingBrowser
    pane.newTab(nil)
    try #require(!pane.tabBar.isHidden)

    pane.closeTab(nil)
    #expect(pane.tabs.tabs == [first])
    #expect(pane.tabBar.isHidden)
    #expect(isShown(first, in: pane))
    pane.view.layoutSubtreeIfNeeded()
    #expect(first.view.frame.height == pane.view.frame.height)
  }

  @Test func closeTabSentTwiceWithTwoTabsClosesOneTabAndAsksTheWindowToCloseOnce() async throws {
    let (pane, window) = await paneInAWindow()
    let first = pane.showingBrowser
    pane.newTab(nil)
    let closing = WindowCloseCounter()
    window.delegate = closing

    // No await between the two.
    pane.closeTab(nil)
    pane.closeTab(nil)
    #expect(pane.tabs.tabs == [first])
    #expect(closing.requests == 1)
    // The window refused, so the last tab is still there and showing.
    #expect(isShown(first, in: pane))
  }

  @Test func closingATabThatIsNotShowingThroughTheBarLeavesTheShowingTabInPlace() async throws {
    let (pane, _) = await paneInAWindow()
    let first = pane.showingBrowser
    pane.newTab(nil)
    pane.newTab(nil)
    let tabs = pane.tabs.tabs
    try #require(tabs.count == 3)
    let showingView = tabs[2].view
    try #require(buttons(.closeTabButton, in: pane).count == 3)

    buttons(.closeTabButton, in: pane)[0].performClick(nil)
    #expect(pane.tabs.tabs == [tabs[1], tabs[2]])
    #expect(pane.showingBrowser === tabs[2])
    #expect(tabs[2].view === showingView && showingView.isDescendant(of: pane.view))
    #expect(first.parent == nil)
    #expect(buttons(.tab, in: pane).map { $0.isAccessibilitySelected() } == [false, true])
  }

  // MARK: Titles

  @Test func theWindowIsTitledWithTheShowingTabsFolder() async throws {
    let (pane, window) = await paneInAWindow()
    let first = pane.showingBrowser
    #expect(window.title == "fixture")

    pane.newTab(nil)
    let second = pane.showingBrowser
    await settle(pane)
    #expect(window.title == "fixture")

    // The showing tab navigates: the window and its tab follow as the command arrives.
    try select("Sub", in: second)
    second.openSelection(nil)
    #expect(window.title == "Sub")
    #expect(pane.title == "Sub")
    #expect(buttons(.tab, in: pane).map(\.title) == ["fixture", "Sub"])
    await settle(pane)

    pane.showPreviousTab(nil)
    #expect(pane.showingBrowser === first)
    #expect(window.title == "fixture")
    pane.showNextTab(nil)
    #expect(window.title == "Sub")

    pane.closeTab(nil)
    #expect(pane.showingBrowser === first)
    #expect(window.title == "fixture")
  }

  @Test func aTabLeftWhileItsListingIsHeldFinishesWithoutTouchingTheWindow() async throws {
    let gate = Gate()
    let (pane, window) = await paneInAWindow(gates: [sub: gate])
    let first = pane.showingBrowser
    pane.newTab(nil)
    let second = pane.showingBrowser
    await settle(pane)

    try select("Sub", in: second)
    second.openSelection(nil)
    await gate.waitUntilReached()
    #expect(buttons(.tab, in: pane).map(\.title) == ["fixture", "Sub"])

    pane.showPreviousTab(nil)
    try #require(pane.showingBrowser === first)
    let focused = window.firstResponder
    #expect(focused === (try table(of: first)))
    #expect(window.title == "fixture")

    await gate.open()
    await settle(pane)
    #expect(second.model.state == .loaded)
    #expect(second.model.items.map(\.name) == ["Deeper", "inner.txt"])
    #expect(window.title == "fixture")
    #expect(window.firstResponder === focused)
    #expect(buttons(.tab, in: pane).map(\.title) == ["fixture", "Sub"])
    #expect(!isShown(second, in: pane))
  }

  @Test func aTabLeftBetweenItsFirstRowsAndItsSortedListFinishesWithoutTouchingTheWindow()
    async throws
  {
    // Left before its first rows, the tab makes both arrivals out of sight;
    // left after them, the sorted list alone.
    for leavingBeforeTheFirstRows in [true, false] {
      let before = Gate()
      let between = Gate()
      let (pane, window) = await paneInAWindow(
        gates: [sub: before], gateAfterFirstItemsOfSub: between)
      let first = pane.showingBrowser
      pane.newTab(nil)
      let second = pane.showingBrowser
      await settle(pane)

      try select("Sub", in: second)
      second.openSelection(nil)
      if leavingBeforeTheFirstRows {
        await before.waitUntilReached()
        #expect(second.model.items.isEmpty)
      } else {
        await before.open()
        await between.waitUntilReached()
        #expect(second.model.items.map(\.name) == ["inner.txt"])
      }

      pane.showPreviousTab(nil)
      try #require(pane.showingBrowser === first)
      let focused = window.firstResponder
      #expect(focused === (try table(of: first)))
      #expect(window.title == "fixture")
      var arrivals = 0
      let redraw = second.model.onChange
      second.model.onChange = {
        arrivals += 1
        redraw?()
      }

      await before.open()
      await between.open()
      await settle(pane)
      #expect(arrivals == (leavingBeforeTheFirstRows ? 2 : 1))
      #expect(second.model.state == .loaded)
      #expect(second.model.items.map(\.name) == ["Deeper", "inner.txt"])
      #expect(window.title == "fixture")
      #expect(window.firstResponder === focused)
      #expect(try table(of: first).numberOfRows == 2)
      #expect(first.model.items.map(\.name) == ["a.txt", "Sub"])
      #expect(buttons(.tab, in: pane).map(\.title) == ["fixture", "Sub"])
      #expect(!isShown(second, in: pane))
    }
  }

  // MARK: Keyboard focus

  @Test func showingAnotherTabPutsFocusInItsList() async throws {
    let (pane, window) = await paneInAWindow()
    let first = pane.showingBrowser
    first.focusList()
    try #require(window.firstResponder === (try table(of: first)))

    pane.newTab(nil)
    let second = pane.showingBrowser
    #expect(window.firstResponder === (try table(of: second)))

    pane.showNextTab(nil)
    #expect(window.firstResponder === (try table(of: first)))
    pane.showPreviousTab(nil)
    #expect(window.firstResponder === (try table(of: second)))
  }

  @Test func pressingAFocusedTabLeavesFocusOnIt() async throws {
    let (pane, window) = await paneInAWindow()
    let first = pane.showingBrowser
    pane.newTab(nil)
    let tabButton = try #require(buttons(.tab, in: pane).first)
    try #require(window.makeFirstResponder(tabButton))

    tabButton.performClick(nil)
    #expect(pane.showingBrowser === first)
    #expect(window.firstResponder === tabButton)
  }

  @Test func pressingATabWithFocusInTheListPutsFocusInTheNewTabsList() async throws {
    let (pane, window) = await paneInAWindow()
    let first = pane.showingBrowser
    pane.newTab(nil)
    try #require(window.firstResponder === (try table(of: pane.showingBrowser)))

    // What a click with the mouse does: it does not move focus to the tab.
    try #require(buttons(.tab, in: pane).first).performClick(nil)
    #expect(pane.showingBrowser === first)
    #expect(window.firstResponder === (try table(of: first)))
  }

  @Test func closingTheTabThatHasFocusPutsFocusInTheSurvivingTabsList() async throws {
    let (pane, window) = await paneInAWindow()
    let first = pane.showingBrowser
    pane.newTab(nil)
    try #require(window.firstResponder === (try table(of: pane.showingBrowser)))

    pane.closeTab(nil)
    #expect(pane.showingBrowser === first)
    #expect(window.firstResponder === (try table(of: first)))
    #expect(window.firstResponder !== window)
  }

  @Test func pressingAFocusedCloseButtonPutsFocusInTheShowingTabsList() async throws {
    let (pane, window) = await paneInAWindow()
    pane.newTab(nil)
    pane.newTab(nil)
    let tabs = pane.tabs.tabs
    try #require(tabs.count == 3)
    // The close button of the first tab, which is not showing.
    let closeButton = try #require(buttons(.closeTabButton, in: pane).first)
    try #require(window.makeFirstResponder(closeButton))

    closeButton.performClick(nil)
    #expect(pane.tabs.tabs == [tabs[1], tabs[2]])
    #expect(window.firstResponder === (try table(of: tabs[2])))
  }

  @Test func closingTheBarsLastButOneTabFromAFocusedCloseButtonPutsFocusInTheList() async throws {
    let (pane, window) = await paneInAWindow()
    let first = pane.showingBrowser
    pane.newTab(nil)
    // The bar goes away with this press, and its controls with it.
    let closeButton = try #require(buttons(.closeTabButton, in: pane).last)
    try #require(window.makeFirstResponder(closeButton))

    closeButton.performClick(nil)
    #expect(pane.tabBar.isHidden)
    #expect(window.firstResponder === (try table(of: first)))
  }

  // MARK: The responder chain

  @Test func thePaneOffersTheShowingBrowserForTheCommandsABrowserHandles() async throws {
    let (pane, _) = await paneInAWindow()
    let first = pane.showingBrowser
    pane.newTab(nil)
    let second = pane.showingBrowser
    let actions = [
      #selector(BrowserViewController.goBack(_:)), #selector(BrowserViewController.goForward(_:)),
      #selector(BrowserViewController.goToEnclosingFolder(_:)),
      #selector(BrowserViewController.openSelection(_:)),
    ]
    for action in actions {
      #expect(pane.supplementalTarget(forAction: action, sender: nil) as? NSResponder === second)
    }

    pane.showPreviousTab(nil)
    for action in actions {
      #expect(pane.supplementalTarget(forAction: action, sender: nil) as? NSResponder === first)
    }
    #expect(pane.supplementalTarget(forAction: #selector(NSText.selectAll(_:)), sender: nil) == nil)
  }

  @Test func withFocusOnATabTheToolbarsBackFollowsTheShowingTab() async throws {
    let (pane, window) = await paneInAWindow()
    let source = BrowserToolbar()
    window.toolbar = source.makeToolbar()
    let back = try #require(window.toolbar?.items.first { $0.view is NSButton })
    let action = try #require(back.action)
    try #require(action == #selector(BrowserViewController.goBack(_:)))

    // Tab 1 has no history; tab 2 is one folder in.
    let first = pane.showingBrowser
    pane.newTab(nil)
    let second = pane.showingBrowser
    await settle(pane)
    try select("Sub", in: second)
    second.openSelection(nil)
    await settle(pane)
    pane.showPreviousTab(nil)

    // Focus on a tab's button: the chain from it never passes a browser.
    let tabButtons = buttons(.tab, in: pane)
    try #require(tabButtons.count == 2)
    try #require(window.makeFirstResponder(tabButtons[0]))
    back.isEnabled = true
    back.validate()
    #expect(!back.isEnabled)
    #expect(ToolbarButtonItem.handler(of: action, for: back, in: nil) as? NSResponder === first)

    // Straight after the switch, with nothing validating the toolbar but the pane.
    tabButtons[1].performClick(nil)
    // Focus stays where it was, on the first tab's button.
    try #require(pane.showingBrowser === second && window.firstResponder === tabButtons[0])
    #expect(back.isEnabled)
    #expect(ToolbarButtonItem.handler(of: action, for: back, in: nil) as? NSResponder === second)

    tabButtons[0].performClick(nil)
    #expect(!back.isEnabled)
  }

  // MARK: Who watches

  /// A pane on `/fixture` in a window that is not on screen, with its first
  /// tab loaded. Each watch begins with `live`, as a real one does.
  private func watchedPane() async -> (
    pane: PaneViewController, window: NSWindow, reader: StubReader, watcher: StubWatcher
  ) {
    let reader = reader()
    let watcher = StubWatcher(sendsLive: true)
    let pane = PaneViewController(location: root, reader: reader, watcher: watcher)
    let window = NSWindow(contentViewController: pane)
    await pane.showingBrowser.loadTask?.value
    return (pane, window, reader, watcher)
  }

  @Test func aPaneWatchesTheShowingTabOnlyOnceItsViewHasAppeared() async throws {
    let (pane, _, _, watcher) = await watchedPane()
    #expect(watcher.requested.isEmpty)
    #expect(!pane.showingBrowser.model.isWatching)

    // What AppKit sends once the pane's view is on screen.
    pane.viewDidAppear()
    #expect(watcher.requested == [root])
    #expect(watcher.watched == [root])
  }

  @Test func aNewTabIsWatchedAndTheTabItReplacedIsNot() async throws {
    let (pane, _, _, watcher) = await watchedPane()
    pane.viewDidAppear()
    let first = pane.showingBrowser

    pane.newTab(nil)
    let second = pane.showingBrowser
    // Both tabs are at the same folder, so the streams are told apart by count.
    #expect(watcher.requested == [root, root])
    await watcher.waitForEnd(of: root)
    #expect(watcher.watched == [root])
    #expect(!first.model.isWatching)
    #expect(second.model.isWatching)

    // The watch follows the showing tab into a folder.
    await settle(pane)
    try select("Sub", in: second)
    second.openSelection(nil)
    #expect(watcher.requested == [root, root, sub])
    await watcher.waitForEnd(of: root, count: 2)
    #expect(watcher.watched == [sub])
  }

  @Test func showingATabAgainWatchesItAndBringsItsListUpToDate() async throws {
    let (pane, _, reader, watcher) = await watchedPane()
    pane.viewDidAppear()
    let first = pane.showingBrowser
    let firstAnswered = AnsweredSignals(of: first.model)
    // The first watch's `live` is answered before the tab is left.
    await firstAnswered.wait(for: 1)
    pane.newTab(nil)
    let second = pane.showingBrowser
    await settle(pane)
    try select("Sub", in: second)
    second.openSelection(nil)
    await settle(pane)
    await watcher.waitForEnd(of: root, count: 2)
    try #require(watcher.watched == [sub])

    // While the first tab was away, its folder changed.
    reader.changed.update {
      $0[root] = .items([FileItem(url: root.appending(path: "new.txt"), kind: .file)])
    }
    let listings = reader.listings(of: root)
    pane.showPreviousTab(nil)
    try #require(pane.showingBrowser === first)
    await watcher.waitForEnd(of: sub)
    #expect(watcher.watched == [root])

    // One refresh, from the new watch's `live`.
    await firstAnswered.wait(for: 2)
    #expect(reader.listings(of: root) == listings + 1)
    #expect(first.model.items.map(\.name) == ["new.txt"])
    #expect(try table(of: first).numberOfRows == 1)
  }

  @Test func closingTheShowingTabMovesTheWatchAndClosingAnotherTabChangesNoWatch() async throws {
    let (pane, _, _, watcher) = await watchedPane()
    pane.viewDidAppear()
    let first = pane.showingBrowser
    pane.newTab(nil)
    pane.newTab(nil)
    await settle(pane)
    let tabs = pane.tabs.tabs
    try #require(tabs.count == 3 && pane.showingBrowser === tabs[2])
    await watcher.waitForEnd(of: root, count: 2)
    try #require(watcher.requested.count == 3 && tabs[2].model.isWatching)

    // The first tab is not showing: closing it starts and stops nothing.
    try #require(buttons(.closeTabButton, in: pane).first).performClick(nil)
    try #require(pane.tabs.tabs == [tabs[1], tabs[2]])
    #expect(watcher.requested.count == 3)
    #expect(watcher.watched == [root])
    #expect(tabs[2].model.isWatching && !first.model.isWatching)

    // The showing tab closes: its watch ends and its neighbour's starts.
    pane.closeTab(nil)
    try #require(pane.showingBrowser === tabs[1])
    #expect(watcher.requested.count == 4)
    await watcher.waitForEnd(of: root, count: 3)
    #expect(watcher.watched == [root])
    #expect(tabs[1].model.isWatching && !tabs[2].model.isWatching)
  }

  @Test func aPaneThatLeavesTheScreenStopsWatchingAndOneThatReturnsRefreshes() async throws {
    let (pane, _, reader, watcher) = await watchedPane()
    let answered = AnsweredSignals(of: pane.showingBrowser.model)
    pane.viewDidAppear()
    await answered.wait(for: 1)

    pane.viewDidDisappear()
    // Required, not expected: a watch still running would be awaited forever.
    try #require(!pane.showingBrowser.model.isWatching)
    await watcher.waitForEnd(of: root)
    #expect(watcher.watched.isEmpty)

    let listings = reader.listings(of: root)
    pane.viewDidAppear()
    #expect(watcher.watched == [root])
    await answered.wait(for: 2)
    #expect(reader.listings(of: root) == listings + 1)
  }

  /// Asks AppKit, not the test: the window really goes on screen and closes.
  @Test func closingAWindowThatWasOnScreenEndsTheWatch() async throws {
    let (pane, window, _, watcher) = await watchedPane()
    window.isReleasedWhenClosed = false
    window.orderFront(nil)
    // Required, not expected: without a watch there is nothing to see end.
    try #require(watcher.watched == [root])
    try #require(pane.showingBrowser.model.isWatching)

    window.close()
    // Required, not expected: a watch still running would be awaited forever.
    try #require(!pane.showingBrowser.model.isWatching)
    await watcher.waitForEnd(of: root)
    #expect(watcher.watched.isEmpty)
  }

  @Test func aPaneGivenAReaderAndNoWatcherWatchesNothing() async throws {
    let (pane, _) = await paneInAWindow()
    pane.viewDidAppear()
    pane.newTab(nil)
    await settle(pane)
    #expect(pane.tabs.tabs.allSatisfy { !$0.model.isWatching })
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
}

/// Counts how often a window is asked to close, and refuses.
@MainActor
private final class WindowCloseCounter: NSObject, NSWindowDelegate {
  private(set) var requests = 0

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    requests += 1
    return false
  }
}
