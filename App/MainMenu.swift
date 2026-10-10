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

    let fileMenu = NSMenu()
    fileMenu.addItem(
      withTitle: "Open",
      action: #selector(BrowserViewController.openSelection(_:)),
      keyEquivalent: "o"
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

    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(
      withTitle: "Minimize",
      action: #selector(NSWindow.performMiniaturize(_:)),
      keyEquivalent: "m"
    )
    windowMenu.addItem(
      withTitle: "Close",
      action: #selector(NSWindow.performClose(_:)),
      keyEquivalent: "w"
    )
    mainMenu.addItem(submenuItem(titled: "Window", menu: windowMenu))
    NSApp.windowsMenu = windowMenu

    return mainMenu
  }

  private static func submenuItem(titled title: String, menu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    menu.title = title
    item.submenu = menu
    return item
  }
}
