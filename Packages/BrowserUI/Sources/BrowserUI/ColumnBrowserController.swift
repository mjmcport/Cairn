import AppKit
import FileSystemCore

/// The column presentation: an `NSBrowser` over the model's chain of open
/// folders, with a preview in the last column.
///
/// The model is the one source of what is listed and selected. A column is
/// the open folder the item selected in the column before it stands for, and
/// selecting a folder here asks the model to open it and to close what was
/// open on another branch. What the browser shows is then reloaded from the
/// model, and reloading never writes back.
@MainActor
final class ColumnBrowserController: NSObject, NSBrowserDelegate {
  let browser = NSBrowser()
  private unowned let model: BrowserModel
  private let icons: GenericIcons
  private let preview: PreviewViewController
  /// The browser's one root item, a stand-in for the folder being shown.
  private let rootItem = OutlineNode(statusFor: .root, message: "")
  private var nodes: [FolderKey: OutlineNode] = [:]
  private var statusNodes: [FolderKey: OutlineNode] = [:]
  /// True while the model is being asked to change on the person's behalf or
  /// the browser is being set from the model, so neither echoes the other.
  private(set) var isApplying = false

  /// Called when the person opens a folder (double-click).
  var onOpen: (() -> Void)?

  init(model: BrowserModel, icons: GenericIcons, preview: PreviewViewController) {
    self.model = model
    self.icons = icons
    self.preview = preview
    super.init()
    browser.delegate = self
    browser.setCellClass(NSBrowserCell.self)
    browser.hasHorizontalScroller = true
    browser.allowsMultipleSelection = true
    browser.allowsEmptySelection = true
    browser.allowsBranchSelection = true
    browser.separatesColumns = true
    browser.minColumnWidth = 160
    browser.target = self
    browser.action = #selector(selectionChanged(_:))
    browser.doubleAction = #selector(doubleClicked(_:))
    browser.apply(.columnBrowser)
  }

  /// Gives each column's list a name by its place. The browser makes them,
  /// and the audit reports a list that has no description.
  private func nameColumns() {
    var lists: [NSTableView] = []
    func collect(_ view: NSView) {
      if let table = view as? NSTableView {
        lists.append(table)
        return
      }
      for subview in view.subviews { collect(subview) }
    }
    collect(browser)
    let ordered = lists.sorted {
      $0.convert($0.bounds, to: browser).minX < $1.convert($1.bounds, to: browser).minX
    }
    for (index, list) in ordered.enumerated() {
      list.apply(.browserColumn, for: "\(index + 1)")
    }
  }

  // MARK: From the model

  /// Draws everything again from the model: the columns, the selection and
  /// the preview.
  func reload() {
    isApplying = true
    defer { isApplying = false }
    nodes.removeAll()
    statusNodes.removeAll()
    browser.loadColumnZero()
    applySelection()
    nameColumns()
  }

  /// Draws one folder's column again, after the model listed it or changed
  /// it, and puts the selection back.
  func reloadColumn(of folder: FolderKey) {
    isApplying = true
    defer { isApplying = false }
    for key in nodes.keys where key.isInside(folder) && key != folder {
      nodes[key] = nil
    }
    statusNodes[folder] = nil
    // The column that lists a folder's children is the one after the column
    // the folder itself is in, which is as many columns in as it is deep.
    if folder.depth < browser.lastColumn + 2 {
      browser.reloadColumn(folder.depth)
    }
    applySelection()
    nameColumns()
  }

  /// Selects, in the browser, what the model has selected, and shows its
  /// preview. A selected folder that is not open is opened, because
  /// selecting a folder here is showing it.
  func applySelection() {
    let selected = model.selectedItems
    guard !selected.isEmpty else {
      browser.setPath("/")
      preview.show([])
      return
    }
    var paths: [IndexPath] = []
    for item in selected {
      guard let key = model.key(of: item.url), let path = indexPath(of: key) else { continue }
      paths.append(path)
    }
    if paths.isEmpty {
      preview.show([])
      return
    }
    browser.selectionIndexPaths = paths
    nameColumns()
    if selected.count == 1, let only = selected.first, only.isNavigable,
      let key = model.key(of: only.url), !model.isOpen(key)
    {
      // Selected in the browser, not yet listed: ask the model, which lists
      // it and publishes when its rows are there.
      model.openFolder(key)
    }
    showPreview()
  }

  private func showPreview() {
    let selected = selectedItemsOfBrowser()
    let leaves = selected.filter { !$0.isNavigable }
    preview.show(leaves.count == selected.count ? leaves : [])
  }

  // MARK: Index paths and keys

  /// The browser's index path to the item at `key`: the position of each
  /// name among its siblings, from the first column on.
  private func indexPath(of key: FolderKey) -> IndexPath? {
    var indexes: [Int] = []
    var folder = FolderKey.root
    for name in key.names {
      let rows = model.children(of: folder)
      guard let index = rows.firstIndex(where: { $0.name == name }) else { return nil }
      indexes.append(index)
      folder = folder.appending(name)
    }
    return IndexPath(indexes: indexes)
  }

  /// The items the browser has selected in its last column.
  private func selectedItemsOfBrowser() -> [FileItem] {
    browser.selectionIndexPaths.compactMap { path in
      var folder = FolderKey.root
      var item: FileItem?
      for index in path {
        let rows = model.children(of: folder)
        guard rows.indices.contains(index) else { return nil }
        item = rows[index]
        folder = folder.appending(rows[index].name)
      }
      return item
    }
  }

  private func key(for path: IndexPath) -> FolderKey? {
    var folder = FolderKey.root
    for index in path {
      let rows = model.children(of: folder)
      guard rows.indices.contains(index) else { return nil }
      folder = folder.appending(rows[index].name)
    }
    return folder
  }

  // MARK: What the person does

  /// The person selected something. The model is asked to open the folders on
  /// the path and to close the others; nothing is reloaded here, because the
  /// model publishes what changed and the publishes are heard once the
  /// request is over.
  @objc private func selectionChanged(_ sender: Any?) {
    guard !isApplying else { return }
    let paths = browser.selectionIndexPaths
    let keys = paths.compactMap { key(for: $0) }
    let items = selectedItemsOfBrowser()

    isApplying = true
    // The folders to keep open: the chain that leads to what is selected, and
    // a selected folder itself.
    var keep = Set<FolderKey>()
    for key in keys {
      var next = key.parent
      while let ancestor = next, !ancestor.isRoot {
        keep.insert(ancestor)
        next = ancestor.parent
      }
    }
    if keys.count == 1, let only = items.first, only.isNavigable { keep.insert(keys[0]) }
    for open in model.openFolderKeys.reversed() where !keep.contains(open) {
      model.closeFolder(open)
    }
    for key in keep.sorted(by: { $0.depth < $1.depth }) where !model.isOpen(key) {
      model.openFolder(key)
    }
    model.selection = Set(items.map(\.url))
    isApplying = false
    showPreview()
    nameColumns()
  }

  @objc private func doubleClicked(_ sender: Any?) {
    onOpen?()
  }

  // MARK: NSBrowserDelegate

  func rootItem(for browser: NSBrowser) -> Any? {
    rootItem
  }

  func browser(_ browser: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int {
    guard let node = item as? OutlineNode, node !== rootItem else { return model.items.count }
    guard !node.isStatus else { return 0 }
    if model.failure(of: node.key) != nil { return 1 }
    return model.children(of: node.key).count
  }

  func browser(_ browser: NSBrowser, child index: Int, ofItem item: Any?) -> Any {
    guard let parent = item as? OutlineNode, parent !== rootItem else {
      guard model.items.indices.contains(index) else { return Self.stale }
      return node(for: FolderKey.root.appending(model.items[index].name), item: model.items[index])
    }
    if let reason = model.failure(of: parent.key) {
      return statusNode(for: parent.key, message: reason)
    }
    let rows = model.children(of: parent.key)
    guard rows.indices.contains(index) else { return Self.stale }
    return node(for: parent.key.appending(rows[index].name), item: rows[index])
  }

  func browser(_ browser: NSBrowser, isLeafItem item: Any?) -> Bool {
    guard let node = item as? OutlineNode, node !== rootItem else { return false }
    return !(node.item?.isNavigable ?? false)
  }

  func browser(_ browser: NSBrowser, objectValueForItem item: Any?) -> Any? {
    guard let node = item as? OutlineNode else { return nil }
    return node.item?.name ?? node.message
  }

  func browser(_ browser: NSBrowser, willDisplayCell cell: Any, atRow row: Int, column: Int) {
    guard let cell = cell as? NSBrowserCell else { return }
    let rows = rows(inColumn: column)
    guard rows.indices.contains(row) else { return }
    let image = icons.icon(for: rows[row])
    image.size = NSSize(width: 16, height: 16)
    cell.image = image
  }

  func browser(_ browser: NSBrowser, previewViewControllerForLeafItem item: Any)
    -> NSViewController?
  {
    showPreview()
    return preview
  }

  func browser(
    _ browser: NSBrowser, selectionIndexesForProposedSelection proposed: IndexSet,
    inColumn column: Int
  )
    -> IndexSet
  {
    // A status row, which says why a folder could not be listed, is not
    // something to select.
    let rows = self.rows(inColumn: column)
    return proposed.filter { rows.indices.contains($0) }.reduce(into: IndexSet()) { $0.insert($1) }
  }

  func browser(_ browser: NSBrowser, typeSelectStringForRow row: Int, inColumn column: Int)
    -> String?
  {
    let rows = self.rows(inColumn: column)
    return rows.indices.contains(row) ? rows[row].name : nil
  }

  /// The items listed in a column: the folder shown for column 0, and for
  /// the others the open folder the browser's path leads through.
  private func rows(inColumn column: Int) -> [FileItem] {
    guard let folder = key(for: browser.indexPath(forColumn: column)) else { return [] }
    return model.children(of: folder)
  }

  // MARK: Handles

  private func node(for key: FolderKey, item: FileItem) -> OutlineNode {
    if let existing = nodes[key] {
      existing.item = item
      return existing
    }
    let node = OutlineNode(key: key, item: item)
    nodes[key] = node
    return node
  }

  private func statusNode(for key: FolderKey, message: String) -> OutlineNode {
    if let existing = statusNodes[key] {
      existing.message = message
      return existing
    }
    let node = OutlineNode(statusFor: key, message: message)
    statusNodes[key] = node
    return node
  }

  /// An empty row for an index the browser asks for after the rows changed
  /// under it. A reload follows and replaces it.
  private static let stale = OutlineNode(statusFor: .root, message: "")
}
