import AppKit

/// The accessibility identity of one control: a stable identifier that tests
/// find it by, and the label VoiceOver speaks.
///
/// Declare every element here, in ``all``, and apply it with
/// `view.apply(_:)`. Setting an identifier or a label any other way is
/// rejected by `scripts/check-accessibility.sh`, so a control cannot gain a
/// test hook without also gaining a spoken name.
public struct AccessibilityElement: Sendable, Hashable {
  /// Stable, unique, never localized. UI tests query by this.
  public let identifier: String
  /// What VoiceOver speaks. Localized when the app is.
  public let label: String

  public init(identifier: String, label: String) {
    self.identifier = identifier
    self.label = label
  }
}

extension AccessibilityElement {
  public static let mainWindow = AccessibilityElement(
    identifier: "main-window", label: "Cairn")
  public static let browserView = AccessibilityElement(
    identifier: "browser-view", label: "Browser")
  public static let fileList = AccessibilityElement(
    identifier: "file-list", label: "Files")
  public static let browserStatus = AccessibilityElement(
    identifier: "browser-status", label: "Folder status")
  public static let nameCell = AccessibilityElement(
    identifier: "name-text", label: "Name")
  public static let sizeCell = AccessibilityElement(
    identifier: "size-text", label: "Size")
  public static let modifiedCell = AccessibilityElement(
    identifier: "modified-text", label: "Date Modified")

  /// Every element the app declares. Tests check that identifiers are unique
  /// and labels are present.
  public static let all: [AccessibilityElement] = [
    .mainWindow, .browserView, .fileList, .browserStatus, .nameCell, .sizeCell, .modifiedCell,
  ]
}

extension NSView {
  /// Gives the view its identifier and spoken label together.
  public func apply(_ element: AccessibilityElement) {
    identifier = NSUserInterfaceItemIdentifier(element.identifier)
    setAccessibilityIdentifier(element.identifier)
    setAccessibilityLabel(element.label)
  }

  /// Gives a view that shows changing text (a cell, a status line) its
  /// identifier only. VoiceOver speaks the text itself, so a fixed label
  /// would hide it.
  public func applyIdentifier(of element: AccessibilityElement) {
    identifier = NSUserInterfaceItemIdentifier(element.identifier)
    setAccessibilityIdentifier(element.identifier)
  }
}

extension NSView {
  /// Overrides what VoiceOver speaks for a view that shows changing text,
  /// for text that is not words, such as the dashes shown for a missing
  /// size. Pass `nil` to go back to speaking the visible text.
  public func setSpokenText(_ text: String?) {
    setAccessibilityLabel(text)
  }
}

extension NSWindow {
  /// Gives the window its identifier. A window's spoken name is its title,
  /// which the browser sets to the folder name.
  public func apply(_ element: AccessibilityElement) {
    identifier = NSUserInterfaceItemIdentifier(element.identifier)
    setAccessibilityIdentifier(element.identifier)
  }
}
