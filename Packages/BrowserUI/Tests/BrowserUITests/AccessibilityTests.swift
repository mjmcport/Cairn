import AppKit
import Foundation
import Testing

@testable import BrowserUI

@Suite @MainActor struct AccessibilityTests {
  @Test func everyDeclaredElementHasAUniqueIdentifierAndALabel() {
    let identifiers = AccessibilityElement.all.map(\.identifier)
    #expect(Set(identifiers).count == identifiers.count)
    for element in AccessibilityElement.all {
      #expect(!element.identifier.isEmpty)
      #expect(!element.label.trimmingCharacters(in: .whitespaces).isEmpty)
      // Identifiers are test hooks: lowercase words joined by hyphens.
      #expect(element.identifier.wholeMatch(of: /[a-z]+(-[a-z]+)*/) != nil)
    }
  }

  @Test func applyingAnElementSetsIdentifierAndLabelTogether() {
    let view = NSView()
    view.apply(.fileList)
    #expect(view.identifier?.rawValue == "file-list")
    #expect(view.accessibilityIdentifier() == "file-list")
    #expect(view.accessibilityLabel() == "Files")
  }

  @Test func applyingOnlyTheIdentifierLeavesTheSpokenTextAlone() {
    let label = NSTextField(labelWithString: "notes.txt")
    label.applyIdentifier(of: .nameCell)
    #expect(label.accessibilityIdentifier() == "name-text")
    #expect(label.accessibilityLabel() != "Name")
  }

  @Test func aWindowTakesItsIdentifierFromTheElement() {
    let window = NSWindow()
    window.apply(.mainWindow)
    #expect(window.identifier?.rawValue == "main-window")
    #expect(window.accessibilityIdentifier() == "main-window")
  }

  @Test func theBrowserUsesDeclaredElementsForEveryControl() throws {
    let folder = URL(filePath: "/fixture/folder", directoryHint: .isDirectory)
    let controller = BrowserViewController(
      location: folder, reader: StubReader(results: [folder: []]))
    let declared = Set(AccessibilityElement.all.map(\.identifier))

    var found: [String] = []
    func visit(_ view: NSView) {
      let identifier = view.accessibilityIdentifier()
      if !identifier.isEmpty { found.append(identifier) }
      for subview in view.subviews { visit(subview) }
      if let scrollView = view as? NSScrollView, let document = scrollView.documentView {
        visit(document)
      }
    }
    visit(controller.view)

    #expect(found.contains("file-list"))
    #expect(found.contains("browser-status"))
    // AppKit gives some of its own subviews identifiers (prefixed with an underscore).
    for identifier in found where !identifier.hasPrefix("_") {
      #expect(
        declared.contains(identifier), "\(identifier) is not declared in AccessibilityElement")
    }
  }
}
