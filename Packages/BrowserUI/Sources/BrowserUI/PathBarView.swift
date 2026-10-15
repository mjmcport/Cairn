import AppKit
import FileSystemCore

/// The row of folder names under the file list. A name goes to its folder;
/// the chevron beside it lists the folders inside it. Names that do not fit
/// collapse, from the left, into one "…" button.
///
/// The bar holds no browser and reads no file system itself: the owner gives
/// it a location, hears of a choice through ``onNavigate``, and the lists in
/// its menus come from a ``FolderCompleting`` off the main thread.
@MainActor
public final class PathBarView: NSView {
  /// The most folders a name's menu lists.
  static let menuLimit = 200
  static let height: CGFloat = 26

  /// Called with the folder the person chose.
  public var onNavigate: ((URL) -> Void)?
  /// Shows a menu from a button. Tests replace it; the bar's own pops it up.
  var presentMenu: (NSMenu, NSView) -> Void = { menu, view in
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 2), in: view)
  }

  private let completer: any FolderCompleting
  private(set) var crumbs: [Crumb] = []
  private(set) var nameButtons: [NSButton] = []
  private(set) var menuButtons: [NSButton] = []
  let overflowButton = NSButton()
  /// How many of the first crumbs are folded into the "…" button.
  private(set) var hiddenCount = 0
  private var menuTask: Task<Void, Never>?

  public init(completer: any FolderCompleting = DirectoryFolderCompleter()) {
    self.completer = completer
    super.init(frame: .zero)
    apply(.pathBar)
    // A named group, so a screen reader announces it and its names are
    // found inside it.
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    overflowButton.title = "\u{2026}"
    overflowButton.isBordered = false
    overflowButton.target = self
    overflowButton.action = #selector(showOverflow(_:))
    overflowButton.apply(.pathOverflow)
    overflowButton.isHidden = true
    addSubview(overflowButton)
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    fatalError("PathBarView is created in code")
  }

  public override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
  }

  /// Names for the folders from the root to `location`.
  public func update(location: URL, rootName: String = PathCrumbs.defaultRootName) {
    let new = PathCrumbs.crumbs(for: location, rootName: rootName)
    guard new != crumbs else { return }
    crumbs = new
    nameButtons.forEach { $0.removeFromSuperview() }
    menuButtons.forEach { $0.removeFromSuperview() }
    nameButtons = []
    menuButtons = []
    let isVirtual = VirtualLocation.isVirtual(location)
    for (index, crumb) in new.enumerated() {
      let name = NSButton(title: crumb.title, target: self, action: #selector(chooseName(_:)))
      name.isBordered = false
      name.tag = index
      name.font = crumb.isCurrent ? .boldSystemFont(ofSize: 12) : .systemFont(ofSize: 12)
      name.lineBreakMode = .byTruncatingMiddle
      name.apply(.pathCrumb, for: crumb.title)
      name.setAccessibilityValue(crumb.isCurrent ? "Current" : nil)
      addSubview(name)
      nameButtons.append(name)

      let chevron = NSButton(title: "", target: self, action: #selector(openMenu(_:)))
      chevron.isBordered = false
      chevron.tag = index
      chevron.image = NSImage(
        systemSymbolName: "chevron.right", accessibilityDescription: "Folders in \(crumb.title)")
      chevron.imagePosition = .imageOnly
      chevron.apply(.pathCrumbMenu, for: crumb.title)
      chevron.isHidden = isVirtual
      addSubview(chevron)
      menuButtons.append(chevron)
    }
    needsLayout = true
  }

  // MARK: Layout

  public override func layout() {
    super.layout()
    let gap: CGFloat = 2
    let chevronWidth: CGFloat = 16
    let sizes = nameButtons.map { min($0.fittingSize.width, 220) }
    let hasMenu = menuButtons.map { !$0.isHidden }
    func width(_ index: Int) -> CGFloat {
      sizes[index] + (hasMenu[index] ? chevronWidth : 0) + gap
    }
    let inset: CGFloat = 8
    let available = bounds.width - inset * 2
    let overflowWidth: CGFloat = 28
    // Hide names from the left until the rest fit; the current one always stays.
    var hidden = 0
    var total = (0..<sizes.count).reduce(0) { $0 + width($1) }
    while total > available, hidden < sizes.count - 1 {
      total -= width(hidden)
      hidden += 1
      if hidden == 1 { total += overflowWidth }
    }
    hiddenCount = hidden
    overflowButton.isHidden = hidden == 0
    let y = (bounds.height - 18) / 2
    var x = inset
    if hidden > 0 {
      overflowButton.frame = NSRect(x: x, y: y, width: overflowWidth - gap, height: 18)
      x += overflowWidth
    }
    for index in 0..<sizes.count {
      let isShown = index >= hidden
      nameButtons[index].isHidden = !isShown
      menuButtons[index].isHidden = !isShown || !hasMenu[index]
      guard isShown else { continue }
      nameButtons[index].frame = NSRect(x: x, y: y, width: sizes[index], height: 18)
      x += sizes[index]
      if hasMenu[index] {
        menuButtons[index].frame = NSRect(x: x, y: y, width: chevronWidth, height: 18)
        x += chevronWidth
      }
      x += gap
    }
  }

  // MARK: Actions

  @objc private func chooseName(_ sender: NSButton) {
    guard crumbs.indices.contains(sender.tag), !crumbs[sender.tag].isCurrent else { return }
    onNavigate?(crumbs[sender.tag].url)
  }

  @objc private func showOverflow(_ sender: NSButton) {
    let menu = NSMenu()
    for crumb in crumbs.prefix(hiddenCount) {
      menu.addItem(item(for: crumb.title, url: crumb.url))
    }
    presentMenu(menu, sender)
  }

  @objc private func openMenu(_ sender: NSButton) {
    guard crumbs.indices.contains(sender.tag) else { return }
    let folder = crumbs[sender.tag].url
    menuTask?.cancel()
    menuTask = Task { [weak self, weak sender] in
      let menu = await self?.menu(forFolder: folder)
      guard !Task.isCancelled, let self, let sender, let menu else { return }
      self.presentMenu(menu, sender)
    }
  }

  /// The menu of the folders inside `folder`, listed off the main thread. A
  /// folder that cannot be listed gives one disabled line that says so.
  func menu(forFolder folder: URL) async -> NSMenu {
    let completer = completer
    let limit = Self.menuLimit
    let result: Result<[FolderSuggestion], Error> = await Task.detached {
      Result { try completer.folders(in: folder, prefix: "", limit: limit) }
    }.value
    let menu = NSMenu()
    switch result {
    case .success(let folders):
      if folders.isEmpty {
        menu.addItem(disabled("No folders"))
      }
      for entry in folders {
        menu.addItem(item(for: entry.name, url: entry.url))
      }
    case .failure:
      menu.addItem(disabled("Cannot list this folder"))
    }
    return menu
  }

  private func item(for title: String, url: URL) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(chooseMenuItem(_:)), keyEquivalent: "")
    item.target = self
    item.representedObject = url
    return item
  }

  private func disabled(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }

  @objc private func chooseMenuItem(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? URL else { return }
    onNavigate?(url)
  }
}
