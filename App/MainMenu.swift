import AppKit
import BrowserUI

/// Builds the menu bar in code. The app has no storyboard or nib.
@MainActor
enum MainMenu {
  static func make() -> NSMenu {
    let mainMenu = NSMenu()

    let appMenu = NSMenu()
    appMenu.addItem(
      withTitle: "About Cairn",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: ""
    )
    appMenu.addItem(.separator())
    // No target: it travels the responder chain to the app delegate.
    appMenu.addItem(
      withTitle: "Settings\u{2026}",
      action: #selector(AppDelegate.showSettings(_:)),
      keyEquivalent: ","
    )
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "Hide Cairn",
      action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h"
    )
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "Quit Cairn",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    mainMenu.addItem(submenuItem(titled: "Cairn", menu: appMenu))

    // The tab commands have no target, like the Go commands: they travel the
    // responder chain to the pane.
    let fileMenu = NSMenu()
    fileMenu.addItem(
      withTitle: "New Tab",
      action: #selector(PaneViewController.newTab(_:)),
      keyEquivalent: "t"
    )
    fileMenu.addItem(
      withTitle: "Open",
      action: #selector(BrowserViewController.openSelection(_:)),
      keyEquivalent: "o"
    )
    // No target: the window's content offers the selected folder, or the
    // one being shown, to the sidebar.
    let addToSidebar = fileMenu.addItem(
      withTitle: "Add to Sidebar",
      action: #selector(WindowContentViewController.addToSidebar(_:)),
      keyEquivalent: "t"
    )
    addToSidebar.keyEquivalentModifierMask = [.control, .command]
    fileMenu.addItem(.separator())
    // The pane closes its showing tab, and the window with its last tab. With
    // no pane in the chain the app delegate closes the key window.
    fileMenu.addItem(
      withTitle: "Close Tab",
      action: #selector(PaneViewController.closeTab(_:)),
      keyEquivalent: "w"
    )
    // An uppercase key equivalent means Shift is held.
    fileMenu.addItem(
      withTitle: "Close Window",
      action: #selector(NSWindow.performClose(_:)),
      keyEquivalent: "W"
    )
    mainMenu.addItem(submenuItem(titled: "File", menu: fileMenu))

    let goMenu = NSMenu()
    goMenu.addItem(
      withTitle: "Back",
      action: #selector(BrowserViewController.goBack(_:)),
      keyEquivalent: "["
    )
    goMenu.addItem(
      withTitle: "Forward",
      action: #selector(BrowserViewController.goForward(_:)),
      keyEquivalent: "]"
    )
    let enclosingFolder = goMenu.addItem(
      withTitle: "Enclosing Folder",
      action: #selector(BrowserViewController.goToEnclosingFolder(_:)),
      keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!)
    )
    enclosingFolder.keyEquivalentModifierMask = [.command]
    mainMenu.addItem(submenuItem(titled: "Go", menu: goMenu))

    // Like the Go commands, View has no target: it reaches the showing browser.
    let viewMenu = NSMenu()
    viewMenu.addItem(
      withTitle: "as List",
      action: #selector(BrowserViewController.showAsList(_:)),
      keyEquivalent: "1"
    )
    viewMenu.addItem(
      withTitle: "as Icons",
      action: #selector(BrowserViewController.showAsIcons(_:)),
      keyEquivalent: "2"
    )
    viewMenu.addItem(
      withTitle: "as Columns",
      action: #selector(BrowserViewController.showAsColumns(_:)),
      keyEquivalent: "3"
    )
    viewMenu.addItem(.separator())
    viewMenu.addItem(
      withTitle: "Keep Folders on Top",
      action: #selector(BrowserViewController.toggleFoldersFirst(_:)),
      keyEquivalent: ""
    )
    // The split view controller handles this, and titles the item Show or
    // Hide as the sidebar is.
    let sidebarItem = viewMenu.addItem(
      withTitle: "Hide Sidebar",
      action: #selector(NSSplitViewController.toggleSidebar(_:)),
      keyEquivalent: "s"
    )
    sidebarItem.keyEquivalentModifierMask = [.option, .command]
    viewMenu.insertItem(.separator(), at: viewMenu.index(of: sidebarItem))
    mainMenu.addItem(submenuItem(titled: "View", menu: viewMenu))

    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(
      withTitle: "Minimize",
      action: #selector(NSWindow.performMiniaturize(_:)),
      keyEquivalent: "m"
    )
    windowMenu.addItem(.separator())
    // Shift turns Tab into the back-tab character, so that is the key. An
    // item keyed as Tab with Control and Shift never fires, and takes plain
    // Control-Tab from the item after it.
    let previousTab = windowMenu.addItem(
      withTitle: "Show Previous Tab",
      action: #selector(PaneViewController.showPreviousTab(_:)),
      keyEquivalent: "\u{19}"
    )
    previousTab.keyEquivalentModifierMask = [.control, .shift]
    windowMenu.addItem(
      alternateShortcut(for: previousTab, keyEquivalent: "{", modifiers: [.command]))
    let nextTab = windowMenu.addItem(
      withTitle: "Show Next Tab",
      action: #selector(PaneViewController.showNextTab(_:)),
      keyEquivalent: "\t"
    )
    nextTab.keyEquivalentModifierMask = [.control]
    windowMenu.addItem(alternateShortcut(for: nextTab, keyEquivalent: "}", modifiers: [.command]))
    mainMenu.addItem(submenuItem(titled: "Window", menu: windowMenu))
    NSApp.windowsMenu = windowMenu

    return mainMenu
  }

  /// A hidden item that gives a command a second shortcut. Command-Shift-[
  /// and Command-Shift-] are keyed as the characters those keys type, `{`
  /// and `}`, which leaves Command-[ and Command-] to Back and Forward.
  private static func alternateShortcut(
    for item: NSMenuItem, keyEquivalent: String, modifiers: NSEvent.ModifierFlags
  ) -> NSMenuItem {
    let alternate = NSMenuItem(title: item.title, action: item.action, keyEquivalent: keyEquivalent)
    alternate.keyEquivalentModifierMask = modifiers
    alternate.isHidden = true
    alternate.allowsKeyEquivalentWhenHidden = true
    return alternate
  }

  private static func submenuItem(titled title: String, menu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    menu.title = title
    item.submenu = menu
    return item
  }
}
