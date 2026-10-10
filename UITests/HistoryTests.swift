import BrowserUI
import TestSupport
import XCTest

/// End-to-end tests of back and forward (Phase 1A step 1).
final class HistoryTests: XCTestCase {
  private var tree: FixtureTree!

  override func setUpWithError() throws {
    continueAfterFailure = false
    tree = try FixtureTree.build {
      FixtureNode.file("alpha.txt")
      FixtureNode.directory("Sub") {
        FixtureNode.file("inner.txt")
        FixtureNode.directory("Deeper") {
          FixtureNode.file("deepest.txt")
        }
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
    let table = app.tables[AccessibilityElement.fileList.identifier]
    XCTAssertTrue(table.staticTexts["Sub"].waitForExistence(timeout: 10))
    return (app, table, app.windows[AccessibilityElement.mainWindow.identifier])
  }

  @MainActor
  private func row(_ name: String, in table: XCUIElement) -> XCUIElement {
    table.tableRows.containing(.staticText, identifier: name).firstMatch
  }

  /// Opens the Go menu, reads which of its items are enabled and closes it.
  /// A menu validates its items as it opens, so a closed menu's state is stale.
  @MainActor
  private func enabledGoMenuItems(_ app: XCUIApplication) -> Set<String> {
    let menu = app.menuBars.menuBarItems["Go"]
    menu.click()
    var enabled: Set<String> = []
    for title in ["Back", "Forward", "Enclosing Folder"] {
      let item = menu.menuItems[title]
      XCTAssertTrue(item.waitForExistence(timeout: 10), "Go > \(title) is missing")
      if item.isEnabled { enabled.insert(title) }
    }
    app.typeKey(.escape, modifierFlags: [])
    return enabled
  }

  @MainActor
  func testBackAndForwardWithTheKeyboard() {
    let (app, table, window) = launch()

    table.staticTexts["Sub"].doubleClick()
    XCTAssertTrue(table.staticTexts["Deeper"].waitForExistence(timeout: 10))
    table.staticTexts["Deeper"].doubleClick()
    XCTAssertTrue(table.staticTexts["deepest.txt"].waitForExistence(timeout: 10))
    XCTAssertEqual(window.title, "Deeper")

    app.typeKey("[", modifierFlags: .command)
    XCTAssertTrue(table.staticTexts["inner.txt"].waitForExistence(timeout: 10))
    XCTAssertEqual(window.title, "Sub")

    app.typeKey("[", modifierFlags: .command)
    XCTAssertTrue(table.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    XCTAssertEqual(window.title, tree.root.lastPathComponent)

    app.typeKey("]", modifierFlags: .command)
    XCTAssertTrue(table.staticTexts["inner.txt"].waitForExistence(timeout: 10))
    app.typeKey("]", modifierFlags: .command)
    XCTAssertTrue(table.staticTexts["deepest.txt"].waitForExistence(timeout: 10))
    XCTAssertEqual(window.title, "Deeper")
  }

  @MainActor
  func testToolbarButtonsAreEnabledOnlyWhenThereIsHistory() {
    let (app, table, window) = launch()
    XCTAssertEqual(enabledGoMenuItems(app), ["Enclosing Folder"])

    // With no history, Back from the keyboard leaves the folder showing.
    app.typeKey("[", modifierFlags: .command)
    XCTAssertTrue(table.staticTexts["alpha.txt"].exists)
    XCTAssertTrue(table.staticTexts["Sub"].exists)
    XCTAssertEqual(window.title, tree.root.lastPathComponent)

    let back = app.toolbars.buttons.matching(
      identifier: AccessibilityElement.backButton.identifier
    ).firstMatch
    let forward = app.toolbars.buttons.matching(
      identifier: AccessibilityElement.forwardButton.identifier
    ).firstMatch
    XCTAssertTrue(back.waitForExistence(timeout: 10))
    XCTAssertEqual(back.identifier, AccessibilityElement.backButton.identifier)
    XCTAssertEqual(forward.identifier, AccessibilityElement.forwardButton.identifier)
    XCTAssertEqual(back.label, AccessibilityElement.backButton.label)
    XCTAssertEqual(forward.label, AccessibilityElement.forwardButton.label)
    XCTAssertFalse(back.isEnabled)
    XCTAssertFalse(forward.isEnabled)

    table.staticTexts["Sub"].doubleClick()
    XCTAssertTrue(table.staticTexts["inner.txt"].waitForExistence(timeout: 10))
    XCTAssertTrue(back.isEnabled)
    XCTAssertFalse(forward.isEnabled)
    XCTAssertEqual(enabledGoMenuItems(app), ["Back", "Enclosing Folder"])

    back.click()
    XCTAssertTrue(table.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    XCTAssertFalse(back.isEnabled)
    XCTAssertTrue(forward.isEnabled)
    XCTAssertEqual(enabledGoMenuItems(app), ["Forward", "Enclosing Folder"])

    forward.click()
    XCTAssertTrue(table.staticTexts["inner.txt"].waitForExistence(timeout: 10))
    XCTAssertTrue(back.isEnabled)
  }

  @MainActor
  func testGoingBackRestoresTheSelection() {
    let (app, table, _) = launch()

    // Opening Sub by double-click leaves it selected in the parent's history.
    table.staticTexts["Sub"].doubleClick()
    XCTAssertTrue(table.staticTexts["inner.txt"].waitForExistence(timeout: 10))

    app.typeKey("[", modifierFlags: .command)
    XCTAssertTrue(table.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    XCTAssertTrue(row("Sub", in: table).isSelected)
    XCTAssertFalse(row("alpha.txt", in: table).isSelected)
  }

  @MainActor
  func testEnclosingFolderSelectsTheFolderJustLeft() {
    let app = XCUIApplication()
    app.launchArguments = [
      "-OpenFolder", tree.path("Sub/Deeper"), "-ApplePersistenceIgnoreState", "YES",
    ]
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }
    let table = app.tables[AccessibilityElement.fileList.identifier]
    XCTAssertTrue(table.staticTexts["deepest.txt"].waitForExistence(timeout: 10))

    app.typeKey(.upArrow, modifierFlags: .command)
    XCTAssertTrue(table.staticTexts["inner.txt"].waitForExistence(timeout: 10))
    XCTAssertTrue(row("Deeper", in: table).isSelected)
  }
}
