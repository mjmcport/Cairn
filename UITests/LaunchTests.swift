import XCTest

/// End-to-end smoke test: the built app launches and shows its window.
final class LaunchTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testLaunchShowsMainWindow() {
    let app = XCUIApplication()
    app.launch()

    let window = app.windows["main-window"]
    XCTAssertTrue(window.waitForExistence(timeout: 10), "The main window did not appear")
    XCTAssertEqual(window.title, "Cairn")

    app.terminate()
  }
}
