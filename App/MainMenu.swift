import AppKit

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
