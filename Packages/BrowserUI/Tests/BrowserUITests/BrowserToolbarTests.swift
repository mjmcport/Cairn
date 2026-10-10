import AppKit
import FileSystemCore
import Foundation
import Testing

@testable import BrowserUI

@Suite @MainActor struct BrowserToolbarTests {
  /// The items the toolbar shows by default, without the system's spacing items.
  private func defaultItems() throws -> [NSToolbarItem] {
    let source = BrowserToolbar()
    let toolbar = source.makeToolbar()
    #expect(toolbar.delegate === source)
    let spacing: Set<NSToolbarItem.Identifier> = [.flexibleSpace, .space]
    return try source.toolbarDefaultItemIdentifiers(toolbar)
      .filter { !spacing.contains($0) }
      .map { identifier in
        try #require(
          source.toolbar(
            toolbar, itemForItemIdentifier: identifier, willBeInsertedIntoToolbar: true),
          "No item for \(identifier.rawValue)")
      }
  }

  @Test func everyButtonTakesItsIdentityFromADeclaredElement() throws {
    let items = try defaultItems()
    #expect(items.map(\.itemIdentifier.rawValue) == ["go-back", "go-forward"])
    for item in items {
      let element = try #require(
        AccessibilityElement.all.first { $0.identifier == item.itemIdentifier.rawValue },
        "\(item.itemIdentifier.rawValue) is not declared in AccessibilityElement")
      #expect(item.label == element.label)
      #expect(item.paletteLabel == element.label)

      let button = try #require(item.view as? NSButton)
      #expect(button.accessibilityIdentifier() == element.identifier)
      #expect(button.accessibilityLabel() == element.label)
      #expect(button.image?.accessibilityDescription == element.label)
      #expect(button.toolTip?.isEmpty == false)
    }
  }

  @Test func buttonsSendTheirActionsUpTheResponderChain() throws {
    let items = try defaultItems()
    let actions = [
      #selector(BrowserViewController.goBack(_:)), #selector(BrowserViewController.goForward(_:)),
    ]
    #expect(items.map(\.action) == actions)
    for (item, action) in zip(items, actions) {
      let button = try #require(item.view as? NSButton)
      #expect(button.action == action)
      #expect(button.target == nil)
      // Nothing has validated the button yet, and a new window has no history.
      #expect(!button.isEnabled)

      // The overflow menu and text-only mode show a menu item in the button's place.
      let menuItem = try #require(item.menuFormRepresentation)
      #expect(menuItem.title == item.label)
      #expect(menuItem.action == action)
      #expect(menuItem.target == nil)
    }
  }

  @Test func aButtonWithNothingToHandleItsActionIsDisabled() throws {
    let item = try #require(try defaultItems().first)
    item.isEnabled = true
    item.validate()
    #expect(!item.isEnabled)
  }

  /// A window with the real toolbar over a browser that has gone from one
  /// folder into another, so Back can do something and Forward cannot. The
  /// caller keeps `source` alive: a toolbar does not retain its delegate.
  private func browserWindowWithHistory() async throws -> (
    window: NSWindow, controller: BrowserViewController, source: BrowserToolbar,
    back: NSToolbarItem, forward: NSToolbarItem
  ) {
    let parent = URL(filePath: "/fixture/parent", directoryHint: .isDirectory)
    let child = parent.appending(path: "child", directoryHint: .isDirectory)
    let reader = StubReader(results: [parent: [FileItem(url: child, kind: .directory)], child: []])
    let controller = BrowserViewController(location: parent, reader: reader)
    let window = NSWindow(contentViewController: controller)
    let source = BrowserToolbar()
    window.toolbar = source.makeToolbar()
    await controller.loadTask?.value
    await controller.model.navigate(to: child)
    try #require(controller.model.canGoBack && !controller.model.canGoForward)

    let items = try #require(window.toolbar).items.filter { $0.view is NSButton }
    try #require(items.map(\.itemIdentifier.rawValue) == ["go-back", "go-forward"])
    return (window, controller, source, items[0], items[1])
  }

  @Test func aButtonStaysEnabledWhileKeyboardFocusIsOutsideTheBrowser() async throws {
    let (window, _, source, back, forward) = try await browserWindowWithHistory()
    _ = source
    // With Full Keyboard Access the button itself can have focus, and with
    // nothing focused the window is its own first responder.
    let outsideTheBrowser: [NSResponder?] = [back.view, nil]
    for firstResponder in outsideTheBrowser {
      try #require(window.makeFirstResponder(firstResponder))
      try #require(window.firstResponder === firstResponder ?? window)
      back.isEnabled = false
      forward.isEnabled = true
      back.validate()
      forward.validate()
      #expect(back.isEnabled)
      #expect(!forward.isEnabled)
    }
  }

  @Test func aButtonWhoseViewHasLeftTheWindowIsStillValidatedByTheBrowser() async throws {
    let (_, _, source, back, forward) = try await browserWindowWithHistory()
    _ = source
    // The toolbar takes a button out of the window to show it in the overflow menu.
    for item in [back, forward] {
      item.view?.removeFromSuperview()
      try #require(item.view != nil && item.view?.window == nil)
    }
    back.isEnabled = false
    forward.isEnabled = true
    back.validate()
    forward.validate()
    #expect(back.isEnabled)
    #expect(!forward.isEnabled)
  }

  @Test func withNoApplicationToAskTheWindowsContentIsStillFound() async throws {
    let (window, controller, source, back, _) = try await browserWindowWithHistory()
    _ = source
    let action = try #require(back.action)
    try #require(window.makeFirstResponder(back.view))
    #expect(
      ToolbarButtonItem.handler(of: action, for: back, in: nil) as? NSResponder === controller)

    // The first responder is asked before the content: it is where a click goes.
    let focused = Handler()
    window.contentView?.addSubview(focused)
    try #require(window.makeFirstResponder(focused))
    #expect(ToolbarButtonItem.handler(of: action, for: back, in: nil) as? NSResponder === focused)
  }

  /// What macOS 15 needs: there the application gives no answer for a window
  /// that is not key, and the button's view may not be in the window.
  @Test func withNoApplicationAndNoViewInTheWindowTheToolbarsWindowIsStillFound() async throws {
    let (window, controller, source, back, _) = try await browserWindowWithHistory()
    _ = source
    let action = try #require(back.action)
    back.view?.removeFromSuperview()
    try #require(back.view != nil && back.view?.window == nil)
    #expect(ToolbarButtonItem.window(of: back) === window)
    #expect(
      ToolbarButtonItem.handler(of: action, for: back, in: nil) as? NSResponder === controller)
  }

  @Test func aHandlerThatDoesNotValidateEnablesTheButton() throws {
    let content = NSViewController()
    content.view = Handler()
    let window = NSWindow(contentViewController: content)
    let source = BrowserToolbar()
    window.toolbar = source.makeToolbar()
    let back = try #require(window.toolbar?.items.first { $0.view is NSButton })
    try #require(back.action == #selector(Handler.goBack(_:)))
    try #require(window.makeFirstResponder(content.view))

    back.isEnabled = false
    back.validate()
    #expect(back.isEnabled)
  }

  @Test func aButtonWithKeyboardFocusOffersTheBrowserAsTheTargetOfAnAction() async throws {
    let (_, controller, source, back, _) = try await browserWindowWithHistory()
    _ = source
    let button = try #require(back.view as? NSButton)
    // The button's own action, and one only the Go menu sends.
    for action in [
      #selector(BrowserViewController.goBack(_:)),
      #selector(BrowserViewController.goToEnclosingFolder(_:)),
    ] {
      #expect(
        button.supplementalTarget(forAction: action, sender: nil) as? NSResponder === controller)
    }
    #expect(
      button.supplementalTarget(forAction: #selector(NSText.selectAll(_:)), sender: nil) == nil)
  }

  @Test func aButtonWithKeyboardFocusOffersTheShowingTabsBrowser() async throws {
    let folder = URL(filePath: "/fixture/folder", directoryHint: .isDirectory)
    let pane = PaneViewController(location: folder, reader: StubReader(results: [folder: []]))
    let window = NSWindow(contentViewController: pane)
    let source = BrowserToolbar()
    window.toolbar = source.makeToolbar()
    let button = try #require(window.toolbar?.items.compactMap { $0.view as? NSButton }.first)
    let first = pane.showingBrowser
    pane.newTab(nil)
    let second = pane.showingBrowser
    try #require(second !== first)

    // The pane handles no Go command itself; the button finds the browser it offers.
    let back = #selector(BrowserViewController.goBack(_:))
    #expect(button.supplementalTarget(forAction: back, sender: nil) as? NSResponder === second)
    pane.showPreviousTab(nil)
    #expect(button.supplementalTarget(forAction: back, sender: nil) as? NSResponder === first)
    #expect(
      button.supplementalTarget(forAction: #selector(NSText.selectAll(_:)), sender: nil) == nil)
  }

  /// What macOS 26 needs: there a button is not in the browser's window until
  /// the toolbar has been laid out.
  @Test func aButtonThatIsNotInTheWindowStillOffersTheShowingTabsBrowser() async throws {
    let folder = URL(filePath: "/fixture/folder", directoryHint: .isDirectory)
    let pane = PaneViewController(location: folder, reader: StubReader(results: [folder: []]))
    let window = NSWindow(contentViewController: pane)
    let source = BrowserToolbar()
    window.toolbar = source.makeToolbar()
    let button = try #require(window.toolbar?.items.compactMap { $0.view as? NSButton }.first)
    button.removeFromSuperview()
    try #require(button.window == nil)
    #expect(ToolbarButtonItem.window(holding: button) === window)

    let back = #selector(BrowserViewController.goBack(_:))
    #expect(
      button.supplementalTarget(forAction: back, sender: nil) as? NSResponder
        === pane.showingBrowser)
  }
}

/// A view that handles Back and says nothing about whether it can.
private final class Handler: NSView {
  override var acceptsFirstResponder: Bool { true }
  @objc func goBack(_ sender: Any?) {}
}
