import BrowserUI
import TestSupport
import XCTest

/// End-to-end tests of browsing: the app opens on a folder given at launch,
/// lists it, navigates into a subfolder, and settles a large folder.
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

  /// A folder larger than the reader's first batch of 2,000 items reaches the
  /// list twice: its first rows as they were read, then the sorted list with
  /// the selection restored (Phase 1A step 3). Only the first two rows are
  /// asked for, so nothing off screen is.
  @MainActor
  func testALargeFolderSettlesIntoSortedOrderAndRestoresTheSelection() throws {
    let large = try FixtureTree.build {
      // Sorts ahead of every file.
      FixtureNode.directory("Before") {
        FixtureNode.file("inside.txt")
      }
      for index in 0..<3_000 {
        FixtureNode.file(FixtureNames.numbered(index))
      }
    }
    addTeardownBlock { try? large.remove() }

    let table = launch(on: large.root)
    let first = table.tableRows.element(boundBy: 0)
    let second = table.tableRows.element(boundBy: 1)
    XCTAssertTrue(
      first.staticTexts["Before"].waitForExistence(timeout: 30),
      "The list did not settle with the folder first")
    XCTAssertTrue(
      second.staticTexts["file-000000.txt"].waitForExistence(timeout: 30),
      "The list did not settle with the first file second")

    // Opening the folder by double-click leaves it selected in the history.
    first.staticTexts["Before"].doubleClick()
    XCTAssertTrue(table.staticTexts["inside.txt"].waitForExistence(timeout: 10))

    app.typeKey("[", modifierFlags: .command)
    // The selection is restored when the list settles, not in the first rows.
    let restored = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in first.isSelected }, object: nil)
    XCTAssertEqual(
      XCTWaiter.wait(for: [restored], timeout: 30), .completed,
      "The first row was not selected after going back")
    XCTAssertTrue(first.staticTexts["Before"].exists)
    XCTAssertTrue(second.staticTexts["file-000000.txt"].exists)
    XCTAssertFalse(second.isSelected)
  }
}
