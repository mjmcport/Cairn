import BrowserUI
import TestSupport
import XCTest

/// End-to-end tests of the column presentation (Phase 1A step 7): the same
/// folder, selection and history as the other presentations, as columns with a
/// preview.
final class ColumnViewTests: XCTestCase {
  private var tree: FixtureTree!
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    tree = try FixtureTree.build {
      FixtureNode.file("alpha.txt", size: 1_500)
      FixtureNode.hiddenFile("secret")
      FixtureNode.directory("Other") {
        FixtureNode.file("other.txt")
      }
      FixtureNode.directory("Sub") {
        FixtureNode.file("inner.txt", size: 900)
        FixtureNode.file("second.txt")
      }
    }
  }

  override func tearDownWithError() throws {
    try tree?.remove()
  }

  @MainActor
  private func launchInColumns() -> XCUIElement {
    let app = XCUIApplication()
    app.launchArguments = ["-OpenFolder", tree.root.path, "-ApplePersistenceIgnoreState", "YES"]
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }
    self.app = app
    XCTAssertTrue(
      app.outlines[AccessibilityElement.fileList.identifier].waitForExistence(timeout: 10),
      "The file list did not appear")
    app.typeKey("3", modifierFlags: .command)
    let browser = app.browsers[AccessibilityElement.columnBrowser.identifier]
    XCTAssertTrue(browser.waitForExistence(timeout: 10), "The columns did not appear")
    return browser
  }

  /// The entry called `name` in any column. Entries are text fields whose
  /// value is the name.
  @MainActor
  private func entry(_ name: String, in browser: XCUIElement) -> XCUIElement {
    browser.textFields.matching(NSPredicate(format: "value == %@", name)).firstMatch
  }

  @MainActor
  private func waitUntil(_ message: String, _ condition: @escaping () -> Bool) {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in condition() }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, message)
  }

  @MainActor
  func testSelectingFoldersOpensColumnsAndAFileShowsItsPreview() {
    let browser = launchInColumns()
    for name in ["alpha.txt", "Other", "Sub"] {
      XCTAssertTrue(entry(name, in: browser).waitForExistence(timeout: 10), "No \(name)")
    }
    XCTAssertFalse(entry(".secret", in: browser).exists)
    XCTAssertFalse(
      app.outlines[AccessibilityElement.fileList.identifier].exists, "The list is still showing")

    // A folder selected shows its contents in the next column.
    entry("Sub", in: browser).click()
    XCTAssertTrue(entry("inner.txt", in: browser).waitForExistence(timeout: 10))
    XCTAssertEqual(
      app.windows[AccessibilityElement.mainWindow.identifier].title, tree.root.lastPathComponent)

    // A file selected shows its preview.
    entry("inner.txt", in: browser).click()
    let name = app.staticTexts[AccessibilityElement.previewName.identifier]
    XCTAssertTrue(name.waitForExistence(timeout: 10), "No preview")
    XCTAssertEqual(name.value as? String, "inner.txt")
    let facts = app.staticTexts.matching(identifier: AccessibilityElement.previewFact.identifier)
      .allElementsBoundByIndex.compactMap { $0.value as? String }
    XCTAssertTrue(facts.contains { $0.hasPrefix("Kind: ") }, "Facts: \(facts)")
    XCTAssertTrue(facts.contains { $0.hasPrefix("Size: ") }, "Facts: \(facts)")

    // Another folder replaces the first one's column.
    entry("Other", in: browser).click()
    XCTAssertTrue(entry("other.txt", in: browser).waitForExistence(timeout: 10))
    waitUntil("Sub's column went") { !self.entry("inner.txt", in: browser).exists }
  }

  @MainActor
  func testTheArrowKeysMoveBetweenColumnsAndOpenEntersAFolder() {
    let browser = launchInColumns()
    entry("Sub", in: browser).click()
    XCTAssertTrue(entry("inner.txt", in: browser).waitForExistence(timeout: 10))

    // Right goes into the folder's column and selects its first entry.
    app.typeKey(.rightArrow, modifierFlags: [])
    let name = app.staticTexts[AccessibilityElement.previewName.identifier]
    XCTAssertTrue(name.waitForExistence(timeout: 10), "Right should select a file and preview it")
    // Left goes back to the folder, which hides the preview.
    app.typeKey(.leftArrow, modifierFlags: [])
    waitUntil("the preview went") { !name.exists }

    // Open enters the selected folder as a move; the columns start again.
    app.typeKey("o", modifierFlags: .command)
    waitUntil("Sub was entered") {
      self.app.windows[AccessibilityElement.mainWindow.identifier].title == "Sub"
    }
    XCTAssertTrue(entry("inner.txt", in: browser).waitForExistence(timeout: 10))
    app.typeKey("[", modifierFlags: .command)
    XCTAssertTrue(entry("alpha.txt", in: browser).waitForExistence(timeout: 10))
  }

  @MainActor
  func testAnotherProcessAddingAFileShowsInTheOpenColumn() throws {
    let browser = launchInColumns()
    entry("Sub", in: browser).click()
    XCTAssertTrue(entry("inner.txt", in: browser).waitForExistence(timeout: 10))

    try Data().write(
      to: tree.url("Sub").appending(path: "added.txt"), options: .withoutOverwriting)
    XCTAssertTrue(entry("added.txt", in: browser).waitForExistence(timeout: 10))
    XCTAssertTrue(entry("inner.txt", in: browser).exists)
  }

  @MainActor
  func testSwitchingKeepsTheSelectionBetweenColumnsAndTheList() {
    let browser = launchInColumns()
    entry("Sub", in: browser).click()
    XCTAssertTrue(entry("second.txt", in: browser).waitForExistence(timeout: 10))
    entry("second.txt", in: browser).click()

    app.typeKey("1", modifierFlags: .command)
    let list = app.outlines[AccessibilityElement.fileList.identifier]
    XCTAssertTrue(list.waitForExistence(timeout: 10))
    // The folder that leads to it is open in the list, and the file is selected.
    let row = list.outlineRows.containing(.staticText, identifier: "second.txt").firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10), "Sub should be open in the list")
    waitUntil("second.txt selected in the list") { row.isSelected }
  }
}
