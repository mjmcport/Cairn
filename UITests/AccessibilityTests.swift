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
  /// with three exceptions:
  ///
  /// - The Touch Bar, which the system owns and the app does not populate.
  /// - "Parent/Child mismatch" on a group inside a window title-bar button.
  ///   macOS 26 reports the zoom button's inner group; the system draws it.
  /// - "Contrast failed" on a text that, measured from its own screenshot, has
  ///   the contrast WCAG asks for: its most contrasting pixel against its most
  ///   common one. On the runners (a 1x screen) the system's estimate of the
  ///   color of thin anti-aliased text, such as the name `Empty`, falls below
  ///   4.5:1 for text that is #272727 on white, about 14.6:1. Text that is
  ///   really too light still fails, because its darkest pixel is light.
  /// - "Label not human-readable" on a list cell that shows text. The cell
  ///   speaks a file name, such as `alpha.txt`, which is the user's own data
  ///   and the correct thing to say even though it is not a dictionary word.
  @MainActor
  private func audit(_ app: XCUIApplication, _ screen: String) throws {
    // Every audit and every retry is recorded, so CI can show and gate the
    // retry rate (CONTRIBUTING.md, "The accessibility audit's one retry").
    let log = AuditLog()
    log.recordAudit(screen: screen)
    do {
      try runAudit(app, screen)
    } catch let error as NSError where error.code == Self.auditTimedOut {
      // Seen about once in ten runs on the development Mac: the audit itself
      // times out without reporting an issue. One announced retry; a second
      // timeout fails the test. Tracked in docs/solutions (accessibility notes).
      log.recordRetry(screen: screen)
      XCTContext.runActivity(named: "Accessibility audit timed out on \(screen); retrying once") {
        _ in
      }
      try runAudit(app, screen)
    }
  }

  /// WCAG's ratio for normal text.
  private static let requiredContrast = 4.5

  /// The pixels of an element's screenshot counted by color, as 0xRRGGBB.
  @MainActor
  private static func histogram(of element: XCUIElement) -> [UInt32: Int]? {
    guard element.exists,
      let image = element.screenshot().image.cgImage(
        forProposedRect: nil, context: nil, hints: nil)
    else { return nil }
    let width = image.width
    let height = image.height
    var data = [UInt8](repeating: 0, count: width * height * 4)
    guard
      let context = CGContext(
        data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var counts: [UInt32: Int] = [:]
    for index in stride(from: 0, to: data.count, by: 4) {
      let key = UInt32(data[index]) << 16 | UInt32(data[index + 1]) << 8 | UInt32(data[index + 2])
      counts[key, default: 0] += 1
    }
    return counts
  }

  /// The most common colors in an element's screenshot, as `RRGGBB x pixels`:
  /// what the audit sees when it judges the element's contrast.
  @MainActor
  private static func colors(of element: XCUIElement) -> String {
    guard let counts = histogram(of: element) else { return "no image" }
    let top = counts.sorted { $0.value > $1.value }.prefix(4)
      .map { String(format: "%06X x%d", $0.key, $0.value) }
    return top.joined(separator: ", ")
  }

  /// The WCAG contrast ratio between the most common color of an element's
  /// screenshot, taken to be its background, and the color in it that
  /// contrasts with that most. Anti-aliasing only ever lightens a glyph's
  /// pixels, so the strongest one is the text's own color.
  /// - Returns: nil when there is no image.
  @MainActor
  private static func measuredContrast(of element: XCUIElement) -> Double? {
    guard let counts = histogram(of: element),
      let background = counts.max(by: { $0.value < $1.value })?.key
    else { return nil }
    func luminance(_ color: UInt32) -> Double {
      func channel(_ value: UInt32) -> Double {
        let c = Double(value) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
      }
      return 0.2126 * channel(color >> 16 & 0xFF) + 0.7152 * channel(color >> 8 & 0xFF)
        + 0.0722 * channel(color & 0xFF)
    }
    let backgroundLuminance = luminance(background)
    return counts.keys.map { color in
      let other = luminance(color)
      let (light, dark) = (max(other, backgroundLuminance), min(other, backgroundLuminance))
      return (light + 0.05) / (dark + 0.05)
    }.max()
  }

  /// The code XCTest uses for "Audit failed to complete in time".
  private static let auditTimedOut = -56

  @MainActor
  private func runAudit(_ app: XCUIApplication, _ screen: String) throws {
    // The close, minimize and zoom buttons, which the system draws.
    let windowButtons = app.windows.buttons
      .matching(NSPredicate(format: "identifier BEGINSWITH '_XCUI:'"))
      .allElementsBoundByIndex.map(\.frame)
    try app.performAccessibilityAudit { issue in
      guard let element = issue.element else {
        XCTFail("\(screen): \(issue.compactDescription)")
        return true
      }
      if element.elementType == .touchBar { return true }
      if issue.auditType == .parentChild, element.elementType == .group,
        windowButtons.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(element.frame) })
      {
        return true
      }
      if issue.auditType == .contrast, element.elementType == .staticText,
        let ratio = Self.measuredContrast(of: element), ratio >= Self.requiredContrast
      {
        return true
      }
      if issue.auditType == .sufficientElementDescription, element.elementType == .cell,
        let text = element.staticTexts.firstMatch.value as? String, !text.isEmpty
      {
        return true
      }
      let windowFrame = app.windows[AccessibilityElement.mainWindow.identifier].frame
      let outline = app.outlines[AccessibilityElement.fileList.identifier]
      let neighbours = ["alpha.txt", "Sub"].map {
        "\($0): " + Self.colors(of: outline.staticTexts[$0])
      }.joined(separator: "; ")
      XCTFail(
        "\(screen): \(issue.compactDescription) [type \(element.elementType.rawValue), "
          + "id '\(element.identifier)', label '\(element.label)'] \(issue.detailedDescription)"
          + " | colors \(Self.colors(of: element)) | \(neighbours)"
          + " | frame \(element.frame) in window \(windowFrame)"
          + " | \(String(element.debugDescription.prefix(500)))")
      return true
    }
  }

  @MainActor
  func testAuditPassesOnAPopulatedFolder() throws {
    let app = launch(on: tree.root.path)
    let table = app.outlines[AccessibilityElement.fileList.identifier]
    XCTAssertTrue(table.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    XCTAssertEqual(table.label, AccessibilityElement.fileList.label)
    // Every column is inside the window, the last included: a column cut off
    // by the window's edge fails the contrast audit on the CI runners.
    let window = app.windows[AccessibilityElement.mainWindow.identifier]
    let added = table.staticTexts.matching(identifier: "added-text").firstMatch
    XCTAssertTrue(added.waitForExistence(timeout: 10))
    XCTAssertLessThanOrEqual(added.frame.maxX, window.frame.maxX)
    try audit(app, "Populated folder")
  }

  @MainActor
  func testAuditPassesWithAFolderOpenInPlace() throws {
    let app = launch(on: tree.root.path)
    let outline = app.outlines[AccessibilityElement.fileList.identifier]
    let sub = outline.outlineRows.containing(.staticText, identifier: "Sub").firstMatch
    XCTAssertTrue(sub.waitForExistence(timeout: 10))
    sub.disclosureTriangles.firstMatch.click()
    XCTAssertTrue(outline.staticTexts["inner.txt"].waitForExistence(timeout: 10))
    try audit(app, "Folder open in place")
  }

  @MainActor
  func testAuditPassesWithTheFolderShownAsIcons() throws {
    let app = launch(on: tree.root.path)
    XCTAssertTrue(
      app.outlines[AccessibilityElement.fileList.identifier].staticTexts["alpha.txt"]
        .waitForExistence(timeout: 10))
    app.typeKey("2", modifierFlags: .command)
    let icons = app.collectionViews[AccessibilityElement.iconView.identifier]
    XCTAssertTrue(icons.waitForExistence(timeout: 10))
    XCTAssertEqual(icons.label, AccessibilityElement.iconView.label)
    // A cell is one element that speaks the name and kind of its item.
    let cell = icons.groups.matching(
      NSPredicate(format: "label == %@", "alpha.txt, file")
    ).firstMatch
    XCTAssertTrue(cell.waitForExistence(timeout: 10))
    try audit(app, "Icon view")
  }

  @MainActor
  func testAuditPassesOnTheSettingsWindowAndItsCheckboxIsFoundByIdentifier() throws {
    let app = launch(on: tree.root.path)
    XCTAssertTrue(
      app.outlines[AccessibilityElement.fileList.identifier].waitForExistence(timeout: 10))
    app.typeKey(",", modifierFlags: .command)
    let window = app.windows[AccessibilityElement.settingsWindow.identifier]
    XCTAssertTrue(window.waitForExistence(timeout: 10), "Settings did not open")
    XCTAssertEqual(window.title, "Settings")
    let toggle = window.checkBoxes[AccessibilityElement.rememberOpenFoldersToggle.identifier]
    XCTAssertTrue(toggle.exists)
    XCTAssertEqual(toggle.label, AccessibilityElement.rememberOpenFoldersToggle.label)
    // The main window overlaps Settings and is drawn dimmer behind it, so it
    // is closed first and the audit sees the Settings window alone. The app
    // stays running with no window.
    app.windows[AccessibilityElement.mainWindow.identifier].buttons[XCUIIdentifierCloseWindow]
      .click()
    XCTAssertFalse(app.windows[AccessibilityElement.mainWindow.identifier].exists)
    try audit(app, "Settings window")
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
    let table = app.outlines[AccessibilityElement.fileList.identifier]
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

  /// The tab bar, which exists only while there are two or more tabs.
  @MainActor
  private func tabBar(_ app: XCUIApplication) -> XCUIElement {
    app.tabGroups[AccessibilityElement.tabBar.identifier]
  }

  @MainActor
  func testAuditPassesWithTwoTabs() throws {
    // Both tabs are titled "Sub": the audit reads a tab's title as its name.
    let app = launch(on: tree.path("Sub"))
    let table = app.outlines[AccessibilityElement.fileList.identifier]
    XCTAssertTrue(table.staticTexts["inner.txt"].waitForExistence(timeout: 10))

    app.typeKey("t", modifierFlags: .command)
    let bar = tabBar(app)
    XCTAssertTrue(bar.waitForExistence(timeout: 10))
    XCTAssertEqual(bar.label, AccessibilityElement.tabBar.label)
    let tabs = bar.tabs.matching(identifier: AccessibilityElement.tab.identifier)
    XCTAssertEqual(tabs.allElementsBoundByIndex.map(\.title), ["Sub", "Sub"])
    XCTAssertEqual(tabs.allElementsBoundByIndex.map(\.isSelected), [false, true])
    try audit(app, "Two tabs")
  }

  @MainActor
  func testTabsCanBeOpenedSwitchedAndClosedWithTheKeyboardAlone() {
    let app = launch(on: tree.root.path)
    let table = app.outlines[AccessibilityElement.fileList.identifier]
    let window = app.windows[AccessibilityElement.mainWindow.identifier]
    let bar = tabBar(app)
    XCTAssertTrue(table.staticTexts["Sub"].waitForExistence(timeout: 10))

    // A new tab takes keyboard focus in its list. Rows are alpha.txt, beta.txt, Empty, Sub.
    app.typeKey("t", modifierFlags: .command)
    XCTAssertTrue(bar.waitForExistence(timeout: 10))
    XCTAssertTrue(table.staticTexts["Sub"].waitForExistence(timeout: 10))
    for _ in 0..<4 {
      app.typeKey(.downArrow, modifierFlags: [])
    }
    app.typeKey("o", modifierFlags: .command)
    XCTAssertTrue(table.staticTexts["inner.txt"].waitForExistence(timeout: 10))
    XCTAssertEqual(window.title, "Sub")

    // Control-Tab shows tab 1 with focus in its list: Down Arrow selects its first row.
    app.typeKey(.tab, modifierFlags: .control)
    XCTAssertTrue(table.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    app.typeKey(.downArrow, modifierFlags: [])
    XCTAssertTrue(
      table.outlineRows.containing(.staticText, identifier: "alpha.txt").firstMatch.isSelected)

    // Command-W closes tab 1. Tab 2 is left, where it was, and takes the keyboard.
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(table.staticTexts["inner.txt"].waitForExistence(timeout: 10))
    XCTAssertFalse(bar.exists)
    app.typeKey(.upArrow, modifierFlags: .command)
    XCTAssertTrue(table.staticTexts["alpha.txt"].waitForExistence(timeout: 10))
    XCTAssertEqual(window.title, tree.root.lastPathComponent)
  }
}
