import BrowserUI
import TestSupport
import XCTest

/// End-to-end tests of browsing: the app opens on a folder given at launch,
/// lists it, navigates into a subfolder, settles a large folder, and follows
/// changes that another process makes to the folder it is showing.
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
    let table = app.outlines[AccessibilityElement.fileList.identifier]
    XCTAssertTrue(table.waitForExistence(timeout: 10), "The file list did not appear")
    return table
  }

  @MainActor
  private func waitForRowCount(_ count: Int, in table: XCUIElement, _ message: String) {
    let matches = NSPredicate { _, _ in table.outlineRows.count == count }
    let expectation = XCTNSPredicateExpectation(predicate: matches, object: nil)
    let result = XCTWaiter.wait(for: [expectation], timeout: 10)
    XCTAssertEqual(result, .completed, "\(message): found \(table.outlineRows.count) rows")
  }

  @MainActor
  private func row(_ name: String, in table: XCUIElement) -> XCUIElement {
    table.outlineRows.containing(.staticText, identifier: name).firstMatch
  }

  @MainActor
  private func waitUntil(_ message: String, _ condition: @escaping () -> Bool) {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in condition() }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, message)
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
    XCTAssertEqual(app.outlines[AccessibilityElement.fileList.identifier].outlineRows.count, 0)
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
    let first = table.outlineRows.element(boundBy: 0)
    let second = table.outlineRows.element(boundBy: 1)
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

  /// The list follows the disk (Phase 1A step 4). The test runner is another
  /// process to the app and changes the fixture under it. One launch: it ends
  /// with a folder gone, so nothing else can share it.
  @MainActor
  func testChangesMadeByAnotherProcessShowInTheListAndKeepTheSelection() throws {
    let table = launch(on: tree.root)
    waitForRowCount(3, in: table, "Expected alpha.txt, beta.txt and Sub")
    table.staticTexts["beta.txt"].click()
    XCTAssertTrue(row("beta.txt", in: table).isSelected)

    // Created.
    try Data().write(to: tree.url("gamma.txt"), options: .withoutOverwriting)
    waitForRowCount(4, in: table, "gamma.txt did not appear")
    XCTAssertTrue(table.staticTexts["gamma.txt"].exists)
    XCTAssertTrue(row("beta.txt", in: table).isSelected)

    // Renamed.
    try FileManager.default.moveItem(at: tree.url("alpha.txt"), to: tree.url("delta.txt"))
    XCTAssertTrue(
      table.staticTexts["delta.txt"].waitForExistence(timeout: 10), "The new name did not appear")
    XCTAssertFalse(table.staticTexts["alpha.txt"].exists)
    XCTAssertTrue(row("beta.txt", in: table).isSelected)

    // Deleted.
    try FileManager.default.removeItem(at: tree.url("gamma.txt"))
    waitForRowCount(3, in: table, "gamma.txt did not go away")

    // Modified: the file's size is shown, so it changes.
    let size = row("beta.txt", in: table).staticTexts.matching(
      identifier: AccessibilityElement.sizeCell.identifier
    ).firstMatch
    let sizeBefore = try XCTUnwrap(size.value as? String)
    let handle = try FileHandle(forWritingTo: tree.url("beta.txt"))
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(repeating: 0x61, count: 5_000))
    try handle.close()
    waitUntil("The size of beta.txt did not change from \(sizeBefore)") {
      (size.value as? String) != sizeBefore
    }
    XCTAssertTrue(row("beta.txt", in: table).isSelected)

    // The folder being shown goes away: the reason is shown, as for a folder
    // that could not be listed, and Back still works.
    table.staticTexts["Sub"].doubleClick()
    XCTAssertTrue(table.staticTexts["inner.txt"].waitForExistence(timeout: 10))
    try FileManager.default.removeItem(at: tree.url("Sub"))
    let status = app.staticTexts[AccessibilityElement.browserStatus.identifier]
    waitUntil("No reason was shown for the folder that went away") {
      let text = status.exists ? (status.value as? String ?? "") : ""
      return !text.isEmpty && text != "This folder is empty."
    }
    waitForRowCount(0, in: table, "The rows of the folder that went away were not cleared")

    app.typeKey("[", modifierFlags: .command)
    waitForRowCount(2, in: table, "Expected beta.txt and delta.txt after going back")
    XCTAssertTrue(table.staticTexts["beta.txt"].exists)
    XCTAssertTrue(table.staticTexts["delta.txt"].exists)
  }
}
