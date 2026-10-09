import TestSupport
import XCTest

/// Time to first rows in a large folder (quality bar 4), measured from the
/// app's own `LoadFolder` signpost interval: from the request to load until
/// the list has been given its rows.
///
/// Run with `make perf`. `make uitest` skips this class.
final class PerformanceTests: XCTestCase {
  private var tree: FixtureTree!

  override func setUpWithError() throws {
    continueAfterFailure = false
    tree = try FixtureTree.build {
      FixtureNode.files(count: 10_000, in: "Items10000")
    }
  }

  override func tearDownWithError() throws {
    try tree?.remove()
  }

  @MainActor
  func testTimeToFirstRows10000() {
    let app = XCUIApplication()
    app.launchArguments = ["-OpenFolder", tree.root.path, "-ApplePersistenceIgnoreState", "YES"]
    app.launch()
    addTeardownBlock { @MainActor in app.terminate() }

    let table = app.tables["file-list"]
    let folder = table.staticTexts["Items10000"]
    XCTAssertTrue(folder.waitForExistence(timeout: 10))

    let loadFolder = XCTOSSignpostMetric(
      subsystem: "com.mjmcport.cairn", category: "performance", name: "LoadFolder")
    let options = XCTMeasureOptions()
    options.iterationCount = 5
    options.invocationOptions = [.manuallyStart, .manuallyStop]

    measure(metrics: [loadFolder], options: options) {
      startMeasuring()
      folder.doubleClick()
      XCTAssertTrue(table.staticTexts["file-000000.txt"].waitForExistence(timeout: 30))
      stopMeasuring()

      app.typeKey(.upArrow, modifierFlags: .command)
      XCTAssertTrue(folder.waitForExistence(timeout: 30))
    }
  }
}
