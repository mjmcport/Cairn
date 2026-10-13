import BrowserUI
import TestSupport
import XCTest

/// End-to-end tests of the icon presentation (Phase 1A step 6): the same
/// folder, selection and history as the list, drawn as a grid of pictures.
final class IconViewTests: XCTestCase {
  private var tree: FixtureTree!
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    tree = try FixtureTree.build {
      FixtureNode.file("alpha.txt", size: 1_500)
      FixtureNode.file("beta.txt")
      FixtureNode.hiddenFile("secret")
      FixtureNode.directory("Other") {
        FixtureNode.file("other.txt")
      }
      FixtureNode.directory("Sub") {
        FixtureNode.file("inner.txt")
      }
    }
  }

  override func tearDownWithError() throws {
    try tree?.remove()
  }

  @MainActor
  private func launch() -> XCUIElement {
    let app = XCUIApplication()
    app.launchArguments = ["-OpenFolder", tree.root.path, "-ApplePersistenceIgnoreState", "YES"]
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }
    self.app = app
    let outline = app.outlines[AccessibilityElement.fileList.identifier]
    XCTAssertTrue(outline.waitForExistence(timeout: 10), "The file list did not appear")
    XCTAssertTrue(outline.staticTexts["Sub"].waitForExistence(timeout: 10))
    return outline
  }

  @MainActor
  private var icons: XCUIElement {
    app.collectionViews[AccessibilityElement.iconView.identifier]
  }

  /// The cell of the item called `name`. A cell is one element that speaks
  /// the item's name and kind, such as "alpha.txt, file".
  @MainActor
  private func cell(_ name: String) -> XCUIElement {
    icons.groups.matching(
      NSPredicate(
        format: "identifier == %@ AND label BEGINSWITH %@",
        AccessibilityElement.iconCell.identifier, "\(name),")
    ).firstMatch
  }

  @MainActor
  private func waitUntil(_ message: String, _ condition: @escaping () -> Bool) {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in condition() }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, message)
  }

  @MainActor
  func testTheFolderIsShownAsIconsAndTheSelectionIsTheListsToo() {
    let outline = launch()
    app.menuBars.menuBarItems["View"].click()
    XCTAssertTrue(app.menuBars.menuItems["as Icons"].exists)
    XCTAssertTrue(app.menuBars.menuItems["as List"].exists)
    app.menuBars.menuItems["as Icons"].click()

    XCTAssertTrue(icons.waitForExistence(timeout: 10), "The icon view did not appear")
    XCTAssertFalse(outline.exists, "The list is still showing")
    // One cell for each visible item, none for the hidden one.
    for name in ["alpha.txt", "beta.txt", "Other", "Sub"] {
      XCTAssertTrue(cell(name).waitForExistence(timeout: 10), "No cell for \(name)")
    }
    XCTAssertFalse(cell(".secret").exists)

    // What is selected here is selected in the list.
    cell("beta.txt").click()
    app.typeKey("1", modifierFlags: .command)
    let list = app.outlines[AccessibilityElement.fileList.identifier]
    XCTAssertTrue(list.waitForExistence(timeout: 10))
    let row = list.outlineRows.containing(.staticText, identifier: "beta.txt").firstMatch
    waitUntil("beta.txt is selected in the list") { row.isSelected }
  }

  @MainActor
  func testAFolderCellIsEnteredAndBackReturnsInIcons() {
    _ = launch()
    app.typeKey("2", modifierFlags: .command)
    XCTAssertTrue(cell("Sub").waitForExistence(timeout: 10))

    cell("Sub").doubleClick()
    XCTAssertTrue(cell("inner.txt").waitForExistence(timeout: 10), "Sub was not entered")
    XCTAssertEqual(app.windows[AccessibilityElement.mainWindow.identifier].title, "Sub")

    app.typeKey("[", modifierFlags: .command)
    XCTAssertTrue(cell("alpha.txt").waitForExistence(timeout: 10))
    XCTAssertTrue(icons.exists, "Back should return in the same presentation")
    XCTAssertEqual(
      app.windows[AccessibilityElement.mainWindow.identifier].title, tree.root.lastPathComponent)
  }

  @MainActor
  func testAFileCellDoesNothingWhenOpened() {
    _ = launch()
    app.typeKey("2", modifierFlags: .command)
    XCTAssertTrue(cell("alpha.txt").waitForExistence(timeout: 10))

    cell("alpha.txt").doubleClick()
    XCTAssertEqual(
      app.windows[AccessibilityElement.mainWindow.identifier].title, tree.root.lastPathComponent)
    XCTAssertTrue(cell("beta.txt").exists)
  }

  @MainActor
  func testTypingSelectsAndTheKeyboardAloneSwitchesMovesAndOpens() {
    _ = launch()
    app.typeKey("2", modifierFlags: .command)
    XCTAssertTrue(cell("Sub").waitForExistence(timeout: 10))

    // Typing selects: back in the list the same row is selected.
    cell("alpha.txt").click()
    app.typeText("su")
    app.typeKey("1", modifierFlags: .command)
    let list = app.outlines[AccessibilityElement.fileList.identifier]
    XCTAssertTrue(list.waitForExistence(timeout: 10))
    let row = list.outlineRows.containing(.staticText, identifier: "Sub").firstMatch
    waitUntil("Sub selected by typing") { row.isSelected }

    // Open with the keyboard.
    app.typeKey("2", modifierFlags: .command)
    XCTAssertTrue(cell("Sub").waitForExistence(timeout: 10))
    app.typeKey("o", modifierFlags: .command)
    XCTAssertTrue(cell("inner.txt").waitForExistence(timeout: 10), "Open should enter Sub")
  }

  @MainActor
  func testAnotherProcessAddingAFileShowsInTheIcons() throws {
    _ = launch()
    app.typeKey("2", modifierFlags: .command)
    XCTAssertTrue(cell("Sub").waitForExistence(timeout: 10))

    try Data().write(to: tree.url("gamma.txt"), options: .withoutOverwriting)
    XCTAssertTrue(cell("gamma.txt").waitForExistence(timeout: 10))
  }
}
