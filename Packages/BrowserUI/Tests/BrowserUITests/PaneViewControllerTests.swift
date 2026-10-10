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
  private func reader(gates: [URL: Gate] = [:]) -> StubReader {
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
  private func paneInAWindow(gates: [URL: Gate] = [:]) async -> (
    pane: PaneViewController, window: NSWindow
  ) {
    let pane = PaneViewController(location: root, reader: reader(gates: gates))
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
