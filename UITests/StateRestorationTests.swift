import BrowserUI
import Darwin
import TestSupport
import XCTest

/// End-to-end tests of state restoration (Phase 1A step 10): a window is
/// built, the app is killed (not quit, so only the save on change can have
/// kept anything), and the next launch brings it back.
///
/// Each test names a defaults suite for the saved state, so these tests never
/// read or change the person's. A first launch has no `-OpenFolder`, because
/// that argument makes a launch ignore saved state.
final class StateRestorationTests: XCTestCase {
  private static let bundleID = "com.mjmcport.cairn"
  private var tree: FixtureTree!
  private var suite: String!

  override func setUpWithError() throws {
    continueAfterFailure = false
    suite = "cairn.uitests.state.\(UUID().uuidString)"
    tree = try FixtureTree.build {
      FixtureNode.file("alpha.txt")
      FixtureNode.directory("Sub") {
        FixtureNode.file("inner.txt")
        FixtureNode.directory("Deeper") {
          FixtureNode.file("leaf.txt")
        }
      }
    }
  }

  override func tearDownWithError() throws {
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    try tree?.remove()
  }

  @MainActor
  private func launch(openFolder: String? = nil) -> XCUIApplication {
    let app = XCUIApplication()
    var arguments = ["-ApplePersistenceIgnoreState", "YES", "-StateSuite", suite!]
    if let openFolder { arguments += ["-OpenFolder", openFolder] }
    app.launchArguments = arguments
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }
    XCTAssertTrue(
      app.windows[AccessibilityElement.mainWindow.identifier].waitForExistence(timeout: 10),
      "The window did not open")
    return app
  }

  /// Ends the app the way a crash does: no quit, no flush.
  @MainActor
  private func kill(_ app: XCUIApplication) {
    // The save happens 0.5 s after the last change. Waiting past it proves
    // the save on change, not the one at quit.
    Thread.sleep(forTimeInterval: 1.5)
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
    XCTAssertEqual(running.count, 1, "Expected one running Cairn")
    // forceTerminate sends SIGKILL: the app gets no chance to run its quit.
    let pid = running.first?.processIdentifier ?? 0
    XCTAssertEqual(Darwin.kill(pid, SIGKILL), 0, "The app could not be killed: \(errno)")
    // Let the system finish with the process before another launch.
    Thread.sleep(forTimeInterval: 1)
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

  @MainActor
  private func goToFolder(_ path: String, in app: XCUIApplication, expecting title: String) {
    app.typeKey("g", modifierFlags: [.command, .shift])
    let field = app.textFields[AccessibilityElement.goToFolderField.identifier]
    XCTAssertTrue(field.waitForExistence(timeout: 10), "The sheet did not open")
    field.typeKey("a", modifierFlags: .command)
    field.typeText(path + "\r")
    waitUntil("\(title) shown") { self.title(app) == title }
  }

  @MainActor
  private func tabs(_ app: XCUIApplication) -> XCUIElementQuery {
    app.tabGroups[AccessibilityElement.tabBar.identifier].tabs.matching(
      identifier: AccessibilityElement.tab.identifier)
  }

  @MainActor
  func testTabsViewAndShowingTabComeBackAfterACrash() throws {
    let app = launch()
    let rootName = tree.root.lastPathComponent
    goToFolder(tree.root.path, in: app, expecting: rootName)

    app.typeKey("t", modifierFlags: .command)
    waitUntil("Two tabs") { self.tabs(app).count == 2 }
    goToFolder(tree.path("Sub"), in: app, expecting: "Sub")
    app.typeKey("2", modifierFlags: .command)
    XCTAssertTrue(
      app.collectionViews[AccessibilityElement.iconView.identifier].waitForExistence(timeout: 10),
      "Icons did not show")
    kill(app)

    let again = launch()
    waitUntil("Two tabs again") { self.tabs(again).count == 2 }
    XCTAssertEqual(tabs(again).allElementsBoundByIndex.map(\.title), [rootName, "Sub"])
    XCTAssertEqual(tabs(again).allElementsBoundByIndex.map(\.isSelected), [false, true])
    XCTAssertEqual(title(again), "Sub")
    let icons = again.collectionViews[AccessibilityElement.iconView.identifier]
    XCTAssertTrue(icons.waitForExistence(timeout: 10), "The tab did not come back in icons")
    // A cell is one element that speaks the item's name and kind.
    let cell = icons.groups.matching(
      NSPredicate(
        format: "identifier == %@ AND label BEGINSWITH %@",
        AccessibilityElement.iconCell.identifier, "inner.txt,")
    ).firstMatch
    XCTAssertTrue(cell.waitForExistence(timeout: 10), "Sub was not listed")
  }

  @MainActor
  func testAFolderRemovedSinceShowsItsNearestAncestorWithNoError() throws {
    let app = launch()
    goToFolder(tree.path("Sub/Deeper"), in: app, expecting: "Deeper")
    kill(app)

    try FileManager.default.removeItem(at: tree.root.appending(path: "Sub/Deeper"))

    let again = launch()
    waitUntil("The nearest folder that exists shows") { self.title(again) == "Sub" }
    XCTAssertTrue(
      again.outlines[AccessibilityElement.fileList.identifier].staticTexts["inner.txt"]
        .waitForExistence(timeout: 10), "Sub was not listed")
    XCTAssertFalse(
      again.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'error'")).firstMatch
        .exists, "An error showed")
  }

  @MainActor
  func testALaunchWithOpenFolderIgnoresTheSavedStateAndLeavesIt() throws {
    let app = launch()
    goToFolder(tree.path("Sub"), in: app, expecting: "Sub")
    kill(app)

    let named = launch(openFolder: tree.root.path)
    waitUntil("The named folder shows") { self.title(named) == self.tree.root.lastPathComponent }
    named.terminate()

    let third = launch()
    waitUntil("The saved folder is still the one saved") { self.title(third) == "Sub" }
  }
}
