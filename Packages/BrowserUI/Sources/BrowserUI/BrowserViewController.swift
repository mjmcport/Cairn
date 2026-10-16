import AppKit
import FileMetadata
import FileSystemCore

/// Shows the contents of one folder as an outline with name, size, size on
/// disk, modified date and date added. A folder can be opened in place, and
/// its items are then listed beneath it. Every tab of a pane is one of these.
///
/// A browser does not know whether it is the tab that is showing, so it
/// leaves the window's title and keyboard focus to its owner: it keeps its
/// own `title` current and reports a change through ``onTitleChange``.
@MainActor
public final class BrowserViewController: NSViewController {
  enum Column: String, CaseIterable {
    case name, size, sizeOnDisk, modified, added

    var identifier: NSUserInterfaceItemIdentifier { .init("column-\(rawValue)") }

    var title: String {
      switch self {
      case .name: "Name"
      case .size: "Size"
      case .sizeOnDisk: "Size on Disk"
      case .modified: "Date Modified"
      case .added: "Date Added"
      }
    }

    var accessibility: AccessibilityElement {
      switch self {
      case .name: .nameCell
      case .size: .sizeCell
      case .sizeOnDisk: .sizeOnDiskCell
      case .modified: .modifiedCell
      case .added: .addedCell
      }
    }

    /// What VoiceOver says in place of the dashes shown for a missing value.
    var missingValueSpokenText: String {
      switch self {
      case .name: "No name"
      case .size: "No size"
      case .sizeOnDisk: "No size on disk"
      case .modified: "No date"
      case .added: "No date added"
      }
    }

    /// The starting widths. Together with the table's spacing they fit the
    /// window's default width, so no column hangs outside it and the list
    /// needs no horizontal scroller; the Name column takes any width the
    /// window gains.
    var width: CGFloat {
      switch self {
      case .name: 240
      case .size: 80
      case .sizeOnDisk: 90
      case .modified: 160
      case .added: 160
      }
    }

    /// The order the column sorts by.
    var sortKey: FileItemSort.Key {
      switch self {
      case .name: .name
      case .size: .size
      case .sizeOnDisk: .sizeOnDisk
      case .modified: .modificationDate
      case .added: .dateAdded
      }
    }

    init(sortKey: FileItemSort.Key) {
      self = Self.allCases.first { $0.sortKey == sortKey } ?? .name
    }
  }

  public let model: BrowserModel

  private let outlineView = NSOutlineView()
  private let scrollView = NSScrollView()
  /// The icon presentation, which is on screen in place of the outline while
  /// the model's mode is icons. Both read the same model.
  private let iconView = IconCollectionView()
  private let iconScrollView = NSScrollView()
  private let genericIcons = GenericIcons()
  private var typeAhead = TypeAhead()
  /// Makes the pictures of the icon presentation. Tests replace it before the
  /// view loads, to stand in for the system's thumbnail generator.
  var thumbnailLoader = ThumbnailLoader(provider: QuickLookThumbnailer())
  /// The column presentation and its preview, made when first needed so that
  /// a test's loader is the one they use.
  lazy var previewController = PreviewViewController(
    loader: thumbnailLoader, icons: genericIcons)
  lazy var columns = ColumnBrowserController(
    model: model, icons: genericIcons, preview: previewController)
  private let statusLabel = NSTextField(wrappingLabelWithString: "")
  /// The model action in flight, if any. Tests await it.
  private(set) var loadTask: Task<Void, Never>?
  /// True while the outline's selection, expansion or sort indicator is
  /// being set from the model, so the change is not written back as if the
  /// user had made it.
  private var isApplyingModelState = false
  /// The handle of each row, kept so a row is the same object each time
  /// AppKit asks for it. A node's item is replaced in place when the model
  /// lists it again.
  private var itemNodes: [FolderKey: OutlineNode] = [:]
  private var statusNodes: [FolderKey: OutlineNode] = [:]

  public var location: URL { model.location }

  /// Called on the main actor when `title`, the name of the folder being
  /// shown, changes. A command reports the change as it arrives, before the
  /// folder has been listed.
  public var onTitleChange: (() -> Void)?

  /// Called on the main actor when the place being shown changes, as it is
  /// made and before it has been listed. The sidebar follows it.
  public var onLocationChange: (() -> Void)?
  private var reportedLocation: URL?

  /// A browser on the real file system, which lists its folder and, while
  /// its owner says it is on screen, watches it.
  public convenience init(location: URL) {
    self.init(model: BrowserModel(location: location))
  }

  /// A browser that lists through `reader`. It watches nothing unless it is
  /// also given a watcher.
  public convenience init(
    location: URL, reader: any DirectoryReading, watcher: (any FolderWatching)? = nil
  ) {
    self.init(model: BrowserModel(location: location, reader: reader, watcher: watcher))
  }

  /// A browser on a saved tab: its location, presentation and history.
  /// Nothing is listed until its view loads, as for any new tab.
  public convenience init(
    restoring saved: SavedTab, location: URL, reader: any DirectoryReading,
    watcher: (any FolderWatching)? = nil
  ) {
    self.init(location: location, reader: reader, watcher: watcher)
    model.restore(saved)
  }

  /// What this tab saves. See ``BrowserModel/captureState()``.
  public func captureState() -> SavedTab { model.captureState() }

  private init(model: BrowserModel) {
    self.model = model
    let location = model.location
    super.init(nibName: nil, bundle: nil)
    // Set here, so a tab that has never been shown already has its title.
    title = Self.title(for: location)
  }

  @available(*, unavailable)
  public required init?(coder: NSCoder) {
    fatalError("BrowserViewController is created in code")
  }

  public override func loadView() {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
    container.applyIdentifier(of: .browserView)

    for column in Column.allCases {
      let tableColumn = NSTableColumn(identifier: column.identifier)
      tableColumn.title = column.title
      tableColumn.width = column.width
      tableColumn.minWidth = 60
      tableColumn.resizingMask =
        column == .name ? [.autoresizingMask, .userResizingMask] : .userResizingMask
      tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
      outlineView.addTableColumn(tableColumn)
      if column == .name {
        // The triangles and the indentation are drawn in this column.
        outlineView.outlineTableColumn = tableColumn
      }
    }
    outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
    outlineView.apply(.fileList)
    outlineView.style = .fullWidth
    outlineView.usesAlternatingRowBackgroundColors = true
    outlineView.allowsMultipleSelection = true
    outlineView.dataSource = self
    outlineView.delegate = self
    outlineView.target = self
    outlineView.doubleAction = #selector(openClickedRow(_:))

    scrollView.documentView = outlineView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    statusLabel.applyIdentifier(of: .browserStatus)
    statusLabel.alignment = .center
    // Primary label color: the secondary color fails the contrast audit.
    statusLabel.textColor = .labelColor
    // An opaque background, so the text's contrast does not depend on the
    // striped rows it sits over.
    statusLabel.drawsBackground = true
    statusLabel.backgroundColor = .textBackgroundColor
    statusLabel.isHidden = true
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    let layout = NSCollectionViewFlowLayout()
    layout.itemSize = IconItem.cellSize
    layout.minimumInteritemSpacing = 8
    layout.minimumLineSpacing = 8
    layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    iconView.collectionViewLayout = layout
    iconView.register(IconItem.self, forItemWithIdentifier: IconItem.reuseIdentifier)
    iconView.dataSource = self
    iconView.delegate = self
    iconView.isSelectable = true
    iconView.allowsMultipleSelection = true
    iconView.backgroundColors = [.controlBackgroundColor]
    iconView.apply(.iconView)
    iconView.onType = { [weak self] text, time in self?.typed(text, at: time) }
    iconView.onOpen = { [weak self] in self?.openSelection(nil) }
    iconScrollView.documentView = iconView
    iconScrollView.hasVerticalScroller = true
    iconScrollView.translatesAutoresizingMaskIntoConstraints = false
    iconScrollView.isHidden = true

    let columnBrowser = columns.browser
    columnBrowser.translatesAutoresizingMaskIntoConstraints = false
    columnBrowser.isHidden = true
    columns.onOpen = { [weak self] in self?.openSelection(nil) }

    container.addSubview(scrollView)
    container.addSubview(iconScrollView)
    container.addSubview(columnBrowser)
    container.addSubview(statusLabel)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: container.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      columnBrowser.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      columnBrowser.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      columnBrowser.topAnchor.constraint(equalTo: container.topAnchor),
      columnBrowser.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      iconScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      iconScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      iconScrollView.topAnchor.constraint(equalTo: container.topAnchor),
      iconScrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      statusLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      statusLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      statusLabel.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -40),
    ])
    view = container
  }

  public override func viewDidLoad() {
    super.viewDidLoad()
    model.onChange = { [weak self] in self?.modelDidChange() }
    updateSortIndicator()
    modelDidChange()
    run { await $0.load() }
  }

  public override func viewDidAppear() {
    super.viewDidAppear()
    view.window?.validateToolbarItems()
  }

  // MARK: Actions

  /// Opens the selected item. Sent by File > Open through the responder chain.
  @objc public func openSelection(_ sender: Any?) {
    if model.viewMode != .list {
      guard let item = singleSelectedItem else { return }
      openItem(item)
    } else {
      open(row: outlineView.selectedRow)
    }
  }

  /// Shows the folder that contains the current one. Sent by Go > Enclosing Folder.
  @objc public func goToEnclosingFolder(_ sender: Any?) {
    // At the root there is nowhere to go, so a load under way is left to finish.
    guard model.moveToEnclosingFolder() else { return }
    movedAway()
    run { await $0.load() }
  }

  /// The folder File > Add to Sidebar would add: the selected folder, or with
  /// no folder selected, the one being shown. Nil in a tag or the recents
  /// with no folder selected.
  public var folderToAdd: URL? {
    let selected = model.selectedItems
    if selected.count == 1, selected[0].isNavigable { return selected[0].url }
    guard selected.isEmpty, !model.isShowingVirtualLocation else { return nil }
    return model.location
  }

  /// The paths Copy Path acts on: the selected items, or with none selected
  /// the folder being shown. Empty in a tag or the recents with none selected.
  public var itemsToCopyPaths: [URL] {
    let selected = model.selectedItems
    if !selected.isEmpty { return selected.map(\.url) }
    return model.isShowingVirtualLocation ? [] : [model.location]
  }

  /// Puts the paths of ``itemsToCopyPaths`` on `pasteboard` in `format`, a
  /// line for each. Does nothing when there are none.
  public func copyPaths(
    as format: PathFormat, to pasteboard: any PathPasteboard = SystemPathPasteboard(),
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) {
    let urls = itemsToCopyPaths
    guard !urls.isEmpty else { return }
    let text = urls.map { format.string(for: $0, home: home) }.joined(separator: "\n")
    pasteboard.replace(with: text, urls: format == .fileURL ? urls : [])
  }

  /// Copies the paths in the format the menu item's tag names. Sent by
  /// Edit > Copy Path.
  @objc public func copyPath(_ sender: NSMenuItem) {
    copyPaths(as: PathFormat(rawValue: sender.tag) ?? .path)
  }

  /// Shows `location` in this tab as a move, as a command does: history, the
  /// title and the toolbar follow, and Back returns. Asked by the sidebar.
  public func show(_ location: URL, selecting: Set<URL> = []) {
    guard model.move(to: location, selecting: selecting) else { return }
    movedAway()
    run { await $0.load() }
  }

  /// Returns to the previous folder. Sent by Go > Back and the toolbar.
  @objc public func goBack(_ sender: Any?) {
    // With no history there is nowhere to go, so a load under way is left to finish.
    guard model.moveBack() else { return }
    movedAway()
    run { await $0.load() }
  }

  /// Undoes Back. Sent by Go > Forward and the toolbar.
  @objc public func goForward(_ sender: Any?) {
    guard model.moveForward() else { return }
    movedAway()
    run { await $0.load() }
  }

  /// Groups folders ahead of files at every level, or stops doing so. Sent
  /// by View > Keep Folders on Top.
  @objc public func toggleFoldersFirst(_ sender: Any?) {
    var sort = model.sort
    sort.foldersFirst.toggle()
    model.changeSort(to: sort)
  }

  /// Shows the folder as rows. Sent by View > as List.
  @objc public func showAsList(_ sender: Any?) {
    model.setViewMode(.list)
  }

  /// Shows the folder as icons. Sent by View > as Icons.
  @objc public func showAsIcons(_ sender: Any?) {
    model.setViewMode(.icons)
  }

  /// Shows the folder as columns with a preview. Sent by View > as Columns.
  @objc public func showAsColumns(_ sender: Any?) {
    model.setViewMode(.columns)
  }

  @objc private func openClickedRow(_ sender: Any?) {
    open(row: outlineView.clickedRow)
  }

  private func open(row: Int) {
    guard row >= 0, let item = (outlineView.item(atRow: row) as? OutlineNode)?.item else { return }
    openItem(item)
  }

  private func openItem(_ item: FileItem) {
    // Opening a file does nothing yet, so a load under way is left to finish.
    guard item.isNavigable else { return }
    model.move(to: item.url)
    movedAway()
    run { await $0.load() }
  }

  /// The one selected item of the icon or column presentation, or nil.
  private var singleSelectedItem: FileItem? {
    let selected = model.selectedItems
    return selected.count == 1 ? selected[0] : nil
  }

  /// Typing in the icon presentation selects the first name that starts with
  /// what has been typed, as it does in the list.
  private func typed(_ text: String, at time: TimeInterval) {
    let prefix = typeAhead.type(text, at: time)
    guard let index = TypeAhead.match(prefix, in: model.items.map(\.name)) else { return }
    let item = model.items[index]
    model.selection = [item.url]
    applyIconSelection(scrollingToIt: true)
  }

  /// Puts keyboard focus in the file list. Does nothing while the browser's
  /// view is not in a window.
  public func focusList() {
    let target: NSView =
      switch model.viewMode {
      case .list: outlineView
      case .icons: iconView
      case .columns: columns.browser
      }
    view.window?.makeFirstResponder(target)
  }

  /// Watches the folder being shown, and each folder the browser moves to,
  /// so the list follows changes made elsewhere. The owner calls this while
  /// the browser is on screen, which a browser cannot know by itself.
  public func startWatching() {
    model.startWatching()
  }

  /// Stops watching, for a browser that is no longer on screen.
  public func stopWatching() {
    model.stopWatching()
  }

  /// Stops a listing that is under way, for a browser that is going away.
  /// The cancelled listing publishes nothing.
  public func cancelLoad() {
    loadTask?.cancel()
  }

  /// Runs a model action that loads a folder, cancelling a load that is still
  /// under way. An action that would do nothing must not come through here:
  /// the cancelled load never publishes a result, so the browser would stay
  /// in its loading state.
  ///
  /// A command moves the model before it calls this, not inside the action.
  /// The task starts later, and a second command can arrive first: it has to
  /// see where the first one went, or it passes a check that is no longer
  /// true, cancels the first, and then finds nothing to do.
  private func run(_ action: @escaping @MainActor (BrowserModel) async -> Void) {
    loadTask?.cancel()
    loadTask = Task { [model] in await action(model) }
  }

  // MARK: Drawing the model

  private func modelDidChange() {
    updateTitle()
    showTheModesView()
    switch model.lastPublish {
    case .load:
      reloadEverything()
      applyModelSelection(scrollingToIt: true)
    case .refresh:
      // A refresh leaves the list where the user is looking: the selection
      // is put back on the same items, and nothing scrolls.
      reloadEverything()
      applyModelSelection(scrollingToIt: false)
    case .folder:
      if model.viewMode == .columns {
        // A change the controller itself asked for is already drawn.
        if !columns.isApplying {
          if let key = model.lastChangedFolder {
            columns.reloadColumn(of: key)
          } else {
            columns.reload()
          }
        }
      } else {
        if let key = model.lastChangedFolder, model.viewMode == .list {
          reloadFolder(key)
        } else {
          reloadEverything()
        }
        applyModelSelection(scrollingToIt: false)
      }
    case .resort:
      reloadEverything()
      updateSortIndicator()
      applyModelSelection(scrollingToIt: true)
    case .mode:
      reloadEverything()
      applyModelSelection(scrollingToIt: false)
    }
    view.window?.validateToolbarItems()

    switch model.state {
    case .loading:
      statusLabel.isHidden = true
    case .loaded:
      statusLabel.stringValue = "This folder is empty."
      statusLabel.isHidden = !model.items.isEmpty
    case .failed(let message):
      statusLabel.stringValue = message
      statusLabel.isHidden = false
    }
  }

  /// A command has moved the model, which has emptied its rows and will not
  /// publish until the listing starts. The outline is told now: it keeps the
  /// counts it was given and may ask for a row by an index that no longer
  /// exists, as AppKit on macOS 15 was seen to.
  private func movedAway() {
    updateTitle()
    reloadEverything()
  }

  /// Reloads every row. The scroll offset and keyboard focus are kept by the
  /// outline; folders that are open are opened again from the model.
  private func reloadEverything() {
    isApplyingModelState = true
    defer { isApplyingModelState = false }
    guard model.viewMode == .list else {
      // The outline is not on screen; it is reloaded when the list returns.
      if model.viewMode == .columns {
        columns.reload()
      } else {
        iconView.reloadData()
      }
      return
    }
    itemNodes.removeAll()
    statusNodes.removeAll()
    outlineView.reloadData()
    openFoldersTheModelHasOpen()
  }

  /// Reloads one folder's rows and nothing else, and opens or closes the
  /// folder to match the model.
  private func reloadFolder(_ key: FolderKey) {
    guard !key.isRoot, let node = itemNodes[key] else {
      // Never asked for by the outline, so there is nothing of it to reload;
      // the folder is opened below, from the model.
      reloadEverything()
      return
    }
    isApplyingModelState = true
    defer { isApplyingModelState = false }
    // The handles of everything beneath the folder are asked for again.
    for other in itemNodes.keys where other != key && other.isInside(key) {
      itemNodes[other] = nil
    }
    for other in statusNodes.keys where other.isInside(key) {
      statusNodes[other] = nil
    }
    if !model.isOpen(key), outlineView.isItemExpanded(node) {
      outlineView.collapseItem(node)
    }
    outlineView.reloadItem(node, reloadChildren: true)
    openFoldersTheModelHasOpen()
  }

  /// Opens, parent before child, each folder the model says is open and the
  /// outline shows closed. Never writes back to the model.
  private func openFoldersTheModelHasOpen() {
    for key in model.openFolderKeys {
      // AppKit asks for the handles of the rows it draws, so a folder far
      // down a long list may not have one yet: it is made from the model.
      guard let handle = handle(for: key), !outlineView.isItemExpanded(handle) else { continue }
      outlineView.expandItem(handle)
    }
  }

  /// Selects the rows the model says are selected and, when asked, scrolls
  /// the first into view.
  private func applyModelSelection(scrollingToIt: Bool) {
    if model.viewMode == .icons {
      applyIconSelection(scrollingToIt: scrollingToIt)
      return
    }
    if model.viewMode == .columns {
      // `reload()` has already put the selection back.
      return
    }
    isApplyingModelState = true
    defer { isApplyingModelState = false }

    var rows = IndexSet()
    let selected = model.selection
    if !selected.isEmpty {
      func collect(_ items: [FileItem], in folder: FolderKey) {
        for item in items where selected.contains(item.url) {
          let node = node(for: folder.appending(item.name), item: item)
          let row = outlineView.row(forItem: node)
          if row >= 0 { rows.insert(row) }
        }
      }
      collect(model.items, in: .root)
      for key in model.openFolderKeys {
        collect(model.children(of: key), in: key)
      }
    }
    outlineView.selectRowIndexes(rows, byExtendingSelection: false)
    if scrollingToIt, let first = rows.first {
      outlineView.scrollRowToVisible(first)
    }
  }

  /// Puts the outline or the icons on screen, whichever the model's mode
  /// says, and keeps keyboard focus in the list that is showing.
  private func showTheModesView() {
    let mode = model.viewMode
    let showsList = mode == .list
    let showsIcons = mode == .icons
    let showsColumns = mode == .columns
    guard
      scrollView.isHidden == showsList || iconScrollView.isHidden == showsIcons
        || columns.browser.isHidden == showsColumns
    else { return }
    let hadFocus = [outlineView, iconView, columns.browser].contains {
      view.window?.firstResponder === $0
    }
    scrollView.isHidden = !showsList
    iconScrollView.isHidden = !showsIcons
    columns.browser.isHidden = !showsColumns
    if hadFocus { focusList() }
  }

  /// Selects the cells of the model's selected items and, when asked,
  /// scrolls the first into view.
  private func applyIconSelection(scrollingToIt: Bool) {
    isApplyingModelState = true
    defer { isApplyingModelState = false }
    let selected = model.selection
    var paths = Set<IndexPath>()
    if !selected.isEmpty {
      for (index, item) in model.items.enumerated() where selected.contains(item.url) {
        paths.insert(IndexPath(item: index, section: 0))
      }
    }
    iconView.selectionIndexPaths = paths
    if scrollingToIt, let first = paths.min() {
      iconView.scrollToItems(at: [first], scrollPosition: .nearestHorizontalEdge)
    }
  }

  /// Writes what the icon view has selected to the model.
  private func iconSelectionChanged() {
    guard !isApplyingModelState else { return }
    let items = model.items
    model.selection = Set(
      iconView.selectionIndexPaths.compactMap {
        items.indices.contains($0.item) ? items[$0.item].url : nil
      })
  }

  /// Shows the model's sort in the column headers.
  private func updateSortIndicator() {
    isApplyingModelState = true
    defer { isApplyingModelState = false }
    let column = Column(sortKey: model.sort.key)
    outlineView.sortDescriptors = [
      NSSortDescriptor(key: column.rawValue, ascending: model.sort.ascending)
    ]
  }

  /// Names the controller after the folder and tells the owner when the
  /// name changed. A command calls this as it makes its move, so the owner
  /// hears before the listing starts; a model change calls it for a move
  /// made on the model directly.
  private func updateTitle() {
    if reportedLocation.map({ !BrowserHistory.isSamePlace($0, model.location) }) ?? true {
      reportedLocation = model.location
      onLocationChange?()
    }
    let folderName = Self.title(for: model.location)
    guard folderName != title else { return }
    title = folderName
    onTitleChange?()
  }

  static func title(for location: URL) -> String {
    if let virtual = VirtualLocation(url: location) { return virtual.title }
    return location.path == "/" ? "/" : location.lastPathComponent
  }

  /// Shown where an item has no value, as Finder does for a folder's size.
  static let missingValueText = "--"

  /// The size as text, or nil for an item that has none, such as a folder.
  static func sizeText(for item: FileItem) -> String? {
    item.size?.formatted(.byteCount(style: .file))
  }

  /// The size on disk as text, or nil for an item that has none.
  static func sizeOnDiskText(for item: FileItem) -> String? {
    item.allocatedSize?.formatted(.byteCount(style: .file))
  }

  /// The modified date as text, or nil for an item that has none.
  static func modifiedText(for item: FileItem) -> String? {
    item.modificationDate?.formatted(date: .abbreviated, time: .shortened)
  }

  /// The date the item was added to its folder as text, or nil.
  static func addedText(for item: FileItem) -> String? {
    item.dateAdded?.formatted(date: .abbreviated, time: .shortened)
  }

  /// Fills a cell, new or recycled, with one item's value for a column.
  static func fill(_ cell: NSTableCellView, column: Column, item: FileItem) {
    let value: String? =
      switch column {
      case .name: item.name
      case .size: sizeText(for: item)
      case .sizeOnDisk: sizeOnDiskText(for: item)
      case .modified: modifiedText(for: item)
      case .added: addedText(for: item)
      }
    cell.textField?.stringValue = value ?? missingValueText
    // Dashes are not words, so both the cell and its text get a spoken
    // replacement. Whether a value is missing comes from the item, never from
    // the text shown: a file can be named "--".
    let spokenText = value == nil ? column.missingValueSpokenText : nil
    cell.setSpokenText(spokenText)
    cell.textField?.setSpokenText(spokenText)
  }

  /// Fills a cell of a status row: the reason in the name column, and
  /// nothing in the others.
  static func fill(_ cell: NSTableCellView, column: Column, statusMessage: String) {
    cell.textField?.stringValue = column == .name ? statusMessage : ""
    cell.setSpokenText(nil)
    cell.textField?.setSpokenText(nil)
  }

  // MARK: Handles

  /// The handle of the row for `item` at `key`, the same object each time.
  private func node(for key: FolderKey, item: FileItem) -> OutlineNode {
    if let existing = itemNodes[key] {
      existing.item = item
      return existing
    }
    let node = OutlineNode(key: key, item: item)
    itemNodes[key] = node
    return node
  }

  /// The handle of the folder at `key`, from the cache or else made from
  /// what the model lists there.
  private func handle(for key: FolderKey) -> OutlineNode? {
    if let existing = itemNodes[key] { return existing }
    guard let item = model.item(at: key) else { return nil }
    return node(for: key, item: item)
  }

  /// What the outline is given for an index it asks for after the rows
  /// changed under it: an empty row that cannot be selected. A reload follows
  /// at once and replaces it.
  private static let staleRow = OutlineNode(statusFor: .root, message: "")

  private func statusNode(for key: FolderKey, message: String) -> OutlineNode {
    if let existing = statusNodes[key] {
      existing.message = message
      return existing
    }
    let node = OutlineNode(statusFor: key, message: message)
    statusNodes[key] = node
    return node
  }
}

extension BrowserViewController: NSUserInterfaceValidations {
  /// Enables menu and toolbar items only when their action can do something.
  public func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    switch item.action {
    case #selector(goBack(_:)):
      return model.canGoBack
    case #selector(goForward(_:)):
      return model.canGoForward
    case #selector(goToEnclosingFolder(_:)):
      return model.enclosingFolder != nil
    case #selector(openSelection(_:)):
      if model.viewMode != .list {
        return singleSelectedItem?.isNavigable == true
      }
      guard outlineView.selectedRowIndexes.count == 1 else { return false }
      let node = outlineView.item(atRow: outlineView.selectedRow) as? OutlineNode
      return node?.item?.isNavigable == true
    case #selector(copyPath(_:)):
      return !itemsToCopyPaths.isEmpty
    case #selector(showAsList(_:)):
      (item as? NSMenuItem)?.state = model.viewMode == .list ? .on : .off
      return true
    case #selector(showAsIcons(_:)):
      (item as? NSMenuItem)?.state = model.viewMode == .icons ? .on : .off
      return true
    case #selector(showAsColumns(_:)):
      (item as? NSMenuItem)?.state = model.viewMode == .columns ? .on : .off
      return true
    case #selector(toggleFoldersFirst(_:)):
      (item as? NSMenuItem)?.state = model.sort.foldersFirst ? .on : .off
      return true
    default:
      return true
    }
  }
}

extension BrowserViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
  // MARK: Rows

  public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    guard let node = item as? OutlineNode else { return model.items.count }
    guard !node.isStatus else { return 0 }
    // A folder that could not be listed has one row that says why.
    if model.failure(of: node.key) != nil { return 1 }
    return model.children(of: node.key).count
  }

  public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?)
    -> Any
  {
    guard let parent = item as? OutlineNode else {
      guard model.items.indices.contains(index) else { return Self.staleRow }
      let row = model.items[index]
      return node(for: FolderKey.root.appending(row.name), item: row)
    }
    if let reason = model.failure(of: parent.key) {
      return statusNode(for: parent.key, message: reason)
    }
    let rows = model.children(of: parent.key)
    guard rows.indices.contains(index) else { return Self.staleRow }
    return node(for: parent.key.appending(rows[index].name), item: rows[index])
  }

  public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    guard !model.isShowingVirtualLocation else { return false }
    return (item as? OutlineNode)?.item?.isNavigable ?? false
  }

  public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
    (item as? OutlineNode)?.isStatus == false
  }

  /// What typing selects by: the item's name. A status row is not found.
  public func outlineView(
    _ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any
  ) -> String? {
    (item as? OutlineNode)?.item?.name
  }

  public func outlineView(
    _ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any
  ) -> NSView? {
    guard let tableColumn, let node = item as? OutlineNode,
      let column = Column.allCases.first(where: { $0.identifier == tableColumn.identifier })
    else { return nil }

    // A reuse identifier for the outline's cell cache, not an accessibility identity.
    let cellIdentifier = NSUserInterfaceItemIdentifier(rawValue: "cell-\(column.rawValue)")
    let cell =
      outlineView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
      ?? Self.makeCell(identifier: cellIdentifier, column: column)
    if let message = node.message, node.isStatus {
      Self.fill(cell, column: column, statusMessage: message)
    } else if let rowItem = node.item {
      Self.fill(cell, column: column, item: rowItem)
    }
    return cell
  }

  private static func makeCell(identifier: NSUserInterfaceItemIdentifier, column: Column)
    -> NSTableCellView
  {
    let cell = NSTableCellView()
    cell.identifier = identifier
    let label = NSTextField(labelWithString: "")
    label.lineBreakMode = column == .name ? .byTruncatingMiddle : .byTruncatingTail
    label.alignment = [.size, .sizeOnDisk].contains(column) ? .right : .natural
    label.applyIdentifier(of: column.accessibility)
    label.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(label)
    cell.textField = label
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
      label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }

  // MARK: What the user does

  public func outlineViewSelectionDidChange(_ notification: Notification) {
    guard !isApplyingModelState else { return }
    model.selection = Set(
      outlineView.selectedRowIndexes.compactMap {
        (outlineView.item(atRow: $0) as? OutlineNode)?.item?.url
      })
  }

  /// A folder opened by the user is opened in the model, which lists it. Not
  /// a move: history, the title and tabs are untouched.
  public func outlineViewItemDidExpand(_ notification: Notification) {
    guard !isApplyingModelState,
      let node = notification.userInfo?["NSObject"] as? OutlineNode, !node.isStatus
    else { return }
    model.openFolder(node.key)
  }

  public func outlineViewItemDidCollapse(_ notification: Notification) {
    guard !isApplyingModelState,
      let node = notification.userInfo?["NSObject"] as? OutlineNode, !node.isStatus
    else { return }
    model.closeFolder(node.key)
  }

  /// A click on a column header sorts every level by that column.
  public func outlineView(
    _ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
  ) {
    guard !isApplyingModelState, let first = outlineView.sortDescriptors.first,
      let key = first.key, let column = Column(rawValue: key)
    else { return }
    model.changeSort(
      to: FileItemSort(
        key: column.sortKey, ascending: first.ascending, foldersFirst: model.sort.foldersFirst))
  }
}

extension BrowserViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
  public func collectionView(
    _ collectionView: NSCollectionView, numberOfItemsInSection section: Int
  ) -> Int {
    model.items.count
  }

  public func collectionView(
    _ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath
  ) -> NSCollectionViewItem {
    let cell = collectionView.makeItem(withIdentifier: IconItem.reuseIdentifier, for: indexPath)
    // A stale index, as the outline can be asked for: the cell stays empty
    // and the reload that follows replaces it.
    guard let icon = cell as? IconItem, model.items.indices.contains(indexPath.item) else {
      return cell
    }
    let item = model.items[indexPath.item]
    icon.configure(item: item, icon: genericIcons.icon(for: item))
    return icon
  }

  public func collectionView(
    _ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem,
    forRepresentedObjectAt indexPath: IndexPath
  ) {
    let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    (item as? IconItem)?.startLoading(with: thumbnailLoader, scale: scale)
  }

  public func collectionView(
    _ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem,
    forRepresentedObjectAt indexPath: IndexPath
  ) {
    (item as? IconItem)?.stopLoading()
  }

  public func collectionView(
    _ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>
  ) {
    iconSelectionChanged()
  }

  public func collectionView(
    _ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>
  ) {
    iconSelectionChanged()
  }
}
