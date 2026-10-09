import AppKit
import FileSystemCore

/// Shows the contents of one folder as a list with name, size and modified
/// date. Every pane hosts one of these.
@MainActor
public final class BrowserViewController: NSViewController {
  private enum Column: String, CaseIterable {
    case name, size, modified

    var identifier: NSUserInterfaceItemIdentifier { .init("column-\(rawValue)") }

    var title: String {
      switch self {
      case .name: "Name"
      case .size: "Size"
      case .modified: "Date Modified"
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
    container.identifier = NSUserInterfaceItemIdentifier("browser-view")

    for column in Column.allCases {
      let tableColumn = NSTableColumn(identifier: column.identifier)
      tableColumn.title = column.title
      tableColumn.width = column.width
      tableColumn.minWidth = 60
      tableView.addTableColumn(tableColumn)
    }
    tableView.identifier = NSUserInterfaceItemIdentifier("file-list")
    tableView.setAccessibilityIdentifier("file-list")
    tableView.setAccessibilityLabel("Files")
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

    statusLabel.identifier = NSUserInterfaceItemIdentifier("browser-status")
    statusLabel.setAccessibilityIdentifier("browser-status")
    statusLabel.alignment = .center
    statusLabel.textColor = .secondaryLabelColor
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
    run { await $0.navigateToEnclosingFolder() }
  }

  @objc private func openClickedRow(_ sender: Any?) {
    open(row: tableView.clickedRow)
  }

  private func open(row: Int) {
    guard model.items.indices.contains(row) else { return }
    let item = model.items[row]
    run { await $0.open(item) }
  }

  /// Runs a model action, cancelling one that is still loading.
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

  static func sizeText(for item: FileItem) -> String {
    guard let size = item.size else { return "--" }
    return size.formatted(.byteCount(style: .file))
  }

  static func modifiedText(for item: FileItem) -> String {
    guard let date = item.modificationDate else { return "--" }
    return date.formatted(date: .abbreviated, time: .shortened)
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

    let cellIdentifier = NSUserInterfaceItemIdentifier("cell-\(column.rawValue)")
    let cell =
      tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
      ?? Self.makeCell(identifier: cellIdentifier, column: column)

    let text =
      switch column {
      case .name: item.name
      case .size: Self.sizeText(for: item)
      case .modified: Self.modifiedText(for: item)
      }
    cell.textField?.stringValue = text
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
    label.setAccessibilityIdentifier("\(column.rawValue)-text")
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
