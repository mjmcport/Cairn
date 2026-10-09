import BrowserUI
import TestSupport
import XCTest

/// End-to-end tests of the walking skeleton: the app opens on a folder given
/// at launch, lists it and navigates into a subfolder.
final class BrowsingTests: XCTestCase {
  private var tree: FixtureTree!
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    tree = try FixtureTree.build {
      FixtureNode.file("alpha.txt", size: 1_500)
      FixtureNode.file("beta.txt")
      FixtureNode.hiddenFile("secret")
      FixtureNode.directory("Sub") {
        FixtureNode.file("inner.txt")
      }
    }
  }

  override func tearDownWithError() throws {
    try tree?.remove()
  }

  /// Launches the app with the given arguments and quits it when the test ends.
  @MainActor
  private func launchApp(arguments: [String]) {
    let app = XCUIApplication()
    app.launchArguments = arguments + ["-ApplePersistenceIgnoreState", "YES"]
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }
    self.app = app
  }

  @MainActor
  private func launch(on folder: URL) -> XCUIElement {
    launchApp(arguments: ["-OpenFolder", folder.path])
    let table = app.tables[AccessibilityElement.fileList.identifier]
    XCTAssertTrue(table.waitForExistence(timeout: 10), "The file list did not appear")
    return table
  }

  @MainActor
  private func waitForRowCount(_ count: Int, in table: XCUIElement, _ message: String) {
    let matches = NSPredicate { _, _ in table.tableRows.count == count }
    let expectation = XCTNSPredicateExpectation(predicate: matches, object: nil)
    let result = XCTWaiter.wait(for: [expectation], timeout: 10)
    XCTAssertEqual(result, .completed, "\(message): found \(table.tableRows.count) rows")
  }

  @MainActor
  func testListsTheLaunchFolderWithoutHiddenFiles() {
    let table = launch(on: tree.root)

    waitForRowCount(3, in: table, "Expected alpha.txt, beta.txt and Sub")
    XCTAssertTrue(table.staticTexts["alpha.txt"].exists)
    XCTAssertTrue(table.staticTexts["beta.txt"].exists)
    XCTAssertTrue(table.staticTexts["Sub"].exists)
    XCTAssertFalse(table.staticTexts[".secret"].exists)
    XCTAssertEqual(
      app.windows[AccessibilityElement.mainWindow.identifier].title, tree.root.lastPathComponent)
  }

  @MainActor
  func testDoubleClickOpensASubfolderAndCommandUpReturns() {
    let table = launch(on: tree.root)
    waitForRowCount(3, in: table, "Expected three rows before navigating")

    table.staticTexts["Sub"].doubleClick()
    waitForRowCount(1, in: table, "Expected only inner.txt inside Sub")
    XCTAssertTrue(table.staticTexts["inner.txt"].exists)
    XCTAssertEqual(app.windows[AccessibilityElement.mainWindow.identifier].title, "Sub")

    app.typeKey(.upArrow, modifierFlags: .command)
    waitForRowCount(3, in: table, "Expected three rows after returning")
    XCTAssertEqual(
      app.windows[AccessibilityElement.mainWindow.identifier].title, tree.root.lastPathComponent)
  }

  @MainActor
  func testDoubleClickingAFileDoesNotNavigate() {
    let table = launch(on: tree.root)
    waitForRowCount(3, in: table, "Expected three rows")

    table.staticTexts["alpha.txt"].doubleClick()
    waitForRowCount(3, in: table, "A file must not navigate")
    XCTAssertEqual(
      app.windows[AccessibilityElement.mainWindow.identifier].title, tree.root.lastPathComponent)
  }

  @MainActor
  func testAMissingFolderShowsWhyItCouldNotBeListed() {
    launchApp(arguments: ["-OpenFolder", tree.path("does-not-exist")])

    let status = app.staticTexts[AccessibilityElement.browserStatus.identifier]
    XCTAssertTrue(status.waitForExistence(timeout: 10), "No explanation was shown")
    XCTAssertFalse((status.value as? String ?? "").isEmpty)
    XCTAssertEqual(app.tables[AccessibilityElement.fileList.identifier].tableRows.count, 0)
  }
}
