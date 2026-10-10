import AppKit

/// The window toolbar: Back and Forward. Each item holds a real button that
/// sends its action up the responder chain, so it reaches whichever browser
/// has focus. The system does not validate a button in a toolbar, so
/// ``ToolbarButtonItem`` enables it by asking that browser's
/// `validateUserInterfaceItem`, the method the Go menu uses.
@MainActor
public final class BrowserToolbar: NSObject, NSToolbarDelegate {
  public static let identifier = NSToolbar.Identifier("browser-toolbar")
  /// The buttons the toolbar offers, in order.
  static let buttons: [AccessibilityElement] = [.backButton, .forwardButton]

  /// Builds the toolbar. The caller keeps the `BrowserToolbar` alive, because
  /// a toolbar does not retain its delegate.
  public func makeToolbar() -> NSToolbar {
    let toolbar = NSToolbar(identifier: Self.identifier)
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    return toolbar
  }

  public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    Self.buttons.map(\.toolbarItemIdentifier) + [.flexibleSpace]
  }

  public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarDefaultItemIdentifiers(toolbar)
  }

  public func toolbar(
    _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    switch itemIdentifier {
    case AccessibilityElement.backButton.toolbarItemIdentifier:
      Self.makeItem(
        .backButton, symbolName: "chevron.left", toolTip: "Show the previous folder",
        action: #selector(BrowserViewController.goBack(_:)))
    case AccessibilityElement.forwardButton.toolbarItemIdentifier:
      Self.makeItem(
        .forwardButton, symbolName: "chevron.right", toolTip: "Show the next folder",
        action: #selector(BrowserViewController.goForward(_:)))
    default:
      nil
    }
  }

  private static func makeItem(
    _ element: AccessibilityElement, symbolName: String, toolTip: String, action: Selector
  ) -> NSToolbarItem {
    // The element gives the button its identifier and the label VoiceOver speaks.
    let item = ToolbarButtonItem(element, symbolName: symbolName)
    item.toolTip = toolTip
    // The item does not pass its tooltip on to the button, which is what the
    // pointer rests on.
    item.view?.toolTip = toolTip
    // No target: the action travels the responder chain. An item passes its
    // target and action on to the button it holds.
    item.target = nil
    item.action = action
    // Disabled until a browser says otherwise: a new window has no history.
    item.isEnabled = false
    // What stands in for the button in the overflow menu and in text-only
    // mode. The system validates a menu item itself.
    item.menuFormRepresentation = NSMenuItem(
      title: element.label, action: action, keyEquivalent: "")
    return item
  }
}

/// A toolbar item that holds a button and keeps it enabled only while its
/// action can do something.
///
/// The system validates a standard item through the responder chain but
/// leaves an item with a view alone, so this item does the same work in
/// `validate()`. The toolbar calls that as the window updates, and
/// `BrowserViewController` calls it whenever its model changes.
final class ToolbarButtonItem: NSToolbarItem {
  override func validate() {
    guard let action, let handler = Self.handler(of: action, for: self, in: NSApp) else {
      isEnabled = false
      return
    }
    let validator = handler as? any NSUserInterfaceValidations
    isEnabled = validator?.validateUserInterfaceItem(self) ?? true
  }

  /// The object a click on the item's button would reach.
  ///
  /// The application is asked first, because it is what delivers the click,
  /// so the button is enabled exactly when a click would arrive somewhere.
  /// Walking up from the first responder of the button's own window is not
  /// the same question: it finds nothing when the button has keyboard focus,
  /// and nothing when the button's view is out of the window, as it is while
  /// the toolbar shows the item in its overflow menu.
  ///
  /// The application does not always answer. On macOS 15 it gives nothing
  /// for an item whose window is not key or main, where macOS 26 and 27 find
  /// the item's window themselves. The item's window is then searched from
  /// its first responder, and from its content view controller when the
  /// first responder is outside the content.
  ///
  /// - Parameter application: `nil` to skip the application and search the
  ///   item's window only.
  static func handler(
    of action: Selector, for item: NSToolbarItem, in application: NSApplication?
  ) -> Any? {
    if let target = application?.target(forAction: action, to: nil, from: item) {
      return target
    }
    let window = window(of: item)
    return responder(to: action, from: window?.firstResponder)
      ?? responder(to: action, from: window?.contentViewController)
  }

  /// The window whose toolbar holds the item.
  ///
  /// The item's view is only in that window while the toolbar is showing the
  /// button: not before the toolbar is first laid out, and not while the item
  /// is in the overflow menu. A toolbar does not say which window it belongs
  /// to, so the windows are asked which of them has this toolbar.
  static func window(of item: NSToolbarItem) -> NSWindow? {
    if let window = item.view?.window { return window }
    guard let toolbar = item.toolbar else { return nil }
    return NSApplication.shared.windows.first { $0.toolbar === toolbar }
  }

  /// The first responder that implements an action, from `start` upward.
  static func responder(to action: Selector, from start: NSResponder?) -> NSResponder? {
    var responder = start
    while let candidate = responder {
      if candidate.responds(to: action) { return candidate }
      responder = candidate.nextResponder
    }
    return nil
  }
}

/// The button a toolbar item holds.
///
/// With Full Keyboard Access a toolbar button can take keyboard focus. Its
/// responder chain runs up the title bar to the window and never passes the
/// browser, so an action sent while it has focus, its own or a Go menu
/// item's, reaches the browser only if something offers it. The button
/// offers whatever in the window's content handles the action. On macOS 27
/// the window makes the same offer itself; that was not checked on macOS 15
/// or 26, and the button does not depend on it.
final class ToolbarButton: NSButton {
  override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
    ToolbarButtonItem.responder(to: action, from: window?.contentViewController)
      ?? super.supplementalTarget(forAction: action, sender: sender)
  }
}
