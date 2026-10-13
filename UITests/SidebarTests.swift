import BrowserUI
import TestSupport
import XCTest

/// End-to-end tests of the sidebar (Phase 1A step 8): choosing a favorite,
/// adding and removing one, and the places that are not folders.
///
/// Each launch names a defaults suite of its own for favorites, so these
/// tests never read or change the person's.
final class SidebarTests: XCTestCase {
  private var tree: FixtureTree!
  private var suite: String!

  override func setUpWithError() throws {
    continueAfterFailure = false
    suite = "cairn.uitests.favorites.\(UUID().uuidString)"
    tree = try FixtureTree.build {
      FixtureNode.file("alpha.txt")
      FixtureNode.directory("Sub") {
        FixtureNode.file("inner.txt")
      }
    }
  }

  override func tearDownWithError() throws {
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    try tree?.remove()
  }

  @MainActor
  private func launch() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [
      "-OpenFolder", tree.root.path, "-ApplePersistenceIgnoreState", "YES",
      "-FavoritesSuite", suite, "-SearchScope", tree.root.path,
    ]
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }
    XCTAssertTrue(
      app.outlines[AccessibilityElement.fileList.identifier].staticTexts["Sub"]
        .waitForExistence(timeout: 10), "The folder did not appear")
    return app
  }

  @MainActor
  private func sidebar(_ app: XCUIApplication) -> XCUIElement {
    app.outlines[AccessibilityElement.sidebar.identifier]
  }

  @MainActor
  private func sidebarItem(_ name: String, in app: XCUIApplication) -> XCUIElement {
    sidebar(app).staticTexts.matching(
      NSPredicate(format: "value == %@ OR label == %@", name, name)
    ).firstMatch
  }

  @MainActor
  private func title(_ app: XCUIApplication) -> String {
    app.windows[AccessibilityElement.mainWindow.identifier].title
  }

  @MainActor
  private func waitUntil(_ message: String, _ condition: @escaping () -> Bool) {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in condition() }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, message)
  }

  /// Selects `Sub` in the list and adds it to the sidebar.
  @MainActor
  private func addSub(to app: XCUIApplication) {
    let list = app.outlines[AccessibilityElement.fileList.identifier]
    list.outlineRows.containing(.staticText, identifier: "Sub").firstMatch.click()
    app.typeKey("t", modifierFlags: [.control, .command])
    XCTAssertTrue(
      sidebarItem("Sub", in: app).waitForExistence(timeout: 10), "Sub was not added to the sidebar")
  }

  // MARK: Favorites

  @MainActor
  func testAFavoriteIsAddedChosenInANewTabAndKeptAcrossALaunch() throws {
    let app = launch()
    XCTAssertTrue(sidebar(app).waitForExistence(timeout: 10), "The sidebar did not appear")
    XCTAssertTrue(sidebarItem("Recents", in: app).exists)

    // Added from the list, with the selected folder.
    addSub(to: app)

    // Choosing it shows it in the same tab, and Back returns.
    sidebarItem("Sub", in: app).click()
    waitUntil("Sub shown") { self.title(app) == "Sub" }
    XCTAssertTrue(
      app.outlines[AccessibilityElement.fileList.identifier].staticTexts["inner.txt"]
        .waitForExistence(timeout: 10))
    app.typeKey("[", modifierFlags: .command)
    waitUntil("Back to the fixture") { self.title(app) == self.tree.root.lastPathComponent }

    // Command-click opens a tab.
    XCUIElement.perform(withKeyModifiers: .command) { sidebarItem("Sub", in: app).click() }
    let tabs = app.tabGroups[AccessibilityElement.tabBar.identifier].tabs.matching(
      identifier: AccessibilityElement.tab.identifier)
    waitUntil("Two tabs") { tabs.count == 2 }
    waitUntil("The new tab shows Sub") { self.title(app) == "Sub" }

    // It is kept: a second launch finds it without being told.
    app.terminate()
    let again = launch()
    XCTAssertTrue(
      sidebarItem("Sub", in: again).waitForExistence(timeout: 10), "The favorite was not kept")

    // And removed from the context menu, so it is gone from the next launch too.
    sidebarItem("Sub", in: again).rightClick()
    again.menuItems["Remove from Sidebar"].click()
    waitUntil("Sub removed") { !self.sidebarItem("Sub", in: again).exists }
  }

  @MainActor
  func testDeleteRemovesTheSelectedFavorite() throws {
    let app = launch()
    addSub(to: app)
    sidebarItem("Sub", in: app).click()
    waitUntil("Sub shown") { self.title(app) == "Sub" }
    app.typeKey(.delete, modifierFlags: [])
    waitUntil("Sub removed") { !self.sidebarItem("Sub", in: app).exists }
  }

  // MARK: Places that are not folders

  @MainActor
  func testRecentsIsAPlaceWithNoEnclosingFolder() throws {
    let app = launch()
    sidebarItem("Recents", in: app).click()
    waitUntil("Recents shown") { self.title(app) == "Recents" }

    app.menuBars.menuBarItems["Go"].click()
    let enclosing = app.menuBars.menuItems["Enclosing Folder"]
    XCTAssertTrue(enclosing.waitForExistence(timeout: 10))
    XCTAssertFalse(enclosing.isEnabled, "Recents is inside no folder")
    app.typeKey(.escape, modifierFlags: [])

    // Back to the folder the tab was on.
    app.typeKey("[", modifierFlags: .command)
    waitUntil("Back to the fixture") { self.title(app) == self.tree.root.lastPathComponent }
  }

  @MainActor
  func testATagThatSpotlightHasSeenIsListedAndShowsItsFiles() throws {
    let tag = "CairnTest\(UUID().uuidString.prefix(8))"
    // The typed setter needs macOS 26; the NSURL one works on 15.
    try (tree.url("alpha.txt") as NSURL).setResourceValue([tag], forKey: .tagNamesKey)

    // Spotlight indexes in its own time, and may not index a temporary
    // folder at all. The test goes on only when it has.
    guard waitForIndex(of: tag) else {
      throw XCTSkip("Spotlight did not index the fixture file in time")
    }

    let app = launch()
    let item = sidebarItem(tag, in: app)
    XCTAssertTrue(item.waitForExistence(timeout: 15), "The tag was not listed")
    item.click()
    waitUntil("The tag is shown") { self.title(app) == tag }
    XCTAssertTrue(
      app.outlines[AccessibilityElement.fileList.identifier].staticTexts["alpha.txt"]
        .waitForExistence(timeout: 10))
  }

  /// Whether `mdfind` finds a file with `tag` within a bound.
  private func waitForIndex(of tag: String, seconds: Int = 20) -> Bool {
    for _ in 0..<seconds {
      let process = Process()
      process.executableURL = URL(filePath: "/usr/bin/mdfind")
      process.arguments = ["kMDItemUserTags == '\(tag)'"]
      let pipe = Pipe()
      process.standardOutput = pipe
      guard (try? process.run()) != nil else { return false }
      process.waitUntilExit()
      let output = pipe.fileHandleForReading.readDataToEndOfFile()
      if !output.isEmpty { return true }
      Thread.sleep(forTimeInterval: 1)
    }
    return false
  }
}
