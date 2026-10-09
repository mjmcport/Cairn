import BrowserUI
import TestSupport
import XCTest

/// Quality bar 9: the system's accessibility audit passes on every screen,
/// and everything can be done from the keyboard.
final class AccessibilityTests: XCTestCase {
  private var tree: FixtureTree!

  override func setUpWithError() throws {
    continueAfterFailure = false
    tree = try FixtureTree.build {
      FixtureNode.file("alpha.txt", size: 1_500)
      FixtureNode.file("beta.txt")
      FixtureNode.directory("Sub") {
        FixtureNode.file("inner.txt")
      }
      FixtureNode.directory("Empty")
    }
  }

  override func tearDownWithError() throws {
    try tree?.remove()
  }

  @MainActor
  private func launch(on path: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-OpenFolder", path, "-ApplePersistenceIgnoreState", "YES"]
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }
    return app
  }

  /// Runs the system accessibility audit and fails on every issue it reports,
  /// with two exceptions:
  ///
  /// - The Touch Bar, which the system owns and the app does not populate.
  /// - "Label not human-readable" on a list cell that shows text. The cell
  ///   speaks a file name, such as `alpha.txt`, which is the user's own data
  ///   and the correct thing to say even though it is not a dictionary word.
  @MainActor
  private func audit(_ app: XCUIApplication, _ screen: String) throws {
    do {
      try runAudit(app, screen)
    } catch let error as NSError where error.code == Self.auditTimedOut {
      // Seen about once in ten runs on the development Mac: the audit itself
      // times out without reporting an issue. One announced retry; a second
      // timeout fails the test. Tracked in docs/solutions (accessibility notes).
      XCTContext.runActivity(named: "Accessibility audit timed out on \(screen); retrying once") {
        _ in
      }
      try runAudit(app, screen)
    }
  }

  /// The code XCTest uses for "Audit failed to complete in time".
  private static let auditTimedOut = -56

  @MainActor
  private func runAudit(_ app: XCUIApplication, _ screen: String) throws {
    try app.performAccessibilityAudit { issue in
      guard let element = issue.element else {
        XCTFail("\(screen): \(issue.compactDescription)")
        return true
      }
      if element.elementType == .touchBar { return true }
      if issue.auditType == .sufficientElementDescription, element.elementType == .cell,
        let text = element.staticTexts.firstMatch.value as? String, !text.isEmpty
      {
        return true
      }
      XCTFail(
        "\(screen): \(issue.compactDescription) [type \(element.elementType.rawValue), "
          + "id '\(element.identifier)', label '\(element.label)'] \(issue.detailedDescription)")
      return true
    }
  }

  @MainActor
  func testAuditPassesOnAPopulatedFolder() throws {
    let app = launch(on: tree.root.path)
    let table = app.tables[AccessibilityElement.fileList.identifier]
    XCTAssertTrue(table.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    XCTAssertEqual(table.label, AccessibilityElement.fileList.label)
    try audit(app, "Populated folder")
  }

  @MainActor
  func testAuditPassesOnAnEmptyFolder() throws {
    let app = launch(on: tree.path("Empty"))
    let status = app.staticTexts[AccessibilityElement.browserStatus.identifier]
    XCTAssertTrue(status.waitForExistence(timeout: 10))
    XCTAssertEqual(status.value as? String, "This folder is empty.")
    try audit(app, "Empty folder")
  }

  @MainActor
  func testAuditPassesWhenAFolderCannotBeListed() throws {
    let app = launch(on: tree.path("missing"))
    let status = app.staticTexts[AccessibilityElement.browserStatus.identifier]
    XCTAssertTrue(status.waitForExistence(timeout: 10))
    try audit(app, "Unlistable folder")
  }

  @MainActor
  func testAFolderCanBeOpenedAndLeftWithTheKeyboardAlone() {
    let app = launch(on: tree.root.path)
    let table = app.tables[AccessibilityElement.fileList.identifier]
    let window = app.windows[AccessibilityElement.mainWindow.identifier]
    XCTAssertTrue(table.staticTexts["Sub"].waitForExistence(timeout: 10))

    // The list has keyboard focus at launch. Rows are alpha.txt, beta.txt, Empty, Sub.
    for _ in 0..<4 {
      app.typeKey(.downArrow, modifierFlags: [])
    }
    app.typeKey("o", modifierFlags: .command)
    XCTAssertTrue(table.staticTexts["inner.txt"].waitForExistence(timeout: 10))
    XCTAssertEqual(window.title, "Sub")

    app.typeKey(.upArrow, modifierFlags: .command)
    XCTAssertTrue(table.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    XCTAssertEqual(window.title, tree.root.lastPathComponent)
  }
}
