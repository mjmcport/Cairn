import AppKit
import BrowserUI
import TestSupport
import XCTest

/// End-to-end tests of the path bar, Go to Folder and Copy Path (Phase 1A
/// step 9).
final class PathBarTests: XCTestCase {
  private var tree: FixtureTree!
  private var suite: String!

  override func setUpWithError() throws {
    continueAfterFailure = false
    suite = "cairn.uitests.favorites.\(UUID().uuidString)"
    tree = try FixtureTree.build {
      FixtureNode.file("alpha.txt")
      FixtureNode.directory("Sub") {
        FixtureNode.file("inner.txt")
        FixtureNode.directory("Deeper")
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
  private func crumb(_ name: String, in app: XCUIApplication) -> XCUIElement {
    app.buttons.matching(identifier: AccessibilityElement.pathCrumb.identifier)
      .matching(NSPredicate(format: "label == %@", "Folder \(name)")).firstMatch
  }

  @MainActor
  func testTheBarShowsThePathAndANameGoesThere() throws {
    let app = launch()
    let root = tree.root.lastPathComponent
    XCTAssertTrue(crumb(root, in: app).waitForExistence(timeout: 10), "The bar has no name")

    // Enter Sub from the list; the bar gains a name.
    app.outlines[AccessibilityElement.fileList.identifier].outlineRows
      .containing(.staticText, identifier: "Sub").firstMatch.doubleClick()
    waitUntil("Sub shown") { self.title(app) == "Sub" }
    XCTAssertTrue(crumb("Sub", in: app).waitForExistence(timeout: 10))

    // A click on the earlier name goes back there as one step.
    crumb(root, in: app).click()
    waitUntil("Back at the fixture") { self.title(app) == root }
    XCTAssertTrue(
      app.outlines[AccessibilityElement.fileList.identifier].staticTexts["alpha.txt"]
        .waitForExistence(timeout: 10))
    app.typeKey("[", modifierFlags: .command)
    waitUntil("Back returns to Sub") { self.title(app) == "Sub" }
  }

  @MainActor
  func testGoToFolderTakesATypedPath() throws {
    let app = launch()
    app.typeKey("g", modifierFlags: [.command, .shift])
    let field = app.textFields[AccessibilityElement.goToFolderField.identifier]
    XCTAssertTrue(field.waitForExistence(timeout: 10), "The sheet did not open")
    XCTAssertEqual(field.label, AccessibilityElement.goToFolderField.label)

    field.typeKey("a", modifierFlags: .command)
    field.typeText(tree.root.path + "/Su")
    let suggestions = app.tables[AccessibilityElement.goToFolderSuggestions.identifier]
    XCTAssertTrue(suggestions.staticTexts["Sub"].waitForExistence(timeout: 10))
    field.typeText("b\r")
    waitUntil("Sub shown") { self.title(app) == "Sub" }
    XCTAssertTrue(
      app.outlines[AccessibilityElement.fileList.identifier].staticTexts["inner.txt"]
        .waitForExistence(timeout: 10))
  }

  @MainActor
  func testCopyPathPutsThePathOnThePasteboard() throws {
    let app = launch()
    app.outlines[AccessibilityElement.fileList.identifier].outlineRows
      .containing(.staticText, identifier: "Sub").firstMatch.click()
    app.menuBars.menuBarItems["Edit"].click()
    app.menuBars.menuItems["Copy Path"].click()
    app.menuBars.menuItems["Path"].click()
    let expected = tree.root.appending(path: "Sub").path
    waitUntil("The path was copied") {
      NSPasteboard.general.string(forType: .string) == expected
    }
  }
}
