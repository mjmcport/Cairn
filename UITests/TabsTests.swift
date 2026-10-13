import BrowserUI
import TestSupport
import XCTest

/// End-to-end tests of tabs (Phase 1A step 2). Each test is one launch that
/// walks through several behaviors, because every launch adds to a CI run.
final class TabsTests: XCTestCase {
  private var tree: FixtureTree!

  override func setUpWithError() throws {
    continueAfterFailure = false
    tree = try FixtureTree.build {
      FixtureNode.file("alpha.txt")
      FixtureNode.directory("Sub") {
        FixtureNode.file("inner.txt")
      }
    }
  }

  override func tearDownWithError() throws {
    try tree?.remove()
  }

  @MainActor
  private func launch() -> (app: XCUIApplication, table: XCUIElement, window: XCUIElement) {
    let app = XCUIApplication()
    app.launchArguments = ["-OpenFolder", tree.root.path, "-ApplePersistenceIgnoreState", "YES"]
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }
    // Only the showing tab's list is in the window, so this is always that one.
    let table = app.outlines[AccessibilityElement.fileList.identifier]
    XCTAssertTrue(table.staticTexts["Sub"].waitForExistence(timeout: 10))
    return (app, table, app.windows[AccessibilityElement.mainWindow.identifier])
  }

  @MainActor
  private func row(_ name: String, in table: XCUIElement) -> XCUIElement {
    table.outlineRows.containing(.staticText, identifier: name).firstMatch
  }

  @MainActor
  private func tabBar(_ app: XCUIApplication) -> XCUIElement {
    app.tabGroups[AccessibilityElement.tabBar.identifier]
  }

  /// The tabs in order.
  @MainActor
  private func tabs(_ app: XCUIApplication) -> XCUIElementQuery {
    tabBar(app).tabs.matching(identifier: AccessibilityElement.tab.identifier)
  }

  /// The close buttons in the order of their tabs.
  @MainActor
  private func closeButtons(_ app: XCUIApplication) -> XCUIElementQuery {
    tabBar(app).buttons.matching(identifier: AccessibilityElement.closeTabButton.identifier)
  }

  /// Which tabs report themselves as the one showing.
  @MainActor
  private func showingTabs(_ app: XCUIApplication) -> [Bool] {
    tabs(app).allElementsBoundByIndex.map(\.isSelected)
  }

  @MainActor
  private func waitForCount(_ count: Int, of query: XCUIElementQuery, _ message: String) {
    let matches = NSPredicate { _, _ in query.count == count }
    let expectation = XCTNSPredicateExpectation(predicate: matches, object: nil)
    let result = XCTWaiter.wait(for: [expectation], timeout: 10)
    XCTAssertEqual(result, .completed, "\(message): found \(query.count)")
  }

  @MainActor
  private func waitForShowing(_ expected: [Bool], _ app: XCUIApplication) {
    let matches = NSPredicate { _, _ in self.showingTabs(app) == expected }
    let expectation = XCTNSPredicateExpectation(predicate: matches, object: nil)
    let result = XCTWaiter.wait(for: [expectation], timeout: 10)
    XCTAssertEqual(result, .completed, "Expected \(expected), found \(showingTabs(app))")
  }

  /// Opens the Window menu, reads its items and closes it. A menu validates
  /// its items as it opens, so a closed menu's state is stale.
  @MainActor
  private func windowMenuItems(_ app: XCUIApplication) -> (titles: [String], enabled: Set<String>) {
    let menu = app.menuBars.menuBarItems["Window"]
    menu.click()
    XCTAssertTrue(menu.menuItems["Show Next Tab"].waitForExistence(timeout: 10))
    let items = menu.menuItems.allElementsBoundByIndex
    let titles = items.map(\.title)
    let enabled = Set(items.filter(\.isEnabled).map(\.title))
    app.typeKey(.escape, modifierFlags: [])
    return (titles, enabled)
  }

  private static let tabCommands: Set<String> = ["Show Next Tab", "Show Previous Tab"]

  @MainActor
  func testTabsKeepTheirOwnFolderHistoryAndSelection() throws {
    let (app, table, window) = launch()
    let rootName = tree.root.lastPathComponent
    let back = app.toolbars.buttons.matching(
      identifier: AccessibilityElement.backButton.identifier
    ).firstMatch

    // One tab: no bar, and nowhere for Next and Previous to go.
    XCTAssertFalse(tabBar(app).exists)
    XCTAssertTrue(windowMenuItems(app).enabled.isDisjoint(with: Self.tabCommands))

    app.typeKey("t", modifierFlags: .command)
    XCTAssertTrue(tabBar(app).waitForExistence(timeout: 10))
    waitForCount(2, of: tabs(app), "Expected two tabs after Command-T")
    XCTAssertEqual(tabs(app).allElementsBoundByIndex.map(\.title), [rootName, rootName])
    XCTAssertEqual(showingTabs(app), [false, true])
    XCTAssertTrue(windowMenuItems(app).enabled.isSuperset(of: Self.tabCommands))

    // Tab 2 goes into Sub: its title, the window and Back follow.
    XCTAssertTrue(table.staticTexts["Sub"].waitForExistence(timeout: 10))
    table.staticTexts["Sub"].doubleClick()
    XCTAssertTrue(table.staticTexts["inner.txt"].waitForExistence(timeout: 10))
    XCTAssertEqual(tabs(app).allElementsBoundByIndex.map(\.title), [rootName, "Sub"])
    XCTAssertEqual(window.title, "Sub")
    XCTAssertTrue(back.isEnabled)

    // While tab 1 is not showing, another process, this test runner, adds a
    // file to its folder. No one is watching a tab that is not on screen.
    try Data().write(to: tree.url("arrived.txt"), options: .withoutOverwriting)

    // Control-Tab wraps to tab 1, which is where it was left, with no history.
    app.typeKey(.tab, modifierFlags: .control)
    XCTAssertTrue(table.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    // Shown again, the tab brings its list up to date by itself (Phase 1A step 4).
    XCTAssertTrue(
      table.staticTexts["arrived.txt"].waitForExistence(timeout: 10),
      "The file added while the tab was away did not appear")
    XCTAssertEqual(showingTabs(app), [true, false])
    XCTAssertFalse(back.isEnabled)
    XCTAssertEqual(window.title, rootName)
    table.staticTexts["alpha.txt"].click()
    XCTAssertTrue(row("alpha.txt", in: table).isSelected)

    app.typeKey(.tab, modifierFlags: [.control, .shift])
    XCTAssertTrue(table.staticTexts["inner.txt"].waitForExistence(timeout: 10))
    XCTAssertEqual(showingTabs(app), [false, true])
    XCTAssertEqual(window.title, "Sub")

    // Back acts on the showing tab: tab 2 returns to the launch folder with Sub selected.
    app.typeKey("[", modifierFlags: .command)
    XCTAssertTrue(table.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    XCTAssertEqual(showingTabs(app), [false, true])
    XCTAssertTrue(row("Sub", in: table).isSelected)
    XCTAssertFalse(row("alpha.txt", in: table).isSelected)

    // Command-Shift-]: tab 1 again, with its own selection.
    app.typeKey("]", modifierFlags: [.command, .shift])
    waitForShowing([true, false], app)
    XCTAssertTrue(row("alpha.txt", in: table).isSelected)
    XCTAssertFalse(row("Sub", in: table).isSelected)

    // Command-Shift-[: back on tab 2.
    app.typeKey("[", modifierFlags: [.command, .shift])
    waitForShowing([false, true], app)
    XCTAssertTrue(row("Sub", in: table).isSelected)
    XCTAssertFalse(row("alpha.txt", in: table).isSelected)

    // Command-Shift-W closes the window with both tabs, where Command-W
    // would close one tab and leave the window.
    app.typeKey("w", modifierFlags: [.command, .shift])
    waitForCount(0, of: app.windows, "Command-Shift-W should close the window and its two tabs")
  }

  @MainActor
  func testClosingTabsAndTheWindow() {
    let (app, table, window) = launch()

    // Command-W with a window that has no tabs in front closes that window.
    app.menuBars.menuBarItems["Cairn"].click()
    app.menuBars.menuItems["About Cairn"].click()
    waitForCount(1, of: app.dialogs, "Expected the About panel")
    app.typeKey("w", modifierFlags: .command)
    waitForCount(0, of: app.dialogs, "Command-W should close the About panel")
    XCTAssertTrue(window.exists)
    XCTAssertTrue(table.staticTexts["Sub"].exists)
    XCTAssertFalse(tabBar(app).exists)

    // Tab 2 by the keyboard, in Sub, then tab 3 by the bar's button.
    app.typeKey("t", modifierFlags: .command)
    waitForCount(2, of: tabs(app), "Expected two tabs after Command-T")
    table.staticTexts["Sub"].doubleClick()
    XCTAssertTrue(table.staticTexts["inner.txt"].waitForExistence(timeout: 10))
    let newTab = tabBar(app).buttons[AccessibilityElement.newTabButton.identifier]
    XCTAssertEqual(newTab.label, AccessibilityElement.newTabButton.label)
    newTab.click()
    waitForCount(3, of: tabs(app), "Expected three tabs after pressing New Tab")
    XCTAssertEqual(showingTabs(app), [false, false, true])

    // With three tabs each shortcut's direction shows: with two, next and
    // previous land on the same tab. Each pair goes one step and wraps once.
    app.typeKey(.tab, modifierFlags: [.control, .shift])
    waitForShowing([false, true, false], app)
    app.typeKey(.tab, modifierFlags: .control)
    waitForShowing([false, false, true], app)
    app.typeKey(.tab, modifierFlags: .control)
    waitForShowing([true, false, false], app)
    app.typeKey("[", modifierFlags: [.command, .shift])
    waitForShowing([false, false, true], app)
    app.typeKey("[", modifierFlags: [.command, .shift])
    waitForShowing([false, true, false], app)
    app.typeKey("]", modifierFlags: [.command, .shift])
    waitForShowing([false, false, true], app)

    // The system's own tab commands are switched off: the menu has ours, once each.
    let menu = windowMenuItems(app)
    for title in Self.tabCommands {
      XCTAssertEqual(menu.titles.filter { $0 == title }.count, 1, "Window > \(title)")
    }
    for title in [
      "Show Tab Bar", "Hide Tab Bar", "Show All Tabs", "Merge All Windows",
      "Move Tab to New Window",
    ] {
      XCTAssertFalse(menu.titles.contains(title), "The system added Window > \(title)")
    }

    // A click on a tab shows it.
    tabs(app).element(boundBy: 0).click()
    XCTAssertTrue(table.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    XCTAssertEqual(showingTabs(app), [true, false, false])

    // Closing a tab that is not showing leaves the showing one alone.
    XCTAssertEqual(
      closeButtons(app).element(boundBy: 2).label,
      "\(AccessibilityElement.closeTabButton.label) Sub")
    closeButtons(app).element(boundBy: 2).click()
    waitForCount(2, of: tabs(app), "Expected two tabs after closing the third")
    XCTAssertEqual(showingTabs(app), [true, false])
    XCTAssertTrue(table.staticTexts["alpha.txt"].exists)

    // Command-W closes the showing tab. One tab is left, so the bar goes, and
    // the list has keyboard focus: Down Arrow selects its first row.
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(table.staticTexts["inner.txt"].waitForExistence(timeout: 10))
    XCTAssertFalse(tabBar(app).exists)
    XCTAssertEqual(window.title, "Sub")
    app.typeKey(.downArrow, modifierFlags: [])
    XCTAssertTrue(row("inner.txt", in: table).isSelected)

    // Command-W on the last tab closes the window.
    app.typeKey("w", modifierFlags: .command)
    waitForCount(0, of: app.windows, "Command-W on the last tab should close the window")

    // With the main window gone no pane is left to handle Command-W: the app
    // delegate closes the window in front.
    app.menuBars.menuBarItems["Cairn"].click()
    app.menuBars.menuItems["About Cairn"].click()
    waitForCount(1, of: app.dialogs, "Expected the About panel with no main window")
    app.typeKey("w", modifierFlags: .command)
    waitForCount(0, of: app.dialogs, "Command-W should close the About panel with no main window")
  }
}
