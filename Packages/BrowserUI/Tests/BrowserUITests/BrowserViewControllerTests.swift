import AppKit
import Foundation
import Testing

@testable import BrowserUI

@Suite @MainActor struct BrowserViewControllerTests {
  @Test func holdsItsLocationAndLoadsAnIdentifiedView() {
    let location = URL(filePath: "/tmp", directoryHint: .isDirectory)
    let controller = BrowserViewController(location: location)

    #expect(controller.location == location)
    #expect(controller.view.identifier?.rawValue == "browser-view")
  }
}
