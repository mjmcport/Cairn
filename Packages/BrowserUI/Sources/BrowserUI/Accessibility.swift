import AppKit
import SwiftUI

/// The accessibility identity of one control: a stable identifier that tests
/// find it by, and the label VoiceOver speaks.
///
/// Declare every element here, in ``all``, and apply it with
/// `view.apply(_:)` or `view.apply(_:for:)`, or build a toolbar button from
/// it with `NSToolbarItem(_:symbolName:)`. Setting an identifier or a label any other
/// way is rejected by `scripts/check-accessibility.sh`, so a control cannot
/// gain a test hook without also gaining a spoken name.
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
  public static let sizeOnDiskCell = AccessibilityElement(
    identifier: "size-on-disk-text", label: "Size on Disk")
  public static let modifiedCell = AccessibilityElement(
    identifier: "modified-text", label: "Date Modified")
  public static let addedCell = AccessibilityElement(
    identifier: "added-text", label: "Date Added")
  public static let iconView = AccessibilityElement(
    identifier: "icon-view", label: "Files")
  /// Every cell of the icon view shares this identifier, as list cells share
  /// theirs. A cell speaks its item's name and kind, so the label is never
  /// the fixed one.
  public static let iconCell = AccessibilityElement(
    identifier: "icon-cell", label: "Item")
  public static let columnBrowser = AccessibilityElement(
    identifier: "column-browser", label: "Files")
  /// Each column of the browser is a list of entries. It is named by its
  /// place, such as "Column 2", so a screen reader can say where it is.
  public static let browserColumn = AccessibilityElement(
    identifier: "browser-column", label: "Column")
  /// The preview column. It holds the picture, which is decoration, and
  /// texts that speak for themselves.
  public static let preview = AccessibilityElement(
    identifier: "preview", label: "Preview")
  public static let previewName = AccessibilityElement(
    identifier: "preview-name", label: "Name")
  /// Every fact of the preview shares this identifier, as list cells share
  /// theirs: each says its own words, such as "Size: 2 kB".
  public static let previewFact = AccessibilityElement(
    identifier: "preview-fact", label: "Fact")
  public static let backButton = AccessibilityElement(
    identifier: "go-back", label: "Back")
  public static let forwardButton = AccessibilityElement(
    identifier: "go-forward", label: "Forward")
  public static let tabBar = AccessibilityElement(
    identifier: "tab-bar", label: "Tabs")
  /// Every tab shares this identifier, as list cells share theirs. A tab
  /// speaks its folder's name, so the label is never spoken.
  public static let tab = AccessibilityElement(
    identifier: "tab", label: "Tab")
  /// Every tab's close button. See `apply(_:for:)` for what it speaks.
  public static let closeTabButton = AccessibilityElement(
    identifier: "close-tab", label: "Close Tab")
  public static let newTabButton = AccessibilityElement(
    identifier: "new-tab", label: "New Tab")
  public static let sidebar = AccessibilityElement(
    identifier: "sidebar", label: "Sidebar")
  /// Every section header shares this identifier, as list cells share
  /// theirs. A header speaks its own name.
  public static let sidebarHeader = AccessibilityElement(
    identifier: "sidebar-header", label: "Section")
  /// Every place in the sidebar shares this identifier. A row speaks its
  /// name, and says when its folder cannot be found.
  public static let sidebarItem = AccessibilityElement(
    identifier: "sidebar-item", label: "Place")
  /// Every eject button shares this identifier. See `apply(_:for:)` for
  /// what it speaks: "Eject Backup".
  public static let ejectButton = AccessibilityElement(
    identifier: "eject-button", label: "Eject")
  public static let pathBar = AccessibilityElement(
    identifier: "path-bar", label: "Path")
  /// Every name of the path bar shares this identifier. A name speaks its
  /// folder: "Folder Documents".
  public static let pathCrumb = AccessibilityElement(
    identifier: "path-crumb", label: "Folder")
  /// Every name's menu button shares this identifier. It speaks the folder
  /// it opens: "Folders in Documents".
  public static let pathCrumbMenu = AccessibilityElement(
    identifier: "path-crumb-menu", label: "Folders in")
  /// The "…" button that holds the names that do not fit.
  public static let pathOverflow = AccessibilityElement(
    identifier: "path-overflow", label: "Earlier folders")
  public static let goToFolderSheet = AccessibilityElement(
    identifier: "go-to-folder-sheet", label: "Go to Folder")
  public static let goToFolderField = AccessibilityElement(
    identifier: "go-to-folder-field", label: "Folder path")
  public static let goToFolderSuggestions = AccessibilityElement(
    identifier: "go-to-folder-suggestions", label: "Matching folders")
  public static let goToFolderStatus = AccessibilityElement(
    identifier: "go-to-folder-status", label: "Go to Folder status")
  public static let goToFolderGoButton = AccessibilityElement(
    identifier: "go-to-folder-go", label: "Go")
  public static let goToFolderCancelButton = AccessibilityElement(
    identifier: "go-to-folder-cancel", label: "Cancel")
  public static let settingsWindow = AccessibilityElement(
    identifier: "settings-window", label: "Settings")
  /// The view that hosts the Settings window's content. The audit reports a
  /// hosting view that has no description.
  public static let settingsContent = AccessibilityElement(
    identifier: "settings-content", label: "Settings")
  public static let rememberOpenFoldersToggle = AccessibilityElement(
    identifier: "setting-remember-open-folders",
    label: "Open folders again when going back or forward")

  /// Every element the app declares. Tests check that identifiers are unique
  /// and labels are present.
  public static let all: [AccessibilityElement] = [
    .browserColumn,
    .mainWindow, .browserView, .fileList, .browserStatus, .nameCell, .sizeCell, .sizeOnDiskCell,
    .modifiedCell, .addedCell, .iconView, .iconCell, .columnBrowser, .preview, .previewName,
    .previewFact, .backButton, .forwardButton, .tabBar, .tab,
    .closeTabButton, .sidebar, .sidebarHeader, .sidebarItem, .ejectButton,
    .newTabButton, .pathBar, .pathCrumb, .pathCrumbMenu, .pathOverflow, .goToFolderSheet,
    .goToFolderField, .goToFolderSuggestions, .goToFolderStatus, .goToFolderGoButton,
    .goToFolderCancelButton, .settingsWindow,
    .settingsContent, .rememberOpenFoldersToggle,
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
  /// Gives one of several like controls its identifier and a spoken label
  /// that says which thing it acts on: the close button of the tab showing
  /// Documents speaks "Close Tab Documents". Call it again when the thing's
  /// name changes.
  public func apply(_ element: AccessibilityElement, for subject: String) {
    applyIdentifier(of: element)
    setAccessibilityLabel("\(element.label) \(subject)")
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

extension View {
  /// Gives a SwiftUI control its identifier and spoken label together, as
  /// `apply(_:)` does for a view.
  public func apply(_ element: AccessibilityElement) -> some View {
    accessibilityIdentifier(element.identifier).accessibilityLabel(element.label)
  }
}

extension NSWindow {
  /// Gives the window its identifier. A window's spoken name is its title,
  /// which the pane sets to the showing tab's folder name.
  public func apply(_ element: AccessibilityElement) {
    identifier = NSUserInterfaceItemIdentifier(element.identifier)
    setAccessibilityIdentifier(element.identifier)
  }
}

extension AccessibilityElement {
  /// The identifier of the toolbar item that holds this element's button.
  public var toolbarItemIdentifier: NSToolbarItem.Identifier {
    NSToolbarItem.Identifier(identifier)
  }
}

extension NSToolbarItem {
  /// Creates a toolbar item that holds a real button, which takes its
  /// identifier and spoken label from the element through `apply(_:)` like
  /// any other control. A standard item is not used because the button the
  /// system makes for one has no accessibility identifier (seen on macOS 27).
  public convenience init(_ element: AccessibilityElement, symbolName: String) {
    self.init(itemIdentifier: element.toolbarItemIdentifier)
    label = element.label
    paletteLabel = element.label

    let button = ToolbarButton(title: element.label, target: nil, action: nil)
    button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: element.label)
    // Without the symbol the button falls back to showing its title.
    button.imagePosition = button.image == nil ? .noImage : .imageOnly
    button.bezelStyle = .toolbar
    button.apply(element)
    view = button
  }
}
