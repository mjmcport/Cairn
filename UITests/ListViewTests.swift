import BrowserUI
import TestSupport
import XCTest

/// End-to-end tests of the list as an outline (Phase 1A step 5): folders that
/// open in place and follow changes made by another process, columns that
/// sort, Keep Folders on Top, typing to select, and what Back and Forward
/// open again.
///
/// The runner changes the fixture from outside the app, which is another
/// process to it, and shares the temporary folder with it.
final class ListViewTests: XCTestCase {
  private var tree: FixtureTree!
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    tree = try FixtureTree.build {
      FixtureNode.file("alpha.txt", size: 1_500)
      FixtureNode.file("beta.txt")
      FixtureNode.file("big.bin", size: 90_000)
      FixtureNode.directory("Other") {
        FixtureNode.file("other.txt")
      }
      FixtureNode.directory("Sub") {
        FixtureNode.file("inner.txt")
        FixtureNode.directory("Deep") {
          FixtureNode.file("deepest.txt")
        }
      }
    }
  }

  override func tearDownWithError() throws {
    try tree?.remove()
  }

  @MainActor
  private func launch(extraArguments: [String] = []) -> XCUIElement {
    let app = XCUIApplication()
    app.launchArguments =
      ["-OpenFolder", tree.root.path, "-ApplePersistenceIgnoreState", "YES"] + extraArguments
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }
    self.app = app
    let outline = app.outlines[AccessibilityElement.fileList.identifier]
    XCTAssertTrue(outline.waitForExistence(timeout: 10), "The file list did not appear")
    XCTAssertTrue(outline.staticTexts["Sub"].waitForExistence(timeout: 10))
    return outline
  }

  /// The names in the first column of every row, top to bottom.
  @MainActor
  private func names(in outline: XCUIElement) -> [String] {
    outline.outlineRows.allElementsBoundByIndex.map {
      $0.staticTexts.allElementsBoundByIndex.first?.value as? String ?? "?"
    }
  }

  @MainActor
  private func waitForNames(
    _ expected: [String], in outline: XCUIElement, _ message: String
  ) {
    let matches = NSPredicate { _, _ in self.names(in: outline) == expected }
    let result = XCTWaiter.wait(
      for: [XCTNSPredicateExpectation(predicate: matches, object: nil)], timeout: 10)
    XCTAssertEqual(result, .completed, "\(message): found \(names(in: outline))")
  }

  @MainActor
  private func row(_ name: String, in outline: XCUIElement) -> XCUIElement {
    outline.outlineRows.containing(.staticText, identifier: name).firstMatch
  }

  @MainActor
  private func waitUntil(_ message: String, _ condition: @escaping () -> Bool) {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in condition() }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, message)
  }

  // MARK: Opening in place, sorting and typing

  @MainActor
  func testFoldersOpenInPlaceFollowChangesSortAndSelectByTyping() throws {
    let outline = launch()
    waitForNames(
      ["alpha.txt", "beta.txt", "big.bin", "Other", "Sub"], in: outline, "The launch folder")

    // A folder opens by its triangle, in the same window, with nothing moved.
    row("Sub", in: outline).disclosureTriangles.firstMatch.click()
    waitForNames(
      ["alpha.txt", "beta.txt", "big.bin", "Other", "Sub", "Deep", "inner.txt"], in: outline,
      "Sub opened in place")
    XCTAssertEqual(
      app.windows[AccessibilityElement.mainWindow.identifier].title, tree.root.lastPathComponent)

    // Right Arrow opens the selected folder and Left Arrow closes it.
    row("Deep", in: outline).click()
    app.typeKey(.rightArrow, modifierFlags: [])
    XCTAssertTrue(outline.staticTexts["deepest.txt"].waitForExistence(timeout: 10))
    app.typeKey(.leftArrow, modifierFlags: [])
    waitUntil("Deep closed") { !outline.staticTexts["deepest.txt"].exists }

    // Another process adds a file inside the open folder: it appears there.
    try Data().write(
      to: tree.url("Sub").appending(path: "added.txt"), options: .withoutOverwriting)
    XCTAssertTrue(outline.staticTexts["added.txt"].waitForExistence(timeout: 10))
    XCTAssertTrue(outline.staticTexts["Sub"].exists, "The folder stayed open and in place")

    // A header sorts every level; again reverses it.
    app.buttons["Size"].click()
    waitUntil("Sorted by size, smallest first") {
      let rows = self.names(in: outline)
      return rows.last == "big.bin"
    }
    app.buttons["Size"].click()
    waitUntil("Sorted by size, largest first") { self.names(in: outline).first == "big.bin" }
    app.buttons["Name"].click()
    waitUntil("Sorted by name again") { self.names(in: outline).first == "alpha.txt" }

    // Keep Folders on Top groups the folders at both levels.
    app.menuBars.menuBarItems["View"].click()
    app.menuBars.menuItems["Keep Folders on Top"].click()
    waitForNames(
      ["Other", "Sub", "Deep", "added.txt", "inner.txt", "alpha.txt", "beta.txt", "big.bin"],
      in: outline, "Folders first at every level")
    app.menuBars.menuBarItems["View"].click()
    app.menuBars.menuItems["Keep Folders on Top"].click()
    waitUntil("Folders back in name order") { self.names(in: outline).first == "alpha.txt" }

    // Typing selects the row whose name starts with it.
    row("alpha.txt", in: outline).click()
    app.typeText("be")
    waitUntil("beta.txt selected by typing") { self.row("beta.txt", in: outline).isSelected }
  }

  @MainActor
  func testOpenOnAFolderInsideAnOpenFolderEntersItAndLeavesTheOutlineClosed() {
    let outline = launch()
    row("Sub", in: outline).disclosureTriangles.firstMatch.click()
    XCTAssertTrue(outline.staticTexts["Deep"].waitForExistence(timeout: 10))

    row("Deep", in: outline).click()
    app.typeKey("o", modifierFlags: .command)
    waitForNames(["deepest.txt"], in: outline, "Entered Deep as a move")
    XCTAssertEqual(app.windows[AccessibilityElement.mainWindow.identifier].title, "Deep")
  }

  // MARK: What Back and Forward open again

  @MainActor
  func testBackOpensTheFoldersAgainAndTheSettingTurnsThatOff() throws {
    let outline = launch()
    func openSubThenGoToOtherAndBack() {
      row("Sub", in: outline).disclosureTriangles.firstMatch.click()
      XCTAssertTrue(outline.staticTexts["inner.txt"].waitForExistence(timeout: 10))
      outline.staticTexts["Other"].doubleClick()
      XCTAssertTrue(outline.staticTexts["other.txt"].waitForExistence(timeout: 10))
      app.typeKey("[", modifierFlags: .command)
      XCTAssertTrue(outline.staticTexts["Sub"].waitForExistence(timeout: 10))
    }

    // On by default: Sub is open again.
    openSubThenGoToOtherAndBack()
    XCTAssertTrue(
      outline.staticTexts["inner.txt"].waitForExistence(timeout: 10),
      "Back should open Sub again")

    // The checkbox in Settings is on, and turning it off makes Back leave Sub closed.
    app.typeKey(",", modifierFlags: .command)
    let toggle = app.checkBoxes[AccessibilityElement.rememberOpenFoldersToggle.identifier]
    XCTAssertTrue(toggle.waitForExistence(timeout: 10), "The setting was not in Settings")
    // Whatever happens next, leave the setting as it was found.
    addTeardownBlock { @MainActor in
      if (toggle.value as? Int) == 0 || (toggle.value as? String) == "0" { toggle.click() }
    }
    XCTAssertEqual(toggle.value as? Int ?? Int(toggle.value as? String ?? ""), 1)
    toggle.click()
    XCTAssertEqual(toggle.value as? Int ?? Int(toggle.value as? String ?? ""), 0)
    app.typeKey("w", modifierFlags: .command)

    // The main window is still showing Sub, open. Away and back: closed now.
    outline.staticTexts["Other"].doubleClick()
    XCTAssertTrue(outline.staticTexts["other.txt"].waitForExistence(timeout: 10))
    app.typeKey("[", modifierFlags: .command)
    XCTAssertTrue(outline.staticTexts["Sub"].waitForExistence(timeout: 10))
    waitUntil("Sub closed with the setting off") { !outline.staticTexts["inner.txt"].exists }

    // Back to on, so the next test and the user find it as it was.
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    toggle.click()
    XCTAssertEqual(toggle.value as? Int ?? Int(toggle.value as? String ?? ""), 1)
  }
}
