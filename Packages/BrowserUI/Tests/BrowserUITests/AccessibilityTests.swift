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

  @Test func theToolbarButtonsAreDeclared() {
    #expect(AccessibilityElement.all.contains(.backButton))
    #expect(AccessibilityElement.all.contains(.forwardButton))
  }

  @Test func theTabBarsControlsAreDeclared() {
    for element: AccessibilityElement in [.tabBar, .tab, .closeTabButton, .newTabButton] {
      #expect(AccessibilityElement.all.contains(element))
    }
  }

  @Test func applyingAnElementForASubjectNamesTheSubjectInTheLabel() {
    let button = NSButton(title: "", target: nil, action: nil)
    button.apply(.closeTabButton, for: "Documents")
    #expect(button.identifier?.rawValue == "close-tab")
    #expect(button.accessibilityIdentifier() == "close-tab")
    #expect(button.accessibilityLabel() == "Close Tab Documents")

    // Applied again when the subject's name changes.
    button.apply(.closeTabButton, for: "Sub")
    #expect(button.accessibilityLabel() == "Close Tab Sub")
  }

  @Test func aToolbarItemHoldsAButtonThatTakesItsIdentityFromTheElement() throws {
    let element = AccessibilityElement(identifier: "sample-button", label: "Sample")
    #expect(element.toolbarItemIdentifier.rawValue == "sample-button")

    let item = NSToolbarItem(element, symbolName: "chevron.left")
    #expect(item.itemIdentifier == element.toolbarItemIdentifier)
    #expect(item.label == "Sample")
    #expect(item.paletteLabel == "Sample")

    // The identity is on a real button, as AppKit reports it to VoiceOver and to tests.
    let button = try #require(item.view as? NSButton)
    #expect(button.accessibilityIdentifier() == "sample-button")
    #expect(button.accessibilityLabel() == "Sample")
    #expect(button.bezelStyle == .toolbar)
    #expect(button.imagePosition == .imageOnly)
    #expect(button.image?.accessibilityDescription == "Sample")
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

  @Test func aPaneWithTwoTabsUsesDeclaredElementsForEveryControl() throws {
    let folder = URL(filePath: "/fixture/folder", directoryHint: .isDirectory)
    let pane = PaneViewController(location: folder, reader: StubReader(results: [folder: []]))
    _ = pane.view
    pane.newTab(nil)
    let declared = Set(AccessibilityElement.all.map(\.identifier))

    var found: [String] = []
    func visit(_ view: NSView) {
      let identifier = view.accessibilityIdentifier()
      if !identifier.isEmpty { found.append(identifier) }
      for subview in view.subviews { visit(subview) }
    }
    visit(pane.view)

    // The bar's controls and the showing tab's browser, and nothing from the other tab.
    for identifier in ["tab-bar", "new-tab", "browser-view", "file-list", "browser-status"] {
      #expect(found.filter { $0 == identifier }.count == 1, "\(identifier)")
    }
    for identifier in ["tab", "close-tab"] {
      #expect(found.filter { $0 == identifier }.count == 2, "\(identifier)")
    }
    for identifier in found where !identifier.hasPrefix("_") {
      #expect(
        declared.contains(identifier), "\(identifier) is not declared in AccessibilityElement")
    }
  }
}
