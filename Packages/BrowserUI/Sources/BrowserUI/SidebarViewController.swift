import AppKit
import FileSystemCore

/// Ejects a volume. The protocol exists so tests can supply a volume that
/// fails, or that is slow to go.
public protocol VolumeEjecting: Sendable {
  func eject(_ volume: URL) async throws
}

/// Unmounts and ejects through the workspace, off the main thread.
public struct WorkspaceEjector: VolumeEjecting {
  public init() {}

  public func eject(_ volume: URL) async throws {
    try await Task.detached {
      MainThreadGuard.assertOffMainThread()
      try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
    }.value
  }
}

/// The sidebar: Favorites, Locations, Cloud and Tags as a source list. It
/// holds no browser. Choosing an item is reported through ``onChoose``, and
/// the window asks the sidebar to follow the showing tab with
/// ``select(location:)``.
///
/// Everything it learns from the system (bookmarks, volumes, cloud folders,
/// tags) is read off the main actor and arrives as a value.
@MainActor
public final class SidebarViewController: NSViewController {
  private let favoriteStore: any FavoriteStoring
  private let volumeSource: any VolumeSource
  private let cloudSource: any CloudSource
  private let tagSource: any TagSource
  private let ejector: any VolumeEjecting

  /// What the person chose, and whether Command was held (a new tab).
  public var onChoose: ((SidebarItem, Bool) -> Void)?

  /// Says why something could not be done, in the window. Tests replace it.
  var presentFailure: (String) -> Void = { text in
    let alert = NSAlert()
    alert.messageText = text
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private(set) var sections: [SidebarSectionContent] = []
  private var nodes: [SectionNode] = []
  private var records: [FavoriteRecord] = []
  private var tags: [TagInfo] = []
  private var favorites: [ResolvedFavorite] = []
  private var volumes: [VolumeInfo] = []
  private var cloud: [CloudFolder] = []
  private var refreshGeneration = 0
  private var followedLocation: URL?
  private var isApplyingSelection = false

  private let scrollView = NSScrollView()
  private let outline = SidebarOutlineView()

  public init(
    favoriteStore: any FavoriteStoring = UserDefaultsFavoriteStore.forThisLaunch(),
    volumeSource: any VolumeSource = SystemVolumeSource(),
    cloudSource: any CloudSource = SystemCloudSource(),
    tagSource: any TagSource = SpotlightTagSource(),
    ejector: any VolumeEjecting = WorkspaceEjector()
  ) {
    self.favoriteStore = favoriteStore
    self.volumeSource = volumeSource
    self.cloudSource = cloudSource
    self.tagSource = tagSource
    self.ejector = ejector
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    fatalError("SidebarViewController is created in code")
  }

  // MARK: View

  public override func loadView() {
    let column = NSTableColumn(
      identifier: NSUserInterfaceItemIdentifier(rawValue: "sidebar-column"))
    column.resizingMask = .autoresizingMask
    outline.addTableColumn(column)
    outline.outlineTableColumn = column
    outline.headerView = nil
    outline.style = .sourceList
    outline.rowSizeStyle = .default
    outline.allowsMultipleSelection = false
    outline.allowsEmptySelection = true
    outline.floatsGroupRows = false
    outline.indentationPerLevel = 0
    outline.dataSource = self
    outline.delegate = self
    outline.apply(.sidebar)
    outline.onDelete = { [weak self] in self?.removeSelectedFavorite() }

    let menu = NSMenu()
    menu.delegate = self
    outline.menu = menu

    scrollView.documentView = outline
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.autohidesScrollers = true
    view = scrollView

    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(volumesChanged(_:)),
      name: NSWorkspace.didMountNotification, object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(volumesChanged(_:)),
      name: NSWorkspace.didUnmountNotification, object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(volumesChanged(_:)),
      name: NSWorkspace.didRenameVolumeNotification, object: nil)
  }

  public override func viewDidAppear() {
    super.viewDidAppear()
    // Cloud folders and tags are not watched: they are read again whenever
    // the sidebar comes on screen.
    Task { await refresh() }
  }

  @objc private func volumesChanged(_ note: Notification) {
    Task { await refresh() }
  }

  // MARK: Reading the sources

  /// Reads every source again and redraws. Favorites, volumes and cloud
  /// folders arrive together; tags, which can take longer, follow.
  public func refresh() async {
    refreshGeneration += 1
    let generation = refreshGeneration
    let store = favoriteStore
    let volumeSource = volumeSource
    let cloudSource = cloudSource

    let loaded = await Task.detached { () -> Loaded in
      let records = store.load() ?? Favorites.defaults()
      return Loaded(
        records: records, favorites: Favorites.resolve(records), volumes: volumeSource.volumes(),
        cloud: cloudSource.folders())
    }.value
    guard generation == refreshGeneration else { return }
    records = loaded.records
    favorites = loaded.favorites
    volumes = loaded.volumes
    cloud = loaded.cloud
    rebuild()

    let tagList = await tagSource.tags()
    guard generation == refreshGeneration else { return }
    tags = tagList
    rebuild()
  }

  private struct Loaded: Sendable {
    let records: [FavoriteRecord]
    let favorites: [ResolvedFavorite]
    let volumes: [VolumeInfo]
    let cloud: [CloudFolder]
  }

  private func rebuild() {
    sections = SidebarBuilder.sections(
      favorites: favorites, volumes: volumes, cloud: cloud, tags: tags)
    nodes = sections.map(SectionNode.init)
    // Reloading clears the selection; it is put back from the tab's place.
    isApplyingSelection = true
    outline.reloadData()
    outline.expandItem(nil, expandChildren: true)
    isApplyingSelection = false
    applySelection()
  }

  // MARK: Following the tab

  /// Selects the item whose place is `location`, and nothing when none is.
  public func select(location: URL?) {
    followedLocation = location
    applySelection()
  }

  private func applySelection() {
    isApplyingSelection = true
    defer { isApplyingSelection = false }
    guard let location = followedLocation, let node = itemNode(at: location) else {
      outline.deselectAll(nil)
      return
    }
    let row = outline.row(forItem: node)
    guard row >= 0 else { return }
    outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
  }

  private func itemNode(at location: URL) -> ItemNode? {
    for section in nodes {
      for node in section.children where BrowserHistory.isSamePlace(node.item.location, location) {
        return node
      }
    }
    return nil
  }

  /// The item that is selected, or nil.
  var selectedItem: SidebarItem? {
    (outline.item(atRow: outline.selectedRow) as? ItemNode)?.item
  }

  // MARK: Changing favorites

  /// Adds `folder` to Favorites, unless it is there already.
  public func addFavorite(_ folder: URL) async {
    let existing = favorites
    let outcome: Result<FavoriteRecord?, any Error> = await Task.detached {
      MainThreadGuard.assertOffMainThread()
      // Two spellings of one folder, such as /var and /private/var, are told
      // by resolving symbolic links, which asks the disk.
      let target = folder.resolvingSymlinksInPath().path
      if existing.contains(where: { $0.url?.resolvingSymlinksInPath().path == target }) {
        return .success(nil)
      }
      return Result { try Favorites.record(for: folder) }
    }.value

    switch outcome {
    case .success(nil):
      return
    case .success(let record?):
      records.append(record)
      favoriteStore.save(records)
      await refresh()
    case .failure:
      presentFailure("\(folder.lastPathComponent) could not be added to the sidebar.")
    }
  }

  /// Removes the favorite with the item's id, if it is one.
  func remove(_ item: SidebarItem) async {
    guard item.canRemove, item.kind == .favorite else { return }
    let prefix = "favorite:"
    let recordID = String(item.id.dropFirst(prefix.count))
    records.removeAll { $0.id == recordID }
    favoriteStore.save(records)
    await refresh()
  }

  private func removeSelectedFavorite() {
    guard let item = selectedItem else { return }
    Task { await remove(item) }
  }

  // MARK: Ejecting

  /// Ejects the volume of `item`, which the person asked for, and says why
  /// when it fails.
  func eject(_ item: SidebarItem) async {
    guard item.canEject else { return }
    do {
      try await ejector.eject(item.location)
      await refresh()
    } catch {
      presentFailure("\(item.title) could not be ejected. \(error.localizedDescription)")
    }
  }

  @objc private func ejectPressed(_ sender: NSButton) {
    let row = outline.row(for: sender)
    guard row >= 0, let node = outline.item(atRow: row) as? ItemNode else { return }
    let item = node.item
    Task { await eject(item) }
  }

  // MARK: Nodes

  private final class SectionNode: NSObject {
    let content: SidebarSectionContent
    let children: [ItemNode]

    init(_ content: SidebarSectionContent) {
      self.content = content
      children = content.items.map(ItemNode.init)
    }
  }

  private final class ItemNode: NSObject {
    let item: SidebarItem

    init(_ item: SidebarItem) {
      self.item = item
    }
  }
}

// MARK: Data source and delegate

extension SidebarViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
  public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    if item == nil { return nodes.count }
    return (item as? SectionNode)?.children.count ?? 0
  }

  public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any
  {
    if item == nil { return nodes[index] }
    return (item as! SectionNode).children[index]
  }

  public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    item is SectionNode
  }

  public func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
    item is SectionNode
  }

  public func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView?
  {
    // Headers keep the system's row; a place draws its own selection.
    item is ItemNode ? SidebarRowView() : nil
  }

  public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
    item is ItemNode
  }

  public func outlineView(_ outlineView: NSOutlineView, shouldCollapseItem item: Any) -> Bool {
    // Collapsing sections, and remembering it, is step 10's.
    false
  }

  public func outlineView(
    _ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any
  ) -> NSView? {
    if let section = item as? SectionNode {
      let cell = SidebarCell.make(in: outlineView, kind: .header)
      cell.showHeader(section.content.section.rawValue)
      return cell
    }
    guard let node = item as? ItemNode else { return nil }
    let cell = SidebarCell.make(in: outlineView, kind: .item)
    cell.show(node.item, ejectTarget: self, action: #selector(ejectPressed(_:)))
    return cell
  }

  public func outlineViewSelectionDidChange(_ notification: Notification) {
    guard !isApplyingSelection, let item = selectedItem else { return }
    let inNewTab = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
    onChoose?(item, inNewTab)
  }
}

extension SidebarViewController: NSMenuDelegate {
  public func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    let row = outline.clickedRow
    guard row >= 0, let node = outline.item(atRow: row) as? ItemNode else { return }
    let item = node.item
    let open = NSMenuItem(
      title: "Open in New Tab", action: #selector(openInNewTab(_:)), keyEquivalent: "")
    open.target = self
    open.representedObject = node
    menu.addItem(open)
    if item.canRemove {
      let remove = NSMenuItem(
        title: "Remove from Sidebar", action: #selector(removeFromSidebar(_:)), keyEquivalent: "")
      remove.target = self
      remove.representedObject = node
      menu.addItem(remove)
    }
    if item.canEject {
      let eject = NSMenuItem(
        title: "Eject", action: #selector(ejectFromMenu(_:)), keyEquivalent: "")
      eject.target = self
      eject.representedObject = node
      menu.addItem(eject)
    }
  }

  @objc private func openInNewTab(_ sender: NSMenuItem) {
    guard let node = sender.representedObject as? ItemNode else { return }
    onChoose?(node.item, true)
  }

  @objc private func removeFromSidebar(_ sender: NSMenuItem) {
    guard let node = sender.representedObject as? ItemNode else { return }
    let item = node.item
    Task { await remove(item) }
  }

  @objc private func ejectFromMenu(_ sender: NSMenuItem) {
    guard let node = sender.representedObject as? ItemNode else { return }
    let item = node.item
    Task { await eject(item) }
  }
}

// MARK: Views

/// An outline that reports Delete, which removes a favorite.
final class SidebarOutlineView: NSOutlineView {
  var onDelete: (() -> Void)?

  override func keyDown(with event: NSEvent) {
    // Delete and Forward Delete.
    if event.keyCode == 51 || event.keyCode == 117 {
      onDelete?()
    } else {
      super.keyDown(with: event)
    }
  }
}

/// A header or a place.
@MainActor
private final class SidebarCell: NSTableCellView {
  enum Kind {
    case header
    case item

    var reuseIdentifier: NSUserInterfaceItemIdentifier {
      NSUserInterfaceItemIdentifier(self == .header ? "sidebar-header-cell" : "sidebar-item-cell")
    }
  }

  private let label = NSTextField(labelWithString: "")
  private let picture = NSImageView()
  private let ejectButton = NSButton()

  static func make(in outline: NSOutlineView, kind: Kind) -> SidebarCell {
    if let cell = outline.makeView(withIdentifier: kind.reuseIdentifier, owner: nil) as? SidebarCell
    {
      return cell
    }
    let cell = SidebarCell()
    cell.identifier = kind.reuseIdentifier
    cell.build(kind)
    return cell
  }

  private func build(_ kind: Kind) {
    label.translatesAutoresizingMaskIntoConstraints = false
    label.lineBreakMode = .byTruncatingTail
    addSubview(label)
    if kind == .header {
      // Not the cell's `textField`: the system restyles that one in a source
      // list's group rows, in a light grey that fails the contrast audit.
      label.applyIdentifier(of: .sidebarHeader)
      // The system draws a source list's headers in a light grey, about 3:1
      // on the sidebar's background. The primary label color is well past
      // 4.5:1, and a semibold small size keeps them quieter than the rows.
      label.font = .systemFont(ofSize: 11, weight: .semibold)
      label.textColor = .labelColor
      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
        label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        label.centerYAnchor.constraint(equalTo: centerYAnchor),
      ])
      return
    }

    textField = label
    picture.translatesAutoresizingMaskIntoConstraints = false
    picture.imageScaling = .scaleProportionallyDown
    // The row speaks through its text; the picture repeats it.
    picture.setAccessibilityElement(false)
    addSubview(picture)
    imageView = picture

    ejectButton.translatesAutoresizingMaskIntoConstraints = false
    ejectButton.isBordered = false
    ejectButton.bezelStyle = .inline
    ejectButton.imagePosition = .imageOnly
    ejectButton.image = NSImage(systemSymbolName: "eject.fill", accessibilityDescription: nil)
    ejectButton.toolTip = "Eject"
    ejectButton.isHidden = true
    addSubview(ejectButton)

    label.applyIdentifier(of: .sidebarItem)
    NSLayoutConstraint.activate([
      picture.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      picture.centerYAnchor.constraint(equalTo: centerYAnchor),
      picture.widthAnchor.constraint(equalToConstant: 18),
      picture.heightAnchor.constraint(equalToConstant: 18),
      label.leadingAnchor.constraint(equalTo: picture.trailingAnchor, constant: 6),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
      label.trailingAnchor.constraint(lessThanOrEqualTo: ejectButton.leadingAnchor, constant: -4),
      ejectButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
      ejectButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      ejectButton.widthAnchor.constraint(equalToConstant: 18),
    ])
  }

  func showHeader(_ title: String) {
    label.stringValue = title
  }

  func show(_ item: SidebarItem, ejectTarget: AnyObject, action: Selector) {
    label.stringValue = item.title
    label.textColor = item.isMissing ? .secondaryLabelColor : .labelColor
    label.setSpokenText(item.isMissing ? "\(item.title), not found" : nil)
    picture.image = NSImage(systemSymbolName: item.symbolName, accessibilityDescription: nil)
    ejectButton.isHidden = !item.canEject
    ejectButton.target = ejectTarget
    ejectButton.action = action
    if item.canEject {
      ejectButton.apply(.ejectButton, for: item.title)
    }
  }
}
