import AppKit
import FileSystemCore

/// Shows the contents of one folder as a list with name, size and modified
/// date. Every pane hosts one of these.
@MainActor
public final class BrowserViewController: NSViewController {
  enum Column: String, CaseIterable {
    case name, size, modified

    var identifier: NSUserInterfaceItemIdentifier { .init("column-\(rawValue)") }

    var title: String {
      switch self {
      case .name: "Name"
      case .size: "Size"
      case .modified: "Date Modified"
      }
    }

    var accessibility: AccessibilityElement {
      switch self {
      case .name: .nameCell
      case .size: .sizeCell
      case .modified: .modifiedCell
      }
    }

    /// What VoiceOver says in place of the dashes shown for a missing value.
    var missingValueSpokenText: String {
      switch self {
      case .name: "No name"
      case .size: "No size"
      case .modified: "No date"
      }
    }

    var width: CGFloat {
      switch self {
      case .name: 420
      case .size: 110
      case .modified: 200
      }
    }
  }

  public let model: BrowserModel

  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let statusLabel = NSTextField(wrappingLabelWithString: "")
  /// The model action in flight, if any. Tests await it.
  private(set) var loadTask: Task<Void, Never>?

  public var location: URL { model.location }

  public init(location: URL, reader: any DirectoryReading = DirectoryReader()) {
    model = BrowserModel(location: location, reader: reader)
    super.init(nibName: nil, bundle: nil)
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
      tableView.addTableColumn(tableColumn)
    }
    tableView.apply(.fileList)
    tableView.style = .fullWidth
    tableView.usesAlternatingRowBackgroundColors = true
    tableView.allowsMultipleSelection = true
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.doubleAction = #selector(openClickedRow(_:))

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    statusLabel.applyIdentifier(of: .browserStatus)
    statusLabel.alignment = .center
    // Primary label color: the secondary color fails the contrast audit.
    statusLabel.textColor = .labelColor
    statusLabel.isHidden = true
    statusLabel.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(scrollView)
    container.addSubview(statusLabel)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: container.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      statusLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      statusLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      statusLabel.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -40),
    ])
    view = container
  }

  public override func viewDidLoad() {
    super.viewDidLoad()
    model.onChange = { [weak self] in self?.modelDidChange() }
    modelDidChange()
    run { await $0.load() }
  }

  public override func viewDidAppear() {
    super.viewDidAppear()
    updateTitle()
    view.window?.makeFirstResponder(tableView)
  }

  // MARK: Actions

  /// Opens the selected item. Sent by File > Open through the responder chain.
  @objc public func openSelection(_ sender: Any?) {
    open(row: tableView.selectedRow)
  }

  /// Shows the folder that contains the current one. Sent by Go > Enclosing Folder.
  @objc public func goToEnclosingFolder(_ sender: Any?) {
    // At the root there is nowhere to go, so a load under way is left to finish.
    guard model.enclosingFolder != nil else { return }
    run { await $0.navigateToEnclosingFolder() }
  }

  @objc private func openClickedRow(_ sender: Any?) {
    open(row: tableView.clickedRow)
  }

  private func open(row: Int) {
    guard model.items.indices.contains(row) else { return }
    let item = model.items[row]
    // Opening a file does nothing yet, so a load under way is left to finish.
    guard item.isNavigable else { return }
    run { await $0.open(item) }
  }

  /// Runs a model action that loads a folder, cancelling a load that is still
  /// under way. An action that would do nothing must not come through here:
  /// the cancelled load never publishes a result, so the browser would stay
  /// in its loading state.
  private func run(_ action: @escaping @MainActor (BrowserModel) async -> Void) {
    loadTask?.cancel()
    loadTask = Task { [model] in await action(model) }
  }

  // MARK: Drawing the model

  private func modelDidChange() {
    updateTitle()
    tableView.reloadData()
    tableView.deselectAll(nil)

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

  /// Names the controller and its window after the folder. The window is set
  /// directly because it does not follow a title that changes after it opens.
  private func updateTitle() {
    let folderName = Self.title(for: model.location)
    title = folderName
    view.window?.title = folderName
  }

  static func title(for location: URL) -> String {
    location.path == "/" ? "/" : location.lastPathComponent
  }

  /// Shown where an item has no value, as Finder does for a folder's size.
  static let missingValueText = "--"

  /// The size as text, or nil for an item that has none, such as a folder.
  static func sizeText(for item: FileItem) -> String? {
    item.size?.formatted(.byteCount(style: .file))
  }

  /// The modified date as text, or nil for an item that has none.
  static func modifiedText(for item: FileItem) -> String? {
    item.modificationDate?.formatted(date: .abbreviated, time: .shortened)
  }

  /// Fills a cell, new or recycled, with one item's value for a column.
  static func fill(_ cell: NSTableCellView, column: Column, item: FileItem) {
    let value: String? =
      switch column {
      case .name: item.name
      case .size: sizeText(for: item)
      case .modified: modifiedText(for: item)
      }
    cell.textField?.stringValue = value ?? missingValueText
    // Dashes are not words, so both the cell and its text get a spoken
    // replacement. Whether a value is missing comes from the item, never from
    // the text shown: a file can be named "--".
    let spokenText = value == nil ? column.missingValueSpokenText : nil
    cell.setSpokenText(spokenText)
    cell.textField?.setSpokenText(spokenText)
  }
}

extension BrowserViewController: NSTableViewDataSource, NSTableViewDelegate {
  public func numberOfRows(in tableView: NSTableView) -> Int {
    model.items.count
  }

  public func tableView(
    _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
  ) -> NSView? {
    guard let tableColumn,
      let column = Column.allCases.first(where: { $0.identifier == tableColumn.identifier }),
      model.items.indices.contains(row)
    else { return nil }
    let item = model.items[row]

    // A reuse identifier for the table's cell cache, not an accessibility identity.
    let cellIdentifier = NSUserInterfaceItemIdentifier(rawValue: "cell-\(column.rawValue)")
    let cell =
      tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
      ?? Self.makeCell(identifier: cellIdentifier, column: column)
    Self.fill(cell, column: column, item: item)
    return cell
  }

  private static func makeCell(identifier: NSUserInterfaceItemIdentifier, column: Column)
    -> NSTableCellView
  {
    let cell = NSTableCellView()
    cell.identifier = identifier
    let label = NSTextField(labelWithString: "")
    label.lineBreakMode = column == .name ? .byTruncatingMiddle : .byTruncatingTail
    label.alignment = column == .size ? .right : .natural
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
}
